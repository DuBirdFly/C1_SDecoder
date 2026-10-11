`ifndef _SDECODER_CONSTANTS_SVH_
`define _SDECODER_CONSTANTS_SVH_

`ifdef ASSERT_ON

    `define ASSERT_MSG_LABELED(label) `"[ERROR] [ASSERT]: Assertion 'label' failed`"

    // 与时钟同步的并发断言
    `define assert_clk(label,when) \
        label : assert property (@(posedge clk) disable iff (!rst_n || (rst_n === 1'bx)) when) else \
        $display(`ASSERT_MSG_LABELED(label));

    // 用于检查 X 值的并发断言
    `define assert_x_value(label,data_valid,data) \
        label : assert property ( @(posedge clk) disable iff (!rst_n || (rst_n === 1'bx)) ((data_valid==1'b1) |-> (^data !== 1'bx)) ) else \
        $display(`ASSERT_MSG_LABELED(label));

`endif

`endif // _SDECODER_CONSTANTS_SVH_
