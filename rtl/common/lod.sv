`default_nettype none

/*
DesignWare LOD: Leading Ones Detector

lod contains two outputs, dec and enc. 

The dec output is a decoded one-hot value of the a input
vector assuming there is at least one 0 on a. 

The output enc represents the number of 1s found (from the
most significant bit) before the first occurrence of a 0 from the input port a. All lower order bits (to the right)
from the first occurrence of the 0 on the a input port are "don't care".

If no 0 is found and only 1s are
present, the resulting value of enc is all 1s and of dec is all 0s.


The output port enc width is automatically derived from the input port width parameter, A_WIDTH, and is
defined as ceil(log2[A_WIDTH]) + 1.

Output port dec has the same width as the a input.
*/

// 前导 1 检测器
// dec: one-hot 解码 (假设 a 中至少有一个 0)
//      标出从**高位**起第一个 0 的位置
// enc: 从 a 的高位起数到第一个 0 的 1 的个数, 即 "前导 1 的个数"
//      如果 a 全是 1, 则 enc 全为 1 (哨兵), dec 全为 0
// example:
//   a = 8'b1110_0111, dec = 8'b0001_0000, enc = 4'h3
//   a = 8'b1111_1110, dec = 8'b0000_0001, enc = 4'h7
//   a = 8'b1111_1111, dec = 8'b0000_0000, enc = 4'hf (不会是 4'h8)
//   a = 8'b0000_0000, dec = 8'b1000_0000, enc = 4'h0

module lod #(
    parameter int unsigned A_WIDTH = 8,

    localparam int unsigned ENC_WIDTH = $clog2(A_WIDTH) + 1
) (
    input  logic [A_WIDTH-1:0]      a,
    output logic [A_WIDTH-1:0]      dec,
    output logic [ENC_WIDTH-1:0]    enc
);

    // above_one[i] = a[A_WIDTH-1:i+1] 全为 1, 即 "i 的更高位里没有 0"
    logic [A_WIDTH-1:0] above_one;

    assign above_one[A_WIDTH-1] = 1'b1;

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < A_WIDTH - 1; genvar_i++) begin : g_above_one
            assign above_one[genvar_i] = above_one[genvar_i+1] & a[genvar_i+1];
        end
    endgenerate

    // 从 MSB 起第一个 0 的 one-hot; a 全 1 时 dec = 0
    assign dec = above_one & ~a;

    // enc = 第一个 0 前面的 1 的个数; dec 全 0 (没有 0) 时保持全 1 哨兵
    always_comb begin
        enc = {ENC_WIDTH{1'b1}};
        for (int i = 0; i < A_WIDTH; i++) begin
            if (dec[i]) begin
                enc = A_WIDTH - 1 - i;
            end
        end
    end

endmodule

`default_nettype wire
