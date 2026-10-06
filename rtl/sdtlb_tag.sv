// =============================================================================
// sdtlb_tag: SDTLB 的 Tag 段阵列 (SDTLB_ENTRIES 个 sdtlb_tag_item)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   1. 查表: 把请求地址广播给全部条目并行比较, 输出逐条目命中向量.
//   2. 装填: 按内部轮转替换指针选址, 一次写入一条, 并输出该下标给 Data 段阵列.
//   3. 置无效: 把刷新请求广播给全部条目 (条目内优先于装填).
//
// 层次与约定:
//   - Tag 段与 Data 段各自独立成阵列模块 (sdtlb_tag / sdtlb_data), 是为了后续可能的
//     RAM/SRAM 阵列替换: 换实现时只改本模块内部, sdtlb 的端口与连线不变. 写接口用
//     "写有效 + 下标 + 数据" 的 RAM 写形式, 读接口仍是全并行比较 (CAM 语义).
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (§设计原则 4).
//   - 替换策略: 轮转指针只在装填时使用, 指向最久没有被填充过的条目 (§替换策略);
//     被选中的条目若仍有效就被直接覆盖 (由条目内的写入逻辑完成).
//   - 命中向量的宽松独热断言放在本模块: 它是命中向量的产生者 (§命中判断).
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 广播给全部条目做比较
    input  logic                                req_vld,
    input  logic [PA_WIDTH-1:0]                 req_pa,
    output logic [SDTLB_ENTRIES-1:0]            req_hit,     // 逐条目命中

    // 装填请求: 一次一条, 由内部轮转指针选址
    input  logic                                wr_vld,
    input  logic [16:0]                         wr_pa_base,
    input  logic [ 4:0]                         wr_pa_up,
    output logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  fill_idx,    // 本轮装填下标, 给 Data 段阵列

    // 置无效 (刷新) 请求, 优先于装填
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_WIDTH-1:0]                 inv_pa
);

    // 轮转替换指针: 指向最久没有被填充过的条目, 只在装填时自增 (位宽自然回绕)
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0] fill_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_ptr <= '0;
        end
        else if (wr_vld) begin
            fill_ptr <= fill_ptr + 1'b1;
        end
    end

    assign fill_idx = fill_ptr;

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个 Tag 条目: 请求与刷新广播, 装填按 fill_ptr 译码后只写中一条
    // -------------------------------------------------------------------------
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : genvar_tag_item
            sdtlb_tag_item u_tag_item (
                .clk        (clk),
                .rst_n      (rst_n),
                .req_vld    (req_vld),
                .req_pa     (req_pa),
                .req_hit    (req_hit[genvar_i]),
                .wr_pa_base (wr_pa_base),
                .wr_pa_up   (wr_pa_up),
                .wr_pa_vld  (wr_vld && (fill_ptr == genvar_i)),
                .inv_all    (inv_all),
                .inv_en     (inv_en),
                .inv_pa     (inv_pa)
            );
        end
    endgenerate

`ifdef ASSERT_ON
    `assert_clk(a_req_hit_onehot0, $onehot0(req_hit));
`endif

endmodule

`default_nettype wire
