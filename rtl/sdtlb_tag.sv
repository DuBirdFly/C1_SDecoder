`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB 的 Tag 阵列: 2 个查表端口 + 1 个装填端口 + 1 个置无效端口
// 两路查表各自把自己请求拍上的 accept 广播给全部条目, 得到各自的命中向量.
// 装填分两步: 请求拍选目标条目, 下一拍用 fill_wr_* 写 Latch.
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

    // 装填写入: 下一拍生效, 数据与使能都已寄存
    input  logic [SDTLB_ENTRIES-1:0]            fill_wr_en_vector,
    input  logic [PA_BASE_WIDTH-1:0]            fill_wr_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_wr_pa_up,

    // 置无效 (刷新) 请求
    input  logic                                inv_all,
    input  logic                                inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]            inv_sel_pa,

    output SDTLB_TAG_ITEM_t                     tag_item [SDTLB_ENTRIES]
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

                .fill_wr_en       (fill_wr_en_vector[genvar_i]),
                .fill_wr_pa_base  (fill_wr_pa_base),
                .fill_wr_pa_up    (fill_wr_pa_up),

                .inv_all          (inv_all),
                .inv_sel          (inv_sel),
                .inv_sel_pa       (inv_sel_pa),

                .tag_item         (tag_item[genvar_i])
            );
        end
    endgenerate

endmodule

`default_nettype wire
