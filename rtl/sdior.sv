`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdior: SDecoder 的 IO 寄存器 (IOR)
//   首版不做 APB 从口, 寄存器由 cfg_* 端口直接体现 (见接口手册 寄存器列表);
//   以后交付标准形态时在外面包一层 APB wrapper 即可, 寄存器语义不变.
//   本模块只做 SDecoder 需要的 3 个寄存器, 地址是寄存器序号 (见 sdecoder_pkg 的 ADDR_*),
//   寄存器字宽 64 (见 sdecoder_pkg 的 SDIOR_DATA_WIDTH): 地址类寄存器把整条 PA 填在低 PA_WIDTH 位.
//     0: SDecoder_IA   W1P: 触发位是字的 bit[0], 写了它就当拍发出 1 拍 inv_all (置无效全部条目)
//     1: SDecoder_IS   W1P: 触发位是字的 bit[63], 写了它就当拍发出 1 拍 inv_en;
//                            字的低 PA_WIDTH 位是整条 PA[47:0], 置无效只用到 PA[47:30] (inv_pa),
//                            即 1GB 粒度, 所以 PA[29:0] 必须为 0
//     2: SDT_L1_BASE   RW : 一级表基地址 PA[47:0], 16B 对界, 复位值 0
//   时序: 写是同步的 (cfg_wr 在 clk 上升沿生效), 读是组合的 (cfg_rd 当拍给出 cfg_rdata).
//   W1P 寄存器不留存值: 触发的那一拍把写数据直接送到 inv_pa, 所以 inv_* 天然只有 1 拍, 读回 0.
module sdior
import sdecoder_pkg::*;
(
    input  logic                            clk,
    input  logic                            rst_n,

    // 软件侧寄存器访问 (cfg_* 直连; cfg_wr / cfg_rd 都是 1 拍脉冲)
    input  logic                            cfg_wr,
    input  logic                            cfg_rd,
    input  logic [SDIOR_ADDR_WIDTH-1:0]     cfg_addr,
    input  logic [SDIOR_DATA_WIDTH-1:0]     cfg_wdata,
    output logic [SDIOR_DATA_WIDTH-1:0]     cfg_rdata,

    // SDT_L1_BASE: 给 sdptw 的一级表基地址
    output logic [PA_WIDTH-1:0]             sdt_l1_base,

    // 置无效 (刷新): 给 sdtlb, inv_all / inv_en 各只有 1 拍
    output logic                            inv_all,
    output logic                            inv_en,
    output logic [PA_BASE_WIDTH-1:0]        inv_pa
);

    wire wr_ia = cfg_wr && (cfg_addr == ADDR_SDECODER_IA);
    wire wr_is = cfg_wr && (cfg_addr == ADDR_SDECODER_IS);
    wire wr_l1 = cfg_wr && (cfg_addr == ADDR_SDT_L1_BASE);

    // W1P: 只有写了触发位 (IA 是 bit 0, IS 是 bit 63) 才算一次置无效, 写 0 不产生脉冲
    wire pulse_ia = wr_ia && cfg_wdata[SDIOR_IA_W1P_BIT];
    wire pulse_is = wr_is && cfg_wdata[SDIOR_IS_W1P_BIT];

    // SDT_L1_BASE (RW): 软件先写寄存器再发请求, 这里打一拍; 整条 PA[47:0] 填在字的低位
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdt_l1_base <= '0;
        end
        else if (wr_l1) begin
            sdt_l1_base <= cfg_wdata[PA_WIDTH-1:0];
        end
    end

    // SDecoder_IA / SDecoder_IS 是 W1P 寄存器: 触发位当拍透传, 不留存值, 所以脉冲只有 1 拍
    assign inv_all = pulse_ia;
    assign inv_en  = pulse_is;
    assign inv_pa  = cfg_wdata[PA_WIDTH-1 -: PA_BASE_WIDTH];    // 整条 PA 里的 PA[47:30]

    // 读是组合的: 只有读写寄存器给出值, W1P 寄存器读回 0
    // 注: 每个分支都要把整字赋满 —— 只写 cfg_rdata[PA_WIDTH-1:0] 的话, 高位在 always_comb 里
    //     就是"保持", 会综合出 16 个非预期的锁存器 (仿真看不出来)
    always_comb begin
        case (cfg_addr)
            ADDR_SDT_L1_BASE:
                cfg_rdata = {{(SDIOR_DATA_WIDTH-PA_WIDTH){1'b0}}, sdt_l1_base};
            default:
                cfg_rdata = '0;
        endcase
    end

`ifdef ASSERT_ON
    // 只定义了 0/1/2 三个寄存器, 访问别的地址是软件错误
    `assert_clk(a_cfg_addr_known, ((cfg_wr || cfg_rd) |-> (cfg_addr <= ADDR_SDT_L1_BASE)))
    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间):
    // 写 SDT_L1_BASE / 触发 SDecoder_IS 时该位都必须为 0
    `assert_clk(a_l1_base47_zero, (wr_l1   |-> !cfg_wdata[PA_WIDTH-1]))
    `assert_clk(a_is_pa47_zero,   (pulse_is |-> !cfg_wdata[PA_WIDTH-1]))
    // SDT_L1_BASE 是 16B 对界的一级表基地址
    `assert_clk(a_l1_base_16b_aligned, (wr_l1 |-> (cfg_wdata[3:0] == 4'h0)))
    // SDecoder_IS 的置无效是 1GB 粒度的, 只用 PA[47:30]; PA[29:0] 必须为 0, 否则会被静默丢掉
    `assert_clk(a_is_pa_1g_aligned, (pulse_is |-> (cfg_wdata[PA_WIDTH-PA_BASE_WIDTH-1:0] == '0)))
`endif

endmodule

`default_nettype wire
