// sdior (SDecoder IO Register) 的 UVM 接口
//   接口信号与设计方案 "寄存器配置接口" 一致:
//     ior_en / ior_write / ior_waddr / ior_wdata / ior_raddr / ior_rdata
//     ior_en & !ior_write 为读, ior_en & ior_write 为写
//   另有 sdior 输出给 sdtlb 的置无效信号与一级表基地址.
//
//   drv / mon 两个 clocking block:
//     drv: tb 驱动用 (output #1 在沿后 1ns 生效, input #1 在沿前 1ns 采样)
//     mon: 采样用 (input #1step 在沿前 1step 采样)
//   tb 侧驱动统一用 vif.drv.*, 读信号统一用 vif.drv.* / vif.mon.*, 打拍用 @(vif.drv) / @(vif.mon)
interface sdior_if
import sdecoder_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);

    timeunit      1ps;
    timeprecision 1ps;

    // 寄存器配置接口
    logic                           ior_en;
    logic                           ior_write;
    logic [SDIOR_ADDR_WIDTH-1:0]    ior_waddr;
    logic [SDIOR_DATA_WIDTH-1:0]    ior_wdata;
    logic [SDIOR_ADDR_WIDTH-1:0]    ior_raddr;
    logic [SDIOR_DATA_WIDTH-1:0]    ior_rdata;

    // sdior 输出
    logic [PA_WIDTH-1:0]            sdecoder_ptbr;
    logic                           inv_all;
    logic                           inv_sel;
    logic [PA_BASE_WIDTH-1:0]       inv_sel_pa;

    // 驱动用
    clocking drv @(posedge clk);
        default input #1 output #1;

        output ior_en;
        output ior_write;
        output ior_waddr;
        output ior_wdata;
        output ior_raddr;

        input  ior_rdata;
        input  rst_n;
    endclocking

    // 采样用
    clocking mon @(posedge clk);
        default input #1step;

        input  ior_en;
        input  ior_write;
        input  ior_waddr;
        input  ior_wdata;
        input  ior_raddr;
        input  ior_rdata;
        input  rst_n;
        input  sdecoder_ptbr;
        input  inv_all;
        input  inv_sel;
        input  inv_sel_pa;
    endclocking

endinterface
