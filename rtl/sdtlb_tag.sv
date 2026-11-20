`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 查表端口 0 (CAM0): accept 有效时广播给全部条目做比较
    input  logic                                cam0_req_en,
    input  logic [PA_WIDTH-1:0]                 cam0_req_pa,
    output logic [SDTLB_ENTRIES-1:0]            cam0_hit_vector,

    // 查表端口 1 (CAM1)
    input  logic                                cam1_req_en,
    input  logic [PA_WIDTH-1:0]                 cam1_req_pa,
    output logic [SDTLB_ENTRIES-1:0]            cam1_hit_vector,

    // 装填写入: 已经门控好的 one-hot 写使能 (每条一位, 由 sdtlb 用一条只依赖 FF 的
    // 表达式算出: 使能和目标必须是同一根网络, 分开传会在沿后混出 "新目标 × 旧使能")
    input  logic [SDTLB_ENTRIES-1:0]            fill_en_vector,
    input  logic [PA_BASE_WIDTH-1:0]            fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_pa_up,

    // 置无效 (刷新) 请求
    input  logic                                inv_en,
    input  logic                                inv_all,
    input  logic                                inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]            inv_sel_pa,

    output SDTLB_TAG_ITEM_t                     tag_item [SDTLB_ENTRIES],

    // 各条目的有效位: 给装填指针判断 "有没有空闲条目"
    output logic [SDTLB_ENTRIES-1:0]            tag_valid_vector
);

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : gen_tag_item
            sdtlb_tag_item u_tag_item (
                .clk              (clk),
                .rst_n            (rst_n),

                .cam0_req_en      (cam0_req_en),
                .cam0_req_pa      (cam0_req_pa),
                .cam0_hit         (cam0_hit_vector[genvar_i]),

                .cam1_req_en      (cam1_req_en),
                .cam1_req_pa      (cam1_req_pa),
                .cam1_hit         (cam1_hit_vector[genvar_i]),

                .fill_en          (fill_en_vector[genvar_i]),
                .fill_pa_base     (fill_pa_base),
                .fill_pa_up       (fill_pa_up),

                .inv_en           (inv_en),
                .inv_all          (inv_all),
                .inv_sel          (inv_sel),
                .inv_sel_pa       (inv_sel_pa),

                .tag_item         (tag_item[genvar_i]),
                .tag_valid        (tag_valid_vector[genvar_i])
            );
        end
    endgenerate

`ifdef ASSERT_ON
    logic [SDTLB_ENTRIES-1:0] inv_match_vector;

    for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : gen_inv_match
        assign inv_match_vector[genvar_i] = gen_tag_item[genvar_i].u_tag_item.inv_match_for_assert;
    end

    // inv_sel 相当于一次 CAM 查表: 装填不与已有条目冲突的前提下, 它最多命中一个条目
    `assert_clk(a_inv_sel_onehot0, ((inv_en && inv_sel) |-> $onehot0(inv_match_vector)))
`endif

endmodule

`default_nettype wire
