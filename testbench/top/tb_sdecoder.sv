`timescale 1ns/1ps

// SDecoder 的 UVM 顶层 (骨架)
//   写法参考 backup/testbench/tb_sdecoder.sv: crg + 接口 + DUT + config_db + run_test.
//
//   注: rtl/ 下还没有 SDecoder 顶层, 所以 DUT 例化先注释掉. 顶层实现后按设计方案
//   "接口信号" 一节接线:
//     cam0 / cam1 请求 (valid / ready / pa / id) 与响应 (valid / ready / id / eid /
//       token_id / token_value / sla / err)
//     sdmq_rsp (valid / ready / id / eid / token_id / token_value / sla / err / flushed)
//     pw_mem_raddr (id / addr / valid / ready) 与 pw_mem_rdata (data / id / valid / ready / err)
//     ior (wen / waddr / wdata / raddr / rdata)
//     异常统计 (pw_ctrl_err / pw_data_ecc_err / pw_oob_access / pw_pte_malformed /
//       pw_pte_page_fault / tlb_multi_hit)
module tb_sdecoder;

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

    sdecoder_if sdecoder_if (.clk(clk), .rst_n(rst_n));

    // TODO: SDecoder 顶层实现后在这里例化, 端口按设计方案 "接口信号" 一节接 sdecoder_if
    // sdecoder dut (
    //     .clk    (clk),
    //     .rst_n  (rst_n),
    //     ...
    // );

    // 本地 SDT 表模型在 testbench/env 下, 由 SdecoderEnv 创建

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdecoder, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdecoder);
        $display("===============================================");
    end
`endif

    initial begin
        uvm_config_db#(virtual sdecoder_if)::set(null, "*", "vif", sdecoder_if);
        run_test();
    end

endmodule
