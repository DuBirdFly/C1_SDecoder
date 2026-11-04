`default_nettype none

// 从指定方向找输入里的第一个 0
//   direction = 0: LSB2MSB (从低往高找)
//   direction = 1: MSB2LSB (从高往低找)
//
// dec: 第一个 0 的 one-hot (按原 bit 顺序); a 全 1 时 dec = 0
// enc: 从扫描方向起、第一个 0 之前的 1 的个数 (lod 的口径); a 全 1 时输出全 1 哨兵
//      注: enc 不是 bit 位置. MSB2LSB 时 bit 位置 = A_WIDTH-1-enc, LSB2MSB 时 = enc
//
// 实现: lod 固定从 MSB 找, 所以 LSB2MSB 时先把 a 位反序, 再把输出 dec 反序还原.

module find_first_zero #(
    parameter int unsigned A_WIDTH = 8,

    localparam int unsigned ENC_WIDTH = $clog2(A_WIDTH) + 1
) (
    input  logic [A_WIDTH-1:0]      a,
    input  logic                    direction,      // 0: LSB2MSB, 1: MSB2LSB
    output logic [A_WIDTH-1:0]      dec,
    output logic [ENC_WIDTH-1:0]    enc
);

    // 位反序: LSB2MSB 时把 a 反过来喂给 lod
    logic [A_WIDTH-1:0] a_rev;

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < A_WIDTH; genvar_i++) begin : g_rev
            assign a_rev[genvar_i] = a[A_WIDTH-1-genvar_i];
        end
    endgenerate

    logic [A_WIDTH-1:0]   lod_in;
    logic [A_WIDTH-1:0]   lod_dec;
    logic [ENC_WIDTH-1:0] lod_enc;

    assign lod_in = direction ? a : a_rev;

    lod #(
        .A_WIDTH (A_WIDTH)
    ) u_lod (
        .a   (lod_in),
        .dec (lod_dec),
        .enc (lod_enc)
    );

    // MSB2LSB 直接用 lod 的 dec; LSB2MSB 把反序的 dec 还原回原 bit 顺序
    generate
        for (genvar_i = 0; genvar_i < A_WIDTH; genvar_i++) begin : g_dec
            assign dec[genvar_i] = direction ? lod_dec[genvar_i] : lod_dec[A_WIDTH-1-genvar_i];
        end
    endgenerate

    assign enc = lod_enc;

endmodule

`default_nettype wire
