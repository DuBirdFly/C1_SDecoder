// =============================================================================
// sdtlb_data: SDTLB 的 Data 段阵列 (SDTLB_ENTRIES 个 sdtlb_data_item)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   1. 装填: 与 Tag 段同下标写入一条 (EID / TokenID / S_PFN / Grn).
//   2. 读出: 按命中下标读出该条目的数据 (组合), 未命中时输出全 0.
//
// 层次与约定:
//   - 与 sdtlb_tag 分开成阵列模块, 是为了后续可能的 RAM/SRAM 阵列替换: 现在内部是
//     "逐条目门控读出 + 逐位 OR", 换成单读端口 RAM 时只改本模块内部 —— 读接口已经是
//     "读有效 + 读下标" 的地址读形式, 写接口是 "写有效 + 写下标 + 写数据".
//   - 数据段没有有效位: 条目是否有效由同下标 Tag 条目表示, 因此本模块没有置无效端口;
//     读出用 rd_vld 门控, 未命中时即使读下标指向某个条目也不输出它的数据.
//   - 读出目前是纯组合的 (比较与读数据同拍, 下一拍算 SLA, 对应设计方案 "命中 2 拍").
//     若后续换成同步读 RAM (读数据下一拍), 命中通路会多一拍, 需同步改设计方案
//     §性能预期 的口径.
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_data
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 装填请求: 与 Tag 段同下标写入
    input  logic                                wr_vld,
    input  logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  wr_idx,
    input  logic [10:0]                         wr_eid,
    input  logic [ 9:0]                         wr_token_id,
    input  logic [17:0]                         wr_s_pfn,
    input  logic                                wr_grn,

    // 读出请求: 命中有效 + 命中下标
    input  logic                                rd_vld,
    input  logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  rd_idx,
    output logic [10:0]                         rd_eid,
    output logic [ 9:0]                         rd_token_id,
    output logic [17:0]                         rd_s_pfn,
    output logic                                rd_grn
);

    // 每个条目的读出 (未选中时为 0), 汇总后即为命中条目的数据
    logic [10:0] rd_eid_item      [SDTLB_ENTRIES];
    logic [ 9:0] rd_token_id_item [SDTLB_ENTRIES];
    logic [17:0] rd_s_pfn_item    [SDTLB_ENTRIES];
    logic        rd_grn_item      [SDTLB_ENTRIES];

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个 Data 条目: 写使能由 wr_idx 译码; 读选中由 rd_idx 译码
    // (换成 RAM 时, 这两处译码分别对应写地址与读地址)
    // -------------------------------------------------------------------------
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : genvar_data_item
            sdtlb_data_item u_data_item (
                .clk         (clk),
                .rst_n       (rst_n),
                .wr_vld      (wr_vld && (wr_idx == genvar_i)),
                .wr_eid      (wr_eid),
                .wr_token_id (wr_token_id),
                .wr_s_pfn    (wr_s_pfn),
                .wr_grn      (wr_grn),
                .rd_sel      (rd_vld && (rd_idx == genvar_i)),
                .rd_eid      (rd_eid_item[genvar_i]),
                .rd_token_id (rd_token_id_item[genvar_i]),
                .rd_s_pfn    (rd_s_pfn_item[genvar_i]),
                .rd_grn      (rd_grn_item[genvar_i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 命中数据汇总: 每个条目未选中时输出 0, 逐位 OR 起来就是命中条目的数据
    // -------------------------------------------------------------------------
    always_comb begin
        rd_eid      = '0;
        rd_token_id = '0;
        rd_s_pfn    = '0;
        rd_grn      = 1'b0;
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            rd_eid      = rd_eid      | rd_eid_item[i];
            rd_token_id = rd_token_id | rd_token_id_item[i];
            rd_s_pfn    = rd_s_pfn    | rd_s_pfn_item[i];
            rd_grn      = rd_grn      | rd_grn_item[i];
        end
    end

endmodule

`default_nettype wire
