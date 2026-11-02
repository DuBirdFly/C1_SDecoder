`default_nettype none

module age_matrix_8x8 (
    input  logic            clk,

    // 通常 valid 应滞后 req_pos 一拍
    input  logic [7:0]      req_pos_1,
    input  logic [7:0]      req_pos_2,
    input  logic [7:0]      item_valid,
    output logic [7:0]      oldest_vec

);

    // 请求分配条目时, 将年龄矩阵中对应行全部置为 1, 对应列全部置为 0
    // M[i][j] = 1 表示 i 比 j 年轻
    // 支持一拍最多两条请求同时到达, 此时, 默认分配条目号较大的请求更年轻
    logic [7:0]  matrix [7:0];

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

    assign oldest_vec[0] = item_valid[0] & ~(item_valid[1] & matrix[0][1])
                                         & ~(item_valid[2] & matrix[0][2])
                                         & ~(item_valid[3] & matrix[0][3])
                                         & ~(item_valid[4] & matrix[0][4])
                                         & ~(item_valid[5] & matrix[0][5])
                                         & ~(item_valid[6] & matrix[0][6])
                                         & ~(item_valid[7] & matrix[0][7]);

    assign oldest_vec[1] = item_valid[1] & ~(item_valid[0] & matrix[1][0])
                                         & ~(item_valid[2] & matrix[1][2])
                                         & ~(item_valid[3] & matrix[1][3])
                                         & ~(item_valid[4] & matrix[1][4])
                                         & ~(item_valid[5] & matrix[1][5])
                                         & ~(item_valid[6] & matrix[1][6])
                                         & ~(item_valid[7] & matrix[1][7]);

    assign oldest_vec[2] = item_valid[2] & ~(item_valid[0] & matrix[2][0])
                                         & ~(item_valid[1] & matrix[2][1])
                                         & ~(item_valid[3] & matrix[2][3])
                                         & ~(item_valid[4] & matrix[2][4])
                                         & ~(item_valid[5] & matrix[2][5])
                                         & ~(item_valid[6] & matrix[2][6])
                                         & ~(item_valid[7] & matrix[2][7]);

    assign oldest_vec[3] = item_valid[3] & ~(item_valid[0] & matrix[3][0])
                                         & ~(item_valid[1] & matrix[3][1])
                                         & ~(item_valid[2] & matrix[3][2])
                                         & ~(item_valid[4] & matrix[3][4])
                                         & ~(item_valid[5] & matrix[3][5])
                                         & ~(item_valid[6] & matrix[3][6])
                                         & ~(item_valid[7] & matrix[3][7]);

    assign oldest_vec[4] = item_valid[4] & ~(item_valid[0] & matrix[4][0])
                                         & ~(item_valid[1] & matrix[4][1])
                                         & ~(item_valid[2] & matrix[4][2])
                                         & ~(item_valid[3] & matrix[4][3])
                                         & ~(item_valid[5] & matrix[4][5])
                                         & ~(item_valid[6] & matrix[4][6])
                                         & ~(item_valid[7] & matrix[4][7]);

    assign oldest_vec[5] = item_valid[5] & ~(item_valid[0] & matrix[5][0])
                                         & ~(item_valid[1] & matrix[5][1])
                                         & ~(item_valid[2] & matrix[5][2])
                                         & ~(item_valid[3] & matrix[5][3])
                                         & ~(item_valid[4] & matrix[5][4])
                                         & ~(item_valid[6] & matrix[5][6])
                                         & ~(item_valid[7] & matrix[5][7]);

    assign oldest_vec[6] = item_valid[6] & ~(item_valid[0] & matrix[6][0])
                                         & ~(item_valid[1] & matrix[6][1])
                                         & ~(item_valid[2] & matrix[6][2])
                                         & ~(item_valid[3] & matrix[6][3])
                                         & ~(item_valid[4] & matrix[6][4])
                                         & ~(item_valid[5] & matrix[6][5])
                                         & ~(item_valid[7] & matrix[6][7]);

    assign oldest_vec[7] = item_valid[7] & ~(item_valid[0] & matrix[7][0])
                                         & ~(item_valid[1] & matrix[7][1])
                                         & ~(item_valid[2] & matrix[7][2])
                                         & ~(item_valid[3] & matrix[7][3])
                                         & ~(item_valid[4] & matrix[7][4])
                                         & ~(item_valid[5] & matrix[7][5])
                                         & ~(item_valid[6] & matrix[7][6]);


    // [TODO] 断言 oldest_vec 为 $onehot0()


endmodule

`default_nettype wire
