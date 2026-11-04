`default_nettype none

interface age_matrix_if #(
    parameter int unsigned ITEM_DEPTH = 16
) (
    input  logic            clk
);

    timeunit 1ps/1ps;

    logic [ITEM_DEPTH-1:0] req_pos_1;
    logic [ITEM_DEPTH-1:0] req_pos_2;
    logic [ITEM_DEPTH-1:0] item_valid;
    logic [ITEM_DEPTH-1:0] oldest_vec;

    clocking drv_cb @(posedge clk);
        default input #1 output #1;

        output req_pos_1;
        output req_pos_2;
        output item_valid;
        input  oldest_vec;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1 output #1;

        input  req_pos_1;
        input  req_pos_2;
        input  item_valid;
        input  oldest_vec;
    endclocking

endinterface

`default_nettype wire
