`default_nettype none

// N×N 年龄矩阵: 请求分配条目时, 把对应行全部置 1, 对应列全部置 0
// matrix[i][j] = 1 表示 i 比 j 年轻
// 支持一拍最多两条请求同时到达, 此时默认分配条目号较大的请求更年轻

module age_matrix #(
    parameter int unsigned ITEM_DEPTH = 8
) (
    input  logic                    clk,

    input  logic [ITEM_DEPTH-1:0]   req_pos_1,
    input  logic [ITEM_DEPTH-1:0]   req_pos_2,

    output logic [ITEM_DEPTH-1:0]   matrix [ITEM_DEPTH-1:0]
);

    wire [ITEM_DEPTH-1:0] req_pos = req_pos_1 | req_pos_2;

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < ITEM_DEPTH; genvar_i++) begin : g_age_row
            // 只关心比 i 大的列: 同拍申请时条目号大的更年轻
            wire [ITEM_DEPTH-1:0] above = {ITEM_DEPTH{1'b1}} << (genvar_i + 1);

            always_ff @(posedge clk) begin
                if (req_pos[genvar_i]) begin
                    matrix[genvar_i] <= ~(req_pos & above);
                end
                else begin
                    matrix[genvar_i] <= matrix[genvar_i] & ~req_pos;
                end
            end
        end
    endgenerate

endmodule

`default_nettype wire
