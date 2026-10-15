`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 广播给全部条目做比较
    input  logic                                req_valid,
    input  logic [PA_BASE_WIDTH-1:0]            req_pa,
    output logic [SDTLB_ENTRIES-1:0]            req_hit_vector,

    // 装填请求
    input  logic [PA_BASE_WIDTH-1:0]            fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_pa_up,
    input  logic [SDTLB_ENTRIES-1:0]            fill_valid_vector,

    // 置无效 (刷新) 请求, 优先于装填
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_BASE_WIDTH-1:0]            inv_pa,

    output SDTLB_TAG_ITEM_t                     tag_item [SDTLB_ENTRIES]
);

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : gen_tag_item
            sdtlb_tag_item u_tag_item (
                .clk          (clk),
                .rst_n        (rst_n),

                .req_valid    (req_valid),
                .req_pa       (req_pa),
                .req_hit      (req_hit_vector[genvar_i]),

                .fill_pa_base (fill_pa_base),
                .fill_pa_up   (fill_pa_up),
                .fill_valid   (fill_valid_vector[genvar_i]),

                .inv_all      (inv_all),
                .inv_en       (inv_en),
                .inv_pa       (inv_pa),

                .tag_item     (tag_item[genvar_i])
            );
        end
    endgenerate

endmodule

`default_nettype wire
