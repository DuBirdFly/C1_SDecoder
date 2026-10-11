module crg #(
    parameter APB_FREQ = 50,  // 50MHz
    parameter AXI_FREQ = 100, // 100MHz
    parameter CLK_FREQ = 100  // 100MHz: 普通的 clk / rst_n
)(
    output logic pclk,
    output logic presetn,

    output logic aclk,
    output logic aresetn,

    output logic clk,
    output logic rst_n
);

    timeunit 1ns/1ps;

    localparam PERIOD_APB = 1_000 / APB_FREQ;
    localparam PERIOD_AXI = 1_000 / AXI_FREQ;
    localparam PERIOD_CLK = 1_000 / CLK_FREQ;

    initial begin
        pclk = 0;
        forever #(PERIOD_APB / 2) pclk = ~pclk;
    end

    initial begin
        aclk = 0;
        forever #(PERIOD_AXI / 2) aclk = ~aclk;
    end

    initial begin
        clk = 0;
        forever #(PERIOD_CLK / 2) clk = ~clk;
    end

    initial begin
        presetn = 0;
        repeat(2) @(posedge pclk);
        #1 presetn = 1;
    end

    initial begin
        aresetn = 0;
        repeat(2) @(posedge aclk);
        #1 aresetn = 1;
    end

    initial begin
        rst_n = 0;
        repeat(2) @(posedge clk);
        #1 rst_n = 1;
    end

endmodule