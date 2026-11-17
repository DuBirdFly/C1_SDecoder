`timescale 1ns/1ps

// sdior 的仿真 wrapper (不是 RTL):
//   只把 sdior_if 与未改动的 sdior 连起来, 不插任何寄存器 / Latch, 也不改变时序.
//   目的是让 tb / UVM env 只跟接口打交道 (与 wrapper_sdtlb 的组织方式一致),
//   sdior 本身没有 Latch, 所以这里不需要像 sdtlb 那样对输入打拍.
module wrapper_sdior
import sdecoder_pkg::*;
(
    sdior_if sdior_if
);

    sdior u_sdior (
        .clk            (sdior_if.clk           ),
        .rst_n          (sdior_if.rst_n         ),

        .ior_en         (sdior_if.ior_en        ),
        .ior_write      (sdior_if.ior_write     ),
        .ior_waddr      (sdior_if.ior_waddr     ),
        .ior_wdata      (sdior_if.ior_wdata     ),
        .ior_raddr      (sdior_if.ior_raddr     ),
        .ior_rdata      (sdior_if.ior_rdata     ),

        .sdecoder_ptbr  (sdior_if.sdecoder_ptbr ),
        .inv_en         (sdior_if.inv_en        ),
        .inv_all        (sdior_if.inv_all       ),
        .inv_sel        (sdior_if.inv_sel       ),
        .inv_sel_pa     (sdior_if.inv_sel_pa    )
    );

endmodule
