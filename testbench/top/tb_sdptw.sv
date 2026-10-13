`timescale 1ns/1ps

// tb_sdptw: sdptw 的单元自检 tb. 重设计起点: 空骨架, DUT 与测试点待补.
module tb_sdptw;

    logic clk;
    logic rst_n;

    // 时钟与复位由 crg 生成 (SDecoder 是单时钟域时序模块, tb 内不再自己写 #NUM 延时)
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

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdptw, "+all");
        $display("===============================================");
    end
`endif

    initial begin
        // 复位由 crg 产生: 等它释放后即结束, 目前还没有激励与检查
        wait (rst_n === 1'b1);
        $display("tb_sdptw: 骨架, 还没有测试点");
        $finish;
    end

endmodule
