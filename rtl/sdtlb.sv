// =============================================================================
// sdtlb: SDTLB (SDecoder 代换快表), 全相联结构, SDTLB_ENTRIES 个条目
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   每个条目 = 一份 Tag (段空间基址 / 上界 / 有效位, 存于 CAM) + 一份 Data
//   (EID / TokenID / S_PFN / Grn). 本模块做四件事:
//   1. 查表: 请求交给 Tag 段阵列比较, 对命中向量做优先级编码 (多命中取最小) 与命中
//      有效判断, 再用命中下标从 Data 段阵列读出该条目的数据.
//   2. SLA 计算: 命中条目的 S_PFN 加上 1GB 段内偏移得到 SLA[47:0]; 加法进位时报
//      rd_sla_ovf (地址非法异常, 设计方案 §代换结果计算).
//   3. 装填: 把 SDPTW 在 DONE 状态给出的 Page Walk 结果转给两个阵列, 由 Tag 段阵列的
//      轮转替换指针给出下标, Tag 与 Data 同下标写入.
//   4. 置无效: 转给 Tag 段阵列 (Data 段没有有效位).
//
// 层次与约定:
//   - Tag 段与 Data 段各自是独立阵列模块 (sdtlb_tag / sdtlb_data), 各自可以独立演进.
//   - Data 段的读写选中都是 SDTLB_ENTRIES 位 one-hot (自然的全相联形式, 不为 RAM 形式
//     预留地址口): 写选中由 Tag 段的轮转指针译码而来, 读选中直接用 Tag 段的命中向量,
//     未命中时向量全 0, 读出自然全 0.
//   - 命中下标 (req_hit_idx) 做优先级编码 (多命中取最小) 供上层观测; 数据通路不依赖它,
//     所以多命中时读出的是各命中条目数据的按位或 (按构造不应出现多命中, 已由 sdtlb_tag
//     里的宽松独热断言守住).
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (§设计原则 4).
//   - 本模块到 "命中下标 + 命中条目数据 + SLA" 为止: SMD 三元组的组装与异常码上报,
//     以及未命中后的未命中队列 / Page Walk 流程, 由上层负责.
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 查表 (组合)
    input  logic                                req_vld,
    input  logic [PA_WIDTH-1:0]                 req_pa,
    output logic                                req_hit_vld,    // 有命中
    output logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  req_hit_idx,    // 命中下标, 多命中取最小

    // 命中条目的数据 (未命中时为 0)
    output logic [10:0]                         rd_eid,
    output logic [ 9:0]                         rd_token_id,
    output logic [17:0]                         rd_s_pfn,
    output logic                                rd_grn,

    // 命中条目算出的 SLA
    output logic [SLA_WIDTH-1:0]                rd_sla,         // SLA[47:0]
    output logic                                rd_sla_ovf,     // SLA 加法溢出 -> 地址非法

    // 装填: 接 SDPTW 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目
    input  logic                                wr_vld,
    input  logic [16:0]                         wr_pa_base,     // Tag: 段空间基地址, 以 1 GB 对界
    input  logic [ 4:0]                         wr_pa_up,       // Tag: 段空间上界 (含)
    input  logic [10:0]                         wr_eid,         // Data: Entity 标识
    input  logic [ 9:0]                         wr_token_id,    // Data: 逻辑池标识
    input  logic [17:0]                         wr_s_pfn,       // Data: SLA 基址, 以 1 GB 对界
    input  logic                                wr_grn,         // Data: 粒度位, 1 段式 0 页式

    // 置无效 (刷新): 只作用于 Tag 侧的有效位
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_WIDTH-1:0]                 inv_pa
);

    logic [SDTLB_ENTRIES-1:0]           req_hit;    // Tag 段阵列的逐条目命中
    logic [SDTLB_ENTRIES-1:0]           fill_sel;   // 本轮装填的 one-hot 选中 (Tag 段阵列给出)
    logic [16:0]                        hit_pa_base;// 命中条目的段空间基址

    // Tag 段阵列: 比较 / 装填选址 / 置无效 / 命中条目的段基址读出
    sdtlb_tag u_sdtlb_tag (
        .clk        (clk),
        .rst_n      (rst_n),
        .req_vld    (req_vld),
        .req_pa     (req_pa),
        .req_hit    (req_hit),
        .rd_pa_base (hit_pa_base),
        .wr_vld     (wr_vld),
        .wr_pa_base (wr_pa_base),
        .wr_pa_up   (wr_pa_up),
        .fill_sel   (fill_sel),
        .inv_all    (inv_all),
        .inv_en     (inv_en),
        .inv_pa     (inv_pa)
    );

    // Data 段阵列: 与 Tag 段同条目写入 (fill_sel 作 one-hot 写使能), 按命中向量读出
    sdtlb_data u_sdtlb_data (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_vld      (fill_sel),
        .wr_eid      (wr_eid),
        .wr_token_id (wr_token_id),
        .wr_s_pfn    (wr_s_pfn),
        .wr_grn      (wr_grn),
        .rd_sel      (req_hit),
        .rd_eid      (rd_eid),
        .rd_token_id (rd_token_id),
        .rd_s_pfn    (rd_s_pfn),
        .rd_grn      (rd_grn)
    );

    // -------------------------------------------------------------------------
    // 命中下标: 从最高下标往低扫, 低下标最后赋值, 于是多命中时取索引最小的条目
    // -------------------------------------------------------------------------
    assign req_hit_vld = |req_hit;

    always_comb begin
        req_hit_idx = '0;       // 未命中时给 0, 上层以 req_hit_vld 判断是否有效
        for (int i = SDTLB_ENTRIES - 1; i >= 0; i--) begin
            if (req_hit[i]) begin
                req_hit_idx = i[SDTLB_ENTRIES_IDX_WIDTH-1:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // SLA 计算 (设计方案 §代换结果计算): 段式与页式共用同一公式, 页式条目的
    // pa_base[34:30] == pa_up, 段内偏移自然为 0
    //   PA_Offset[34:30] = req_pa[34:30] - pa_base[34:30]
    //   SLA[47:30]       = S_PFN[47:30] + PA_Offset[34:30]  (进位 => 地址非法异常)
    //   SLA[47:0]        = {SLA[47:30], req_pa[29:0]}
    // 未命中时 (req_hit_vld = 0) 偏移按 0 算, SLA 与溢出标志都给 0
    // -------------------------------------------------------------------------
    logic [ 4:0] pa_offset;     // 1GB 段内偏移
    logic [18:0] sla_hi_sum;    // {1'b0, S_PFN} + {14'h0, 偏移}, 最高位是进位

    assign pa_offset  = req_hit_vld ? (req_pa[34:30] - hit_pa_base[4:0]) : 5'h0;
    assign sla_hi_sum = {1'b0, rd_s_pfn} + {14'h0, pa_offset};

    assign rd_sla_ovf = req_hit_vld && sla_hi_sum[18];
    assign rd_sla     = req_hit_vld ? {sla_hi_sum[17:0], req_pa[29:0]} : '0;

    // -------------------------------------------------------------------------
    // 装填合法性: pa_up 是段空间上界 (含), 不能低于基址的页号, 否则区间为空 —— 这样的
    // 条目永远命中不了 (设计方案 §命中判断 的闭区间). 上界本身是 5 bit 页号, 不会越界,
    // 所以这里只需要守住"非空"这一条
    // -------------------------------------------------------------------------
`ifdef ASSERT_ON
    `assert_clk(a_wr_pa_range_valid, (wr_vld == 1'b0) || (wr_pa_up >= wr_pa_base[4:0]));
`endif

endmodule

`default_nettype wire
