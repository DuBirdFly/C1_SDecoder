// =============================================================================
// sdtlb_data_item: SDTLB 的一个 Data 条目 (全相联条目里的数据部分)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §表项格式):
//   Data 段共 40 bit: EID[10:0] + TokenID[9:0] + S_PFN[47:30] + Grn (位域见 sdecoder_pkg).
//   由 SDPTW 在 Page Walk 完成后装填, 与同下标的 sdtlb_tag_item 一起构成一个 SDTLB 条目.
//
// 层次与约定:
//   - 本模块**只存数据**, 不参与选择: 四个读出端口始终是本条目寄存器里的值, 由上层
//     sdtlb_data 用 common 下的 onehot0_mux 按命中向量挑出命中条目的那一份.
//   - 条目内容存在本模块的 data_item 寄存器里. 装填由端口 fill_vld 作写使能: 有效时把
//     fill_eid / fill_token_id / fill_s_pfn / fill_grn 一起写进 data_item, 因此装填当拍读出的
//     仍是旧值, 新值下一拍生效.
//   - 读出是纯组合的 (比较与选数据同拍), 与设计方案的 "命中 2 拍" 口径一致.
//   - 数据段没有有效位: 条目是否有效由同下标的 tag 条目的 tag_item.valid 表示, 因此
//     本模块没有无效化端口, 刷新只清 tag 侧的有效位.
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_data_item
import sdecoder_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,

    // 装填请求
    input  logic                    fill_vld,     // 写使能
    input  logic [10:0]             fill_eid,     // Entity 标识
    input  logic [ 9:0]             fill_token_id,// 逻辑池标识
    input  logic [17:0]             fill_s_pfn,   // SLA 基址, 以 1 GB 对界
    input  logic                    fill_grn,     // 粒度位, 1 表示段式, 0 表示 1GB 页式

    // 读出端口: 始终输出本条目内容 (是否被选中由上层 sdtlb_data 的 onehot0_mux 决定)
    output logic [10:0]             hit_eid,
    output logic [ 9:0]             hit_token_id,
    output logic [17:0]             hit_s_pfn,
    output logic                    hit_grn
);

    // 本条目寄存器: 位域见 sdecoder_pkg 的 SDTLB_DATA_ITEM_t
    SDTLB_DATA_ITEM_t data_item;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_item <= '0;
        end
        else if (fill_vld) begin
            data_item <= '{
                eid:      fill_eid,
                token_id: fill_token_id,
                s_pfn:    fill_s_pfn,
                grn:      fill_grn
            };
        end
    end

    // 组合读出: 本条目内容 (不再按选中门控)
    assign hit_eid      = data_item.eid;
    assign hit_token_id = data_item.token_id;
    assign hit_s_pfn    = data_item.s_pfn;
    assign hit_grn      = data_item.grn;

endmodule

`default_nettype wire
