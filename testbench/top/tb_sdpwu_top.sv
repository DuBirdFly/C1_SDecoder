`timescale 1ns/1ps

// SDPWU_TOP 的 UVM 顶层: crg + sdpwu_if + sdpwu_top + run_test
//   用例名由 +UVM_TESTNAME 决定 (Makefile 里 TB_TOP=tb_sdpwu_top 时默认 SdpwuTestBase)
module tb_sdpwu_top;

    import uvm_pkg::*;
    import test_pkg::*;

    logic clk;
    logic rst_n;

    crg #(
        .CLK_FREQ ( 2_500 )
    ) u_crg (
        .clk     (clk      ),
        .rst_n   (rst_n    )
    );

    sdpwu_if sdpwu_if (.clk(clk), .rst_n(rst_n));

    sdpwu_top dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .l1_base            (sdpwu_if.l1_base),

        .sdmq_pw_valid      (sdpwu_if.sdmq_pw_valid),
        .sdmq_pw_item       (sdpwu_if.sdmq_pw_item),
        .sdmq_pw_ready      (sdpwu_if.sdmq_pw_ready),

        .pw_mem_raddr_valid (sdpwu_if.pw_mem_raddr_valid),
        .pw_mem_raddr       (sdpwu_if.pw_mem_raddr),
        .pw_mem_raddr_id    (sdpwu_if.pw_mem_raddr_id),
        .pw_mem_raddr_ready (sdpwu_if.pw_mem_raddr_ready),

        .pw_mem_rdata       (sdpwu_if.pw_mem_rdata),
        .pw_mem_rdata_id    (sdpwu_if.pw_mem_rdata_id),
        .pw_mem_rdata_valid (sdpwu_if.pw_mem_rdata_valid),
        .pw_mem_rdata_err   (sdpwu_if.pw_mem_rdata_err),
        .pw_mem_rdata_ready (sdpwu_if.pw_mem_rdata_ready),

        .pwu_finish_valid   (sdpwu_if.pwu_finish_valid),
        .pwu_finish_item    (sdpwu_if.pwu_finish_item)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdpwu_top, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdpwu_top);
        $display("===============================================");
    end
`endif

    initial begin
        uvm_config_db#(virtual sdpwu_if)::set(null, "*", "vif", sdpwu_if);
        run_test();
    end

endmodule
