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

    sdior dut (
        .clk            (clk                    ),
        .rst_n          (rst_n                  ),
        .ior_en         (sdior_if.ior_en        ),
        .ior_write      (sdior_if.ior_write     ),
        .ior_waddr      (sdior_if.ior_waddr     ),
        .ior_wdata      (sdior_if.ior_wdata     ),
        .ior_raddr      (sdior_if.ior_raddr     ),
        .ior_rdata      (sdior_if.ior_rdata     ),
        .sdecoder_ptbr  (sdior_if.sdecoder_ptbr ),
        .inv_all        (sdior_if.inv_all       ),
        .inv_sel         (sdior_if.inv_sel        ),
        .inv_sel_pa         (sdior_if.inv_sel_pa        )
    );

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
