// =============================================================================
// sdtlb_data_item: SDTLB 的一个 Data 条目 (全相联条目里的数据部分)
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §表项格式):
//   Data 段共 40 bit: EID[10:0] + TokenID[9:0] + S_PFN[47:30] + Grn (位域见 sdecoder_pkg).
//   由 SDPTW 在 Page Walk 完成后装填, 与同下标的 sdtlb_tag_item 一起构成一个 SDTLB 条目.
//
// 层次与约定:
//   - sdtlb_data 用 generate 例化 SDTLB_ENTRIES 份本模块, 每个条目接同下标
//     sdtlb_tag_item 的 req_hit 作为 rd_sel, 再把 128 份输出 OR 起来, 得到命中条目的数据.
//   - 条目内容存在本模块的 data_item 寄存器里. 装填由端口 wr_vld 作写使能: 有效时把
//     wr_eid / wr_token_id / wr_s_pfn / wr_grn 一起写进 data_item, 因此装填当拍读出的
//     仍是旧值, 新值下一拍生效.
//   - 读出是纯组合的: rd_sel 有效时输出本条目内容, 否则输出全 0, 便于上层直接 OR.
//     这样比较与读数据同拍, 下一拍算 SLA, 与设计方案的 "命中 2 拍" 口径一致.
//   - 数据段没有有效位: 条目是否有效由同下标的 tag 条目的 tag_item.valid 表示, 因此
//     本模块没有无效化端口, 刷新只清 tag 侧的有效位.
//   - 复位后 data_item 清 0 (无效条目的数据字段是 don't care).
// =============================================================================
`default_nettype none

module sdtlb_data_item
import sdecoder_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,

    // 本条目装填端口: wr_vld 有效时把四个字段一起写入 data_item
    input  logic                    wr_vld,     // 写使能
    input  logic [10:0]             wr_eid,     // Entity 标识
    input  logic [ 9:0]             wr_token_id,// 逻辑池标识
    input  logic [17:0]             wr_s_pfn,   // SLA 基址, 以 1 GB 对界
    input  logic                    wr_grn,     // 粒度位, 1 表示段式, 0 表示 1GB 页式

    // 读出端口
    input  logic                    rd_sel,     // 本条目被选中 (接同下标 tag 条目的 req_hit)
    output logic [10:0]             eid_o,      // 选中时输出本条目内容, 否则全 0
    output logic [ 9:0]             token_id_o, // 同上
    output logic [17:0]             s_pfn_o,    // 同上
    output logic                    grn_o       // 同上
);

    // 本条目寄存器: 位域见 sdecoder_pkg 的 SDTLB_DATA_ITEM_t
    SDTLB_DATA_ITEM_t data_item;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_item <= '0;
        end
        else if (wr_vld) begin
            data_item <= '{eid:      wr_eid,
                           token_id: wr_token_id,
                           s_pfn:    wr_s_pfn,
                           grn:      wr_grn};
        end
    end

    // 组合读出: 未选中时输出 0, 上层把 128 份输出 OR 起来即为命中条目的数据
    assign eid_o      = rd_sel ? data_item.eid      : 11'h0;
    assign token_id_o = rd_sel ? data_item.token_id : 10'h0;
    assign s_pfn_o    = rd_sel ? data_item.s_pfn    : 18'h0;
    assign grn_o      = rd_sel ? data_item.grn      : 1'b0;

endmodule

`default_nettype wire
