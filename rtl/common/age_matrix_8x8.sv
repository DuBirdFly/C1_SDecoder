`default_nettype none

// 请求分配条目时, 将年龄矩阵中对应行全部置为 1, 对应列全部置为 0
// matrix[i][j] = 1 表示 i 比 j 年轻
// 支持一拍最多两条请求同时到达, 此时, 默认分配条目号较大的请求更年轻

module age_matrix_8x8 (
    input  logic            clk,

    input  logic [7:0]      req_pos_1,
    input  logic [7:0]      req_pos_2,

    output logic [7:0]      matrix [7:0]

);

    wire [7:0] req_pos = req_pos_1 | req_pos_2;

    always_ff @(posedge clk) begin
        matrix[0] <= req_pos[0] ? (8'hff & ~({req_pos[7:1], 1'h0})) : (matrix[0] & ~req_pos);
        matrix[1] <= req_pos[1] ? (8'hff & ~({req_pos[7:2], 2'h0})) : (matrix[1] & ~req_pos);
        matrix[2] <= req_pos[2] ? (8'hff & ~({req_pos[7:3], 3'h0})) : (matrix[2] & ~req_pos);
        matrix[3] <= req_pos[3] ? (8'hff & ~({req_pos[7:4], 4'h0})) : (matrix[3] & ~req_pos);
        matrix[4] <= req_pos[4] ? (8'hff & ~({req_pos[7:5], 5'h0})) : (matrix[4] & ~req_pos);
        matrix[5] <= req_pos[5] ? (8'hff & ~({req_pos[7:6], 6'h0})) : (matrix[5] & ~req_pos);
        matrix[6] <= req_pos[6] ? (8'hff & ~({req_pos[7:7], 7'h0})) : (matrix[6] & ~req_pos);
        matrix[7] <= req_pos[7] ? (8'hff & ~({              8'h0})) : (matrix[7] & ~req_pos);
    end

endmodule

`default_nettype wire
