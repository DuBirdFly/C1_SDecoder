`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdior: SDecoder 的 IO 寄存器 (IOR)
//   首版不做 APB 从口, 寄存器由 ior_* 端口直接体现 (见设计方案 "寄存器配置接口");
//   以后交付标准形态时在外面包一层 APB wrapper 即可, 寄存器语义不变.
//   本模块实现 SDecoder 需要的 3 个寄存器, 地址是寄存器序号 (见 sdecoder_pkg 的 ADDR_*),
//   寄存器字宽 64 (见 sdecoder_pkg 的 SDIOR_DATA_WIDTH):
//     0: SDecoder_IA   volatile: 写该地址 (与写入值无关) 当拍发出 1 拍 inv_all (置无效全部条目), 读回 0
//     1: SDecoder_IS   写即触发 + 存储: 写该地址当拍发出 1 拍 inv_sel (置无效指定条目),
//                      字段 INV_SEL_PA[47:30] 在寄存器字的 [17:0], 存下来并可读回原值
//     2: SDecoder_PTBR RW : Page Table Base Register, 字段 SDT_L1_BASE[47:4] 在寄存器字的 [47:4],
//                      即一级表基地址 PA[47:0] (低 4 位恒 0, 16B 对界), 复位值 0
//   时序: 写是同步的 (ior_en & ior_write 的那一拍在 clk 上升沿生效);
//         读是组合的, ior_en & !ior_write 的那一拍由 ior_raddr 给出 ior_rdata.
//   IA / IS 不留存值: 写的那一拍直接产生 inv_* 脉冲, 所以天然只有 1 拍, 读回 0.
//   注: SDecoder_ES (异常统计) 暂不实现, 后续补的时候按设计方案 "异常统计接口" 加 W1C 寄存器.
module sdior
import sdecoder_pkg::*;
(
    input  logic                            clk,
    input  logic                            rst_n,

    // 软件侧寄存器访问 (见设计方案 "寄存器配置接口")
    //   ior_en & !ior_write 为读 (该拍 ior_rdata 有效); ior_en & ior_write 为写
    input  logic                            ior_en,
    input  logic                            ior_write,
    input  logic [SDIOR_ADDR_WIDTH-1:0]     ior_waddr,
    input  logic [SDIOR_DATA_WIDTH-1:0]     ior_wdata,
    input  logic [SDIOR_ADDR_WIDTH-1:0]     ior_raddr,
    output logic [SDIOR_DATA_WIDTH-1:0]     ior_rdata,

    // SDecoder_PTBR: 一级表基地址, 给 sdptw
    output logic [PA_WIDTH-1:0]             sdecoder_ptbr,

    // 置无效 (刷新): 给 sdtlb / sdmq, inv_en 是总使能, inv_all / inv_sel 各只有 1 拍
    output logic                            inv_en,
    output logic                            inv_all,
    output logic                            inv_sel,
    output logic [PA_BASE_WIDTH-1:0]        inv_sel_pa
);

    wire wr_ia   = ior_en && ior_write && (ior_waddr == ADDR_SDECODER_IA);
    wire wr_is   = ior_en && ior_write && (ior_waddr == ADDR_SDECODER_IS);
    wire wr_ptbr = ior_en && ior_write && (ior_waddr == ADDR_SDECODER_PTBR);

    // SDecoder_IA 是 volatile 寄存器: 写即触发, 不留存值
    assign inv_en  = wr_ia | wr_is;
    assign inv_all = wr_ia;

    // SDecoder_IS: 写即触发置无效, 同时把 INV_SEL_PA[47:30] 存下来 (可读回)
    logic [PA_BASE_WIDTH-1:0] inv_sel_pa_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_sel_pa_q <= '0;
        end
        else if (wr_is) begin
            inv_sel_pa_q <= ior_wdata[SDIOR_IS_PA_LSB +: PA_BASE_WIDTH];
        end
    end

    // 脉冲当拍把本次写入的 PA[47:30] 送给 sdtlb (寄存器在下一拍才更新)
    assign inv_sel    = wr_is;
    assign inv_sel_pa = ior_wdata[PA_BASE_WIDTH-1:0];

    // SDecoder_PTBR (RW): 字段 SDT_L1_BASE[47:4] 在寄存器字的 [47:4], 低 4 位恒 0
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sdecoder_ptbr <= '0;
        end
        else if (wr_ptbr) begin
            sdecoder_ptbr <= {ior_wdata[PA_WIDTH-1:SDIOR_PTBR_LSB], {SDIOR_PTBR_LSB{1'b0}}};
        end
    end

    // 读是组合的: PTBR 与 IS 给出存的值, IA 是 volatile (读回 0), 未定义地址读回 0
    // 注: 每个分支都要把整字赋满 —— 只写 ior_rdata[PA_WIDTH-1:0] 的话, 高位在 always_comb 里
    //     就是"保持", 会综合出 16 个非预期的锁存器 (仿真看不出来)
    always_comb begin
        case (ior_raddr)
            ADDR_SDECODER_PTBR:
                ior_rdata = {{(SDIOR_DATA_WIDTH-PA_WIDTH){1'b0}}, sdecoder_ptbr};
            ADDR_SDECODER_IS:
                ior_rdata = {{(SDIOR_DATA_WIDTH-PA_BASE_WIDTH){1'b0}}, inv_sel_pa_q};
            default:
                ior_rdata = '0;
        endcase
    end

`ifdef ASSERT_ON
    // 只定义了 0/1/2 三个寄存器, 写别的地址是软件错误 (读未定义地址读回 0, 不报错)
    `assert_clk(a_ior_waddr_known, ((ior_en && ior_write) |-> (ior_waddr <= ADDR_SDECODER_PTBR)))
    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间):
    // 写 SDecoder_PTBR / 触发 SDecoder_IS 时该位都必须为 0
    `assert_clk(a_ptbr47_zero, (wr_ptbr |-> !ior_wdata[PA_WIDTH-1]))
    // SDecoder_IS 的字段 INV_SEL_PA 只有 PA[47:30], 最高位 (寄存器字 bit 17) 就是 PA[47]
    `assert_clk(a_is_pa47_zero, (wr_is |-> !ior_wdata[PA_BASE_WIDTH-1]))
`endif

endmodule

`default_nettype wire
