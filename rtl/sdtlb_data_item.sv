`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB 单个条目的 Data 段
// 存储: 全部字段用 Latch (有效位在 Tag 段, 是 FF).
// Latch 注意: 装填期间字段对输入透明, 因此本条目在装填当拍不可被查表读.
// 顶层的 camN_req_ready 在装填当拍拉低, 由它保证这一点.
module sdtlb_data_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 装填请求
    input  logic                        fill_en,
    input  logic [EID_WIDTH-1:0]        fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]   fill_token_id,
    input  logic [S_PFN_WIDTH-1:0]      fill_s_pfn,

    // 本条目内容静默输出
    output SDTLB_DATA_ITEM_t            data_item
);

    logic [EID_WIDTH-1:0]      eid_q;
    logic [TOKEN_ID_WIDTH-1:0] token_id_q;
    logic [S_PFN_WIDTH-1:0]    s_pfn_q;

    // 只由装填写: 置无效只清 Tag 段的 Valid, 不碰 Data 段, 所以这里没有清位分支
    always_latch begin
        if (fill_en) begin
            eid_q      <= fill_eid;
            token_id_q <= fill_token_id;
            s_pfn_q    <= fill_s_pfn;
        end
    end

    assign data_item = '{eid: eid_q, token_id: token_id_q, s_pfn: s_pfn_q};

endmodule

`default_nettype wire
