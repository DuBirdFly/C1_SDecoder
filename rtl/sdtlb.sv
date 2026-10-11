`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 查表 (组合)
    input  logic                                req_vld,
    input  logic [PA_BASE_WIDTH-1:0]            req_pa,
    output logic                                req_hit,
    output SDTLB_TAG_ITEM_t                     req_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    req_hit_data_item,

    // 装填: SDPTW 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目
    input  logic                                fill_vld,
    input  logic [PA_BASE_WIDTH-1:0]            fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_pa_up,
    input  logic [EID_WIDTH-1:0]                fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]           fill_token_id,
    input  logic [S_PFN_WIDTH-1:0]              fill_s_pfn,
    input  logic                                fill_grn,

    // 置无效 (刷新): 只作用于 Tag 侧的有效位
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_BASE_WIDTH-1:0]            inv_pa
);

    SDTLB_TAG_ITEM_t  tag_item  [SDTLB_ENTRIES];
    SDTLB_DATA_ITEM_t data_item [SDTLB_ENTRIES];

    logic [SDTLB_ENTRIES-1:0] req_hit_vector;
    logic [SDTLB_ENTRIES-1:0] fill_sel;
    logic [SDTLB_ENTRIES-1:0] fill_vld_vector;

    assign req_hit = |req_hit_vector;
    assign fill_vld_vector = fill_vld ? fill_sel : 0;

    inc_arbiter #(
        .N      (SDTLB_ENTRIES)
    ) u_inc_arbiter (
        .clk    (clk),
        .rst_n  (rst_n),
        .step   (fill_vld),
        .sel    (fill_sel)
    );

    sdtlb_tag u_sdtlb_tag(
        .clk             (clk             ),
        .rst_n           (rst_n           ),

        .req_vld         (req_vld         ),
        .req_pa          (req_pa          ),
        .req_hit_vector  (req_hit_vector  ),

        .fill_pa_base    (fill_pa_base    ),
        .fill_pa_up      (fill_pa_up      ),
        .fill_vld_vector (fill_vld_vector ),

        .inv_all         (inv_all         ),
        .inv_en          (inv_en          ),
        .inv_pa          (inv_pa          ),

        .tag_item        (tag_item        )
    );

    sdtlb_data u_sdtlb_data(
        .clk             (clk             ),
        .rst_n           (rst_n           ),

        .fill_vld_vector (fill_vld_vector ),
        .fill_eid        (fill_eid        ),
        .fill_token_id   (fill_token_id   ),
        .fill_s_pfn      (fill_s_pfn      ),
        .fill_grn        (fill_grn        ),

        .data_item       (data_item       )
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_TAG_ITEM_WIDTH)
    ) u_onehot0_mux_tag (
        .sel    (req_hit_vector),
        .din    (tag_item),
        .dout   (req_hit_tag_item)
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_DATA_ITEM_WIDTH)
    ) u_onehot0_mux_data (
        .sel    (req_hit_vector),
        .din    (data_item),
        .dout   (req_hit_data_item)
    );

`ifdef ASSERT_ON
    `assert_clk(a_req_hit_vector_onehot0, $onehot0(req_hit_vector))
    `assert_clk(a_fill_sel_onehot0, $onehot0(fill_sel))
`endif

endmodule

`default_nettype wire
