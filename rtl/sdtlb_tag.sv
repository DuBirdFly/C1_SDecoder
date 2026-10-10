// =============================================================================
// sdtlb_tag: SDTLB 的 Tag 段阵列 (SDTLB_ENTRIES 个 sdtlb_tag_item)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   1. 查表: 把请求地址广播给全部条目并行比较, 输出逐条目命中向量.
//   2. 装填: 用 common 下的 round_robin_arbiter 轮转选址 (一次只选中一条), 输出该选中给
//      Data 段阵列.
//   3. 置无效: 把刷新请求广播给全部条目 (条目内优先于装填).
//
// 层次与约定:
//   - Tag 段与 Data 段各自独立成阵列模块 (sdtlb_tag / sdtlb_data), 是为了后续可能的
//     RAM/SRAM 阵列替换: 换实现时只改本模块内部, sdtlb 的端口与连线不变. 写接口用
//     "写有效 + 下标 + 数据" 的 RAM 写形式, 读接口仍是全并行比较 (CAM 语义).
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (§设计原则 4).
//   - 替换策略: 轮转选中只在装填时步进, 指向最久没有被填充过的条目 (§替换策略);被选中
//     的条目若仍有效就被直接覆盖 (由条目内的写入逻辑完成). 轮转逻辑本身在 common 下的
//     [round_robin_arbiter](common/round_robin_arbiter.sv).
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
    input  logic                                fill_vld,
    input  logic [16:0]                         fill_pa_base,
    input  logic [ 4:0]                         fill_pa_up,
    output logic [SDTLB_ENTRIES-1:0]            fill_sel,    // 本轮装填的 one-hot 选中, 给 Data 段阵列

    // 置无效 (刷新) 请求, 优先于装填
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_WIDTH-1:0]                 inv_pa
);

    // 轮转选中: 只在装填时步进, 输出 one-hot 的 fill_sel (本轮只写中一条), 同一根向量
    // 也给 Data 段阵列做写选中
    round_robin_arbiter #(
        .N (SDTLB_ENTRIES)
    ) u_fill_arb (
        .clk   (clk),
        .rst_n (rst_n),
        .step  (fill_vld),
        .sel   (fill_sel)
    );

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个 Tag 条目: 请求与刷新广播, 装填按 fill_sel 只写中一条
    // -------------------------------------------------------------------------
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : genvar_tag_item
            sdtlb_tag_item u_tag_item (
                .clk          (clk),
                .rst_n        (rst_n),
                .req_vld      (req_vld),
                .req_pa       (req_pa),
                .req_hit      (req_hit[genvar_i]),
                .fill_pa_base (fill_pa_base),
                .fill_pa_up   (fill_pa_up),
                .fill_pa_vld  (fill_sel[genvar_i]),
                .inv_all      (inv_all),
                .inv_en       (inv_en),
                .inv_pa       (inv_pa)
            );
        end
    endgenerate

`ifdef ASSERT_ON
    `assert_clk(a_req_hit_onehot0, $onehot0(req_hit));
`endif

endmodule

`default_nettype wire
