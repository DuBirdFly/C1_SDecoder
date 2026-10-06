// =============================================================================
// sdtlb_tag: SDTLB 的 Tag 段 (全相联 CAM), SDTLB_ENTRIES 个 sdtlb_tag_item 的阵列
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   1. 查表: 把请求地址广播给全部条目并行比较, 输出逐条目命中位与命中条目下标.
//   2. 装填: 接收 SDPTW 在 DONE 状态给出的 Page Walk 结果, 按轮转替换指针写入一个条目.
//   3. 无效化: 把刷新接口的置无效广播给全部条目.
//
// 层次与约定:
//   - 逐条目的 req_hit 输出给同下标的 sdtlb_data 条目当 rd_sel, 由顶层 (sdtlb) 连线;
//     本条目的数据段 (EID / TokenID / S_PFN / Grn) 不在本模块, 见 sdtlb_data.
//   - 命中下标是优先级编码: 正常配置下最多命中一个条目, 若多命中则取索引最小的
//     (设计方案 §命中判断). "多命中记状态位" 属可选项, 首版不做.
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (设计方案 §设计原则 4):
//     本模块没有软件写口, fill_* 只接 SDPTW 的结果.
//   - 替换策略: 轮转指针只在装填时使用 (设计方案 §替换策略), 指向最久没有被填充过的条目;
//     该条目若仍有效就被直接覆盖 (由条目内的写入逻辑完成, 无需先清位). fill_idx 是本轮
//     装填的下标, 顶层拿它去写 sdtlb_data 的同下标条目.
//   - 无效化与装填的竞争: 同一条目同一拍既刷新又装填时, 条目内部让刷新优先;
//     "无效化期间禁止回填" 的全局阻塞由顶层按 cfg_inv_busy 做 (设计方案 §与 SDTLB 的配合).
// =============================================================================
`default_nettype none

module sdtlb_tag
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 代换请求: 广播给全部条目做比较
    input  logic                        req_vld,
    input  logic [PA_WIDTH-1:0]         req_pa,
    output logic [SDTLB_ENTRIES-1:0]    req_hit,        // 逐条目命中, 给 sdtlb_data 当 rd_sel
    output logic                        req_hit_vld,    // 有命中 (未命中时下标无意义)
    output logic [IDX_WIDTH-1:0]        req_hit_idx,    // 命中条目下标, 多命中取最小

    // 装填端口: 接 SDPTW 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目
    input  logic                        fill_vld,       // 装填使能
    input  logic [16:0]                 fill_pa_base,   // 段空间基地址 (以 1 GB 对界)
    input  logic [ 4:0]                 fill_pa_up,     // 段空间上界 (含, 以 1 GB 对界)
    output logic [IDX_WIDTH-1:0]        fill_idx,       // 本轮装填到哪个条目

    // 无效化 (刷新) 端口: 广播给全部条目, 条目内优先于装入
    input  logic                        inv_all,        // 置无效全部条目
    input  logic                        inv_en,         // 按地址置无效使能
    input  logic [PA_WIDTH-1:0]         inv_pa          // 按地址置无效的地址
);

    // -------------------------------------------------------------------------
    // 替换指针 (轮转): 指向最久没有被填充过的条目, 只在装填时自增.
    // IDX_WIDTH 位自然回绕, 即 0 -> 1 -> ... -> SDTLB_ENTRIES-1 -> 0.
    // -------------------------------------------------------------------------
    logic [IDX_WIDTH-1:0] fill_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_ptr <= '0;
        end
        else if (fill_vld) begin
            fill_ptr <= fill_ptr + 1'b1;
        end
    end

    assign fill_idx = fill_ptr;

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个 Tag 条目: 请求与刷新广播, 装填按 fill_ptr 译码后只写中一条
    // (条目内写入使能就是有效位, 因此被选中的条目写完后即为有效)
    // -------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < SDTLB_ENTRIES; i = i + 1) begin : g_tag_item
            sdtlb_tag_item u_tag_item (
                .clk        (clk),
                .rst_n      (rst_n),
                .req_vld    (req_vld),
                .req_pa     (req_pa),
                .req_hit    (req_hit[i]),
                .wr_pa_base (fill_pa_base),
                .wr_pa_up   (fill_pa_up),
                .wr_pa_vld  (fill_vld && (fill_ptr == i)),
                .inv_all    (inv_all),
                .inv_en     (inv_en),
                .inv_pa     (inv_pa)
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 命中优先级编码: 从最高下标往低扫, 低下标最后赋值, 于是多命中时取索引最小的条目
    // -------------------------------------------------------------------------
    assign req_hit_vld = |req_hit;

    always_comb begin
        req_hit_idx = '0;       // 未命中时给 0, 上层以 req_hit_vld 判断是否有效
        for (int j = SDTLB_ENTRIES - 1; j >= 0; j--) begin
            if (req_hit[j]) begin
                req_hit_idx = j[IDX_WIDTH-1:0];
            end
        end
    end

endmodule

`default_nettype wire
