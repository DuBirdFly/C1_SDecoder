`timescale 1ns/1ps

// sdior 的 UVM 顶层: crg + sdior_if + sdior + run_test
//   用例名由 +UVM_TESTNAME 决定 (Makefile 里 TB_TOP=tb_sdior 时默认 SdiorTestBase)
module tb_sdior;

    import uvm_pkg::*;
    import test_pkg::*;

    logic clk;
    logic rst_n;

    // 时钟与复位由 crg 生成
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

    sdior_if sdior_if (.clk(clk), .rst_n(rst_n));

    // DUT 走 wrapper: 所有 input 打 1 拍, tb/env 只跟 sdior_if 打交道
    wrapper_sdior dut (.sdior_if(sdior_if));

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdior, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdior);
        $display("===============================================");
    end
`endif

    initial begin
        uvm_config_db#(virtual sdior_if)::set(null, "*", "vif", sdior_if);
        run_test();
    end

endmodule
