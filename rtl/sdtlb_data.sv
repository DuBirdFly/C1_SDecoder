`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_data
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    input  logic [SDTLB_ENTRIES-1:0]            fill_valid_vector,
    input  logic [EID_WIDTH-1:0]                fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]           fill_token_id,
    input  logic [S_PFN_WIDTH-1:0]              fill_s_pfn,
    input  logic                                fill_grn,

    output SDTLB_DATA_ITEM_t                    data_item [SDTLB_ENTRIES]
);

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : gen_data_item
            sdtlb_data_item u_data_item (
                .clk           (clk),
                .rst_n         (rst_n),

                .fill_valid    (fill_valid_vector[genvar_i]),
                .fill_eid      (fill_eid),
                .fill_token_id (fill_token_id),
                .fill_s_pfn    (fill_s_pfn),
                .fill_grn      (fill_grn),

                .data_item     (data_item[genvar_i])
            );
        end
    endgenerate

endmodule

`default_nettype wire
