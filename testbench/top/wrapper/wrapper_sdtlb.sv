`timescale 1ns/1ps

// SDTLB 的仿真 wrapper (不是 RTL):
//   把 sdtlb 的所有 input (cam* / fill* / inv*) 打 1 拍再送进未改动的 sdtlb,
//   用来验证 "整条接口打 1 拍" 这个修法的效果.
//
//   所有 input 在同一个 clk 域, 统一打拍后 fill 与 inv 仍然同拍到达阵列,
//   因此同拍 inv_all + fill 的置无效优先可以保留.
//   代价是整条接口多 1 拍延迟, tb 的请求 / 响应采样要多等一个时钟块事件.
//
//   接口统一用 sdtlb_if, tb 只跟接口打交道.
module wrapper_sdtlb
import sdecoder_pkg::*;
(
    sdtlb_if sdtlb_if
);

    // 所有 input 打 1 拍
    logic                       cam0_req_valid_r;
    logic [PA_WIDTH-1:0]        cam0_req_pa_r;
    logic                       cam1_req_valid_r;
    logic [PA_WIDTH-1:0]        cam1_req_pa_r;

    logic                       fill_en_r;
    logic [PA_BASE_WIDTH-1:0]   fill_pa_base_r;
    logic [PA_UP_WIDTH-1:0]     fill_pa_up_r;
    logic [EID_WIDTH-1:0]       fill_eid_r;
    logic [TOKEN_ID_WIDTH-1:0]  fill_token_id_r;
    logic [S_PFN_WIDTH-1:0]     fill_s_pfn_r;

    logic                       inv_all_r;
    logic                       inv_en_r;
    logic [PA_WIDTH-1:0]        inv_pa_r;

    always_ff @(posedge sdtlb_if.clk or negedge sdtlb_if.rst_n) begin
        if (!sdtlb_if.rst_n) begin
            cam0_req_valid_r <= 1'b0;
            cam0_req_pa_r    <= '0;
            cam1_req_valid_r <= 1'b0;
            cam1_req_pa_r    <= '0;

            fill_en_r        <= 1'b0;
            fill_pa_base_r   <= '0;
            fill_pa_up_r     <= '0;
            fill_eid_r       <= '0;
            fill_token_id_r  <= '0;
            fill_s_pfn_r     <= '0;

            inv_all_r        <= 1'b0;
            inv_en_r         <= 1'b0;
            inv_pa_r         <= '0;
        end
        else begin
            cam0_req_valid_r <= sdtlb_if.cam0_req_valid;
            cam0_req_pa_r    <= sdtlb_if.cam0_req_pa;
            cam1_req_valid_r <= sdtlb_if.cam1_req_valid;
            cam1_req_pa_r    <= sdtlb_if.cam1_req_pa;

            fill_en_r        <= sdtlb_if.fill_en;
            fill_pa_base_r   <= sdtlb_if.fill_pa_base;
            fill_pa_up_r     <= sdtlb_if.fill_pa_up;
            fill_eid_r       <= sdtlb_if.fill_eid;
            fill_token_id_r  <= sdtlb_if.fill_token_id;
            fill_s_pfn_r     <= sdtlb_if.fill_s_pfn;

            inv_all_r        <= sdtlb_if.inv_all;
            inv_en_r         <= sdtlb_if.inv_en;
            inv_pa_r         <= sdtlb_if.inv_pa;
        end
    end

    // 内部仍然是未改动的 sdtlb
    sdtlb u_sdtlb (
        .clk                (sdtlb_if.clk           ),
        .rst_n              (sdtlb_if.rst_n         ),

        .cam0_req_valid     (cam0_req_valid_r       ),
        .cam0_req_ready     (sdtlb_if.cam0_req_ready),
        .cam0_req_pa        (cam0_req_pa_r          ),
        .cam0_hit           (sdtlb_if.cam0_hit      ),
        .cam0_hit_tag_item  (sdtlb_if.cam0_hit_tag_item ),
        .cam0_hit_data_item (sdtlb_if.cam0_hit_data_item),

        .cam1_req_valid     (cam1_req_valid_r       ),
        .cam1_req_ready     (sdtlb_if.cam1_req_ready),
        .cam1_req_pa        (cam1_req_pa_r          ),
        .cam1_hit           (sdtlb_if.cam1_hit      ),
        .cam1_hit_tag_item  (sdtlb_if.cam1_hit_tag_item ),
        .cam1_hit_data_item (sdtlb_if.cam1_hit_data_item),

        .fill_en            (fill_en_r              ),
        .fill_pa_base       (fill_pa_base_r         ),
        .fill_pa_up         (fill_pa_up_r           ),
        .fill_eid           (fill_eid_r             ),
        .fill_token_id      (fill_token_id_r        ),
        .fill_s_pfn         (fill_s_pfn_r           ),

        .inv_all            (inv_all_r              ),
        .inv_en             (inv_en_r               ),
        .inv_pa             (inv_pa_r               )
    );

endmodule
