`default_nettype none

// 从 N×N 年龄矩阵里找有效条目中最老的一个, 以 one-hot 形式输出
// matrix[i][j] = 1 表示 i 比 j 年轻; 没有被任何有效条目"更年轻"压过的有效条目就是最老的

module age_matrix_find_oldest #(
    parameter int unsigned ITEM_DEPTH = 8
) (
    input  logic [ITEM_DEPTH-1:0] matrix [ITEM_DEPTH-1:0],
    input  logic [ITEM_DEPTH-1:0] item_valid,
    output logic [ITEM_DEPTH-1:0] oldest_vec
);

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < ITEM_DEPTH; genvar_i++) begin : g_oldest
            wire [ITEM_DEPTH-1:0] self_mask = ITEM_DEPTH'(1) << genvar_i;
            wire [ITEM_DEPTH-1:0] younger   = item_valid & matrix[genvar_i] & ~self_mask;

            assign oldest_vec[genvar_i] = item_valid[genvar_i] & ~(|younger);
        end
    endgenerate

endmodule

`default_nettype wire
