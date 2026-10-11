`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_data_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 装填请求
    input  logic                        fill_vld,
    input  logic [EID_WIDTH-1:0]        fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]   fill_token_id,
    input  logic [S_PFN_WIDTH-1:0]      fill_s_pfn,
    input  logic                        fill_grn,

    // 本条目内容静默输出
    output SDTLB_DATA_ITEM_t            data_item
);

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

endmodule

`default_nettype wire
