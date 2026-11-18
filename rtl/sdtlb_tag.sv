`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB 的 Tag 阵列: SDTLB_CAM_NUM 个查表端口 + 1 个装填端口 + 1 个置无效端口
// 各查表端口把自己的请求拍上的 accept 广播给全部条目, 得到各自的命中向量.
// 装填分两步: 请求拍选目标条目, 下一拍用 fill_wr_* 写 Latch.
module sdtlb_tag
import sdecoder_pkg::*;
(
    input  logic                                        clk,
    input  logic                                        rst_n,

    // 查表端口: 下标就是 CAM 号, accept 有效时广播给全部条目做比较
    input  logic [SDTLB_CAM_NUM-1:0]                    cam_req_en,
    input  logic [SDTLB_CAM_NUM-1:0][PA_WIDTH-1:0]      cam_req_pa,
    output logic [SDTLB_CAM_NUM-1:0][SDTLB_ENTRIES-1:0] cam_hit_vector,

    // 装填写入: 下一拍生效, 数据与使能都已寄存
    input  logic [SDTLB_ENTRIES-1:0]                    fill_wr_en_vector,
    input  logic [PA_BASE_WIDTH-1:0]                    fill_wr_pa_base,
    input  logic [PA_UP_WIDTH-1:0]                      fill_wr_pa_up,

    // 置无效 (刷新) 请求
    input  logic                                        inv_all,
    input  logic                                        inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]                    inv_sel_pa,

    output SDTLB_TAG_ITEM_t                             tag_item [SDTLB_ENTRIES]
);

    // 条目按 [条目][CAM] 给出命中 (一个条目给所有 CAM 各出一位)
    logic [SDTLB_CAM_NUM-1:0] entry_cam_hit [SDTLB_ENTRIES];

    genvar genvar_entry;
    genvar genvar_cam;
    generate
        for (genvar_entry = 0; genvar_entry < SDTLB_ENTRIES; genvar_entry++) begin : gen_tag_item
            sdtlb_tag_item u_tag_item (
                .clk              (clk),
                .rst_n            (rst_n),

                .cam_req_en       (cam_req_en),
                .cam_req_pa       (cam_req_pa),
                .cam_hit          (entry_cam_hit[genvar_entry]),

                .fill_wr_en       (fill_wr_en_vector[genvar_entry]),
                .fill_wr_pa_base  (fill_wr_pa_base),
                .fill_wr_pa_up    (fill_wr_pa_up),

                .inv_all          (inv_all),
                .inv_sel          (inv_sel),
                .inv_sel_pa       (inv_sel_pa),

                .tag_item         (tag_item[genvar_entry])
            );
        end

        // 命中向量转置: 条目出的是 [条目][CAM], 上层要按 [CAM][条目] 选数据
        for (genvar_cam = 0; genvar_cam < SDTLB_CAM_NUM; genvar_cam++) begin : gen_cam
            for (genvar_entry = 0; genvar_entry < SDTLB_ENTRIES; genvar_entry++) begin : gen_entry
                assign cam_hit_vector[genvar_cam][genvar_entry] = entry_cam_hit[genvar_entry][genvar_cam];
            end
        end
    endgenerate

endmodule

`default_nettype wire
