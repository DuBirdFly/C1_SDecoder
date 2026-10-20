`timescale 1ns/1ps

module tb_sdecoder;

    import uvm_pkg::*;

    logic clk;
    logic rst_n;

    crg #(
        .APB_FREQ ( 20  ),
        .AXI_FREQ ( 100 ),
        .CLK_FREQ ( 100 )
    ) u_crg (
        .pclk    (         ),
        .presetn (         ),
        .aclk    (         ),
        .aresetn (         ),
        .clk     (clk      ),
        .rst_n   (rst_n    )
    );

    sdecoder_if sdecoder_if (
        .clk    (clk),
        .rst_n  (rst_n)
    );

    sdecoder dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (sdecoder_if.req_valid),
        .req_ready          (sdecoder_if.req_ready),
        .req_pa             (sdecoder_if.req_pa),
        .req_id             (sdecoder_if.req_id),

        .rsp_valid          (sdecoder_if.rsp_valid),
        .rsp_ready          (sdecoder_if.rsp_ready),
        .rsp_id             (sdecoder_if.rsp_id),
        .rsp_fcode          (sdecoder_if.rsp_fcode),
        .rsp_eid            (sdecoder_if.rsp_eid),
        .rsp_token_id       (sdecoder_if.rsp_token_id),
        .rsp_sla            (sdecoder_if.rsp_sla),

        .tw_araddr          (sdecoder_if.tw_araddr),
        .tw_arvalid         (sdecoder_if.tw_arvalid),
        .tw_arready         (sdecoder_if.tw_arready),
        .tw_rdata           (sdecoder_if.tw_rdata),
        .tw_rvalid          (sdecoder_if.tw_rvalid),
        .tw_rready          (sdecoder_if.tw_rready),

        .cfg_wr             (sdecoder_if.cfg_wr),
        .cfg_rd             (sdecoder_if.cfg_rd),
        .cfg_addr           (sdecoder_if.cfg_addr),
        .cfg_wdata          (sdecoder_if.cfg_wdata),
        .cfg_rdata          (sdecoder_if.cfg_rdata)
    );

    // 本地表模型在 testbench/env 下, 由 SdecoderEnv 创建

    initial begin
        uvm_config_db#(virtual sdecoder_if)::set(null, "*", "vif", sdecoder_if);
        run_test();
    end

endmodule
