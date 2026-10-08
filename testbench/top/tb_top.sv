`default_nettype none
module tb_top;

    timeunit 1ns/1ps;

    import uvm_pkg::*;
    import test_pkg::*;

    initial begin
        // note: 不应该使用 plusargs，因为不同 EDA 的系统函数不一样
        // note: 不应把 dump_wave 放在 uvm_test 里，否则很难访问到模块名
        // note：还有一种做法是用 ucli.key，但是这样访问具体信号比较麻烦，需要权衡
        // note：vip example 是放在 tb_top 里的，这里沿用 vip 的做法
        `ifdef DUMP_VCD
            $display("===============================================");
            $display("Dumping VCD waveforms");
            $dumpfile(test_pkg::VCS_FILENAME);
            $dumpvars(0);
            $display("===============================================");
        `endif

        `ifdef DUMP_FSDB
            $display("===============================================");
            $display("Dumping FSDB waveforms");
            $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
            $fsdbDumpvars(0, tb_top, "+all");
            // $fsdbDumpvarsToFile("dump_information.list");
            $display("===============================================");
        `endif
    end

    crg #(
        .APB_FREQ       ( 20            ),
        .AXI_FREQ       ( 100           )
    )u_crg (
        .pclk           (               ),
        .presetn        (               ),

        .aclk           (               ),
        .aresetn        (               )
    );

    initial begin: config4uvm
        // uvm_config_db#(virtual apb_if)::set(null, "uvm_test_top", "apb", apb_vif);
        // uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top", "axi", axi_vif);
        run_test();
    end

endmodule
`default_nettype wire
