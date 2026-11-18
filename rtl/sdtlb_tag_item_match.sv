`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag_item_match
import sdecoder_pkg::*;
(
    // 条目内容
    input  logic [PA_BASE_WIDTH-1:0]    tag_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      tag_pa_up,

    // 待比较的地址
    input  logic [PA_BASE_WIDTH-1:0]    pa,

    // 地址落在本条目描述的段里
    output logic                        match
);

    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] high      = pa[PA_BASE_WIDTH-1:PA_UP_WIDTH];
    wire [PA_UP_WIDTH-1:0]               up        = pa[PA_UP_WIDTH-1:0];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] base_high = tag_pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH];
    wire [PA_UP_WIDTH-1:0]               base_up   = tag_pa_base[PA_UP_WIDTH-1:0];

    wire high_match  = (high == base_high);
    wire range_match = (up >= base_up) && (up <= tag_pa_up);

    assign match = high_match && range_match;

endmodule

`default_nettype wire
