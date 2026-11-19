`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_data_item
import sdecoder_pkg::*;
(
    // 装填请求
    input  logic                            fill_en,
    input  logic [EID_WIDTH-1:0]            fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]       fill_token_id,
    input  logic [TOKEN_VALUE_WIDTH-1:0]    fill_token_value,
    input  logic [S_PFN_WIDTH-1:0]          fill_s_pfn,

    // 本条目内容透传输出
    output SDTLB_DATA_ITEM_t                data_item
);

    // 只由装填写: 置无效只清 Tag 段的 Valid, 不碰 Data 段, 所以这里没有清位分支
    always_latch begin
        if (fill_en) begin
            data_item.eid         <= fill_eid;
            data_item.token_id    <= fill_token_id;
            data_item.token_value <= fill_token_value;
            data_item.s_pfn       <= fill_s_pfn;
        end
    end

endmodule

`default_nettype wire
