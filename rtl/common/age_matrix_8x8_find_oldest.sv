`default_nettype none

// 查找年龄矩阵中, valid 有效的最老元素, 以 $onehot0 形式输出
// matrix[i][j] = 1 表示 i 比 j 年轻,
// 所以没有被任何有效条目 "更年轻" 压过的有效条目就是最老的
module age_matrix_8x8_find_oldest (
    input  logic [7:0] matrix [7:0],
    input  logic [7:0] item_valid,
    output logic [7:0] oldest_vec
);

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

endmodule

`default_nettype wire
