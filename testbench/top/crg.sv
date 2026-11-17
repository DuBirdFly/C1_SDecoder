// 时钟与复位发生器: SDecoder 是单时钟域, 只出 clk / rst_n
module crg #(
    parameter CLK_FREQ = 100    // 100MHz
)(
    output logic clk,
    output logic rst_n
);

    timeunit 1ns/1ps;

    localparam PERIOD_CLK = 1_000 / CLK_FREQ;

    initial begin
        clk = 0;
        forever #(PERIOD_CLK / 2) clk = ~clk;
    end

    initial begin
        rst_n = 0;
        repeat(2) @(posedge clk);
        #1 rst_n = 1;
    end

endmodule
