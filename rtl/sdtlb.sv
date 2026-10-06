// =============================================================================
// sdtlb: SDTLB (SDecoder 代换快表), 全相联结构, SDTLB_ENTRIES 个条目
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   每个条目 = 一份 Tag (段空间基址 / 上界 / 有效位, 存于 CAM) + 一份 Data
//   (EID / TokenID / S_PFN / Grn). 本模块只做三件事:
//   1. 查表: 请求交给 Tag 段阵列比较, 对命中向量做优先级编码 (多命中取最小) 与命中
//      有效判断, 再用命中下标从 Data 段阵列读出该条目的数据.
//   2. 装填: 把 SDPTW 在 DONE 状态给出的 Page Walk 结果转给两个阵列, 由 Tag 段阵列的
//      轮转替换指针给出下标, Tag 与 Data 同下标写入.
//   3. 置无效: 转给 Tag 段阵列 (Data 段没有有效位).
//
// 层次与约定:
//   - Tag 段与 Data 段各自是独立阵列模块 (sdtlb_tag / sdtlb_data), 便于后续把阵列换成
//     RAM/SRAM 实现: 替换时只改阵列模块内部, 本模块的端口与连线不变.
//   - 读出用 "命中有效 + 命中下标" 的地址读形式 (与 RAM 一致), 未命中输出全 0.
//     注意多命中时读出的是下标最小那条的数据 —— 按构造不应出现多命中, 已由
//     sdtlb_tag 里的宽松独热断言守住.
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (§设计原则 4).
//   - 本模块到 "命中下标 + 命中条目数据" 为止: SLA 计算与 SMD 组装, 以及未命中后的
//     未命中队列 / Page Walk 流程, 由上层负责.
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
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0] fill_idx;   // 本轮装填下标 (Tag 段阵列给出)

    // Tag 段阵列: 比较 / 装填选址 / 置无效
    sdtlb_tag u_sdtlb_tag (
        .clk        (clk),
        .rst_n      (rst_n),
        .req_vld    (req_vld),
        .req_pa     (req_pa),
        .req_hit    (req_hit),
        .wr_vld     (wr_vld),
        .wr_pa_base (wr_pa_base),
        .wr_pa_up   (wr_pa_up),
        .fill_idx   (fill_idx),
        .inv_all    (inv_all),
        .inv_en     (inv_en),
        .inv_pa     (inv_pa)
    );

    // Data 段阵列: 与 Tag 段同下标写入, 按命中下标读出
    sdtlb_data u_sdtlb_data (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_vld      (wr_vld),
        .wr_idx      (fill_idx),
        .wr_eid      (wr_eid),
        .wr_token_id (wr_token_id),
        .wr_s_pfn    (wr_s_pfn),
        .wr_grn      (wr_grn),
        .rd_vld      (req_hit_vld),
        .rd_idx      (req_hit_idx),
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

endmodule

`default_nettype wire
