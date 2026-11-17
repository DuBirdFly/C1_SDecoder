`timescale 1ns/1ps

// SDTLB 的 UVM 顶层: crg + sdtlb_if + wrapper_sdtlb + run_test
//   用例名由 +UVM_TESTNAME 决定 (Makefile 里 TB_TOP=tb_sdtlb 时默认 SdtlbTestBase)
module tb_sdtlb;

    import uvm_pkg::*;
    import test_pkg::*;

    logic clk;
    logic rst_n;

    // 时钟与复位由 crg 生成
    crg #(
        .CLK_FREQ ( 2_500 )
    ) u_crg (
        .clk     (clk      ),
        .rst_n   (rst_n    )
    );

    sdtlb_if sdtlb_if (.clk(clk), .rst_n(rst_n));

    // DUT 走 wrapper: 所有 input 打 1 拍, tb/env 只跟 sdtlb_if 打交道
    wrapper_sdtlb dut (.sdtlb_if(sdtlb_if));

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdtlb);
        $display("===============================================");
    end
`endif

    initial begin
        uvm_config_db#(virtual sdtlb_if)::set(null, "*", "vif", sdtlb_if);
        // monitor 看的是 bind 到 sdtlb 模块上的探针 (DUT 引脚), 不是 wrapper 之前的接口
        uvm_config_db#(virtual sdtlb_if_probe)::set(
            null, "*", "mon_vif", tb_sdtlb.dut.u_sdtlb.u_sdtlb_if_probe_bind
        );
        run_test();
    end

endmodule
