// =============================================================================
// sdtlb_data: SDTLB 的 Data 段阵列 (SDTLB_ENTRIES 个 sdtlb_data_item)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   1. 装填: 与 Tag 段同条目写入一条 (EID / TokenID / S_PFN / Grn).
//   2. 读出: 读出被选中的那一条 (组合), 没有选中时输出全 0.
//
// 层次与约定:
//   - 读写选中都是 SDTLB_ENTRIES 位 one-hot 向量 (自然的全相联形式), 不用"地址 + 有效"
//     的 RAM 形式: 写使能 fill_vld 由 sdtlb_tag 的轮转指针译码而来, 读选中 hit_sel 直接用
//     Tag 段的命中向量.
//     将来若真要换成 RAM/SRAM 实现, 再改本模块的读写口 (到时把 one-hot 编成地址).
//   - 数据段没有有效位: 条目是否有效由同下标 Tag 条目表示, 因此本模块没有置无效端口;
//     未命中时读选中向量全 0, 读出自然全 0.
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

    // 装填请求: 与 Tag 段同条目写入. fill_vld 是 SDTLB_ENTRIES 位 one-hot 向量,
    // 每一位就是对应条目的写使能 (与 sdtlb_data_item 的 fill_vld 端口同名同义)
    input  logic [SDTLB_ENTRIES-1:0]            fill_vld,
    input  logic [10:0]                         fill_eid,
    input  logic [ 9:0]                         fill_token_id,
    input  logic [17:0]                         fill_s_pfn,
    input  logic                                fill_grn,

    // 读出请求: SDTLB_ENTRIES 位 one-hot 选中 (顶层直接把 Tag 段的命中向量接过来),
    // 同理每一位就是对应条目的读选中
    input  logic [SDTLB_ENTRIES-1:0]            hit_sel,
    output logic [10:0]                         hit_eid,
    output logic [ 9:0]                         hit_token_id,
    output logic [17:0]                         hit_s_pfn,
    output logic                                hit_grn
);

    // 每个条目的读出 (就是条目内容), 由下面的 onehot0_mux 按 hit_sel 挑出命中的那一份
    logic [10:0] hit_eid_item      [SDTLB_ENTRIES];
    logic [ 9:0] hit_token_id_item [SDTLB_ENTRIES];
    logic [17:0] hit_s_pfn_item    [SDTLB_ENTRIES];
    logic        hit_grn_item      [SDTLB_ENTRIES];

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个 Data 条目: 每个条目的写使能 (fill_vld) 就是对应那一位;条目只存
    // 数据, 选中在下面用 onehot0_mux 做
    // -------------------------------------------------------------------------
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : genvar_data_item
            sdtlb_data_item u_data_item (
                .clk           (clk),
                .rst_n         (rst_n),
                .fill_vld      (fill_vld[genvar_i]),
                .fill_eid      (fill_eid),
                .fill_token_id (fill_token_id),
                .fill_s_pfn    (fill_s_pfn),
                .fill_grn      (fill_grn),
                .hit_eid       (hit_eid_item[genvar_i]),
                .hit_token_id  (hit_token_id_item[genvar_i]),
                .hit_s_pfn     (hit_s_pfn_item[genvar_i]),
                .hit_grn       (hit_grn_item[genvar_i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 命中数据汇总: 用 common 下的 onehot0_mux 从 SDTLB_ENTRIES 份条目读出里挑出命中
    // 的那一份 (hit_sel 全 0 即未命中, 输出自然全 0)
    // -------------------------------------------------------------------------
    onehot0_mux #(.N (SDTLB_ENTRIES), .WIDTH (11)) u_hit_eid_mux (
        .sel  (hit_sel),
        .din  (hit_eid_item),
        .dout (hit_eid)
    );

    onehot0_mux #(.N (SDTLB_ENTRIES), .WIDTH (10)) u_hit_token_id_mux (
        .sel  (hit_sel),
        .din  (hit_token_id_item),
        .dout (hit_token_id)
    );

    onehot0_mux #(.N (SDTLB_ENTRIES), .WIDTH (18)) u_hit_s_pfn_mux (
        .sel  (hit_sel),
        .din  (hit_s_pfn_item),
        .dout (hit_s_pfn)
    );

    onehot0_mux #(.N (SDTLB_ENTRIES), .WIDTH (1)) u_hit_grn_mux (
        .sel  (hit_sel),
        .din  (hit_grn_item),
        .dout (hit_grn)
    );

endmodule

`default_nettype wire
