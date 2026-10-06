// =============================================================================
// sdtlb_if: sdtlb (SDTLB 顶层) 的 testbench 接口
//
// 结构: clk / rst_n 作为接口端口由 testbench 传入 (可接 crg 的时钟复位), 其余信号按
//       功能分组声明; 两个 clocking block 分别给 driver 与 monitor 用:
//         drv : 驱动 DUT 输入 (output), 同时回读 DUT 输出 (input)
//         mon : 只采样 (input), 供 scoreboard / coverage 使用
//
// 用法 (sdtlb 是普通端口, 不是 interface 端口, 所以按名字逐根连接):
//   sdtlb_if sdtlb_vif (.clk (clk), .rst_n (rst_n));
//   sdtlb dut (
//       .clk (sdtlb_vif.clk), .rst_n (sdtlb_vif.rst_n),
//       .req_vld (sdtlb_vif.req_vld), ...
//   );
//   驱动: sdtlb_vif.drv.wr_vld <= 1'b1;   采样: sdtlb_vif.mon.req_hit_vld
//   或在 UVM 环境里: uvm_config_db#(virtual sdtlb_if)::set(null, "*", "sdtlb_vif", sdtlb_vif);
// =============================================================================
`include "sdecoder_pkg.svh"

interface sdtlb_if (
    input  logic                    clk,
    input  logic                    rst_n
);

    timeunit 1ps;
    timeprecision 1ps;

    import sdecoder_pkg::*;

    // 代换请求 (查表)
    logic                               req_vld;
    logic [PA_WIDTH-1:0]                req_pa;
    logic                               req_hit_vld;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0] req_hit_idx;

    // 命中条目的读出
    logic [10:0]                        rd_eid;
    logic [ 9:0]                        rd_token_id;
    logic [17:0]                        rd_s_pfn;
    logic                               rd_grn;
    logic [16:0]                        rd_pa_base;
    logic [ 4:0]                        rd_pa_up;
    logic [SLA_WIDTH-1:0]               rd_sla;
    logic                               rd_sla_ovf;

    // 装填请求 (Page Walk 结果)
    logic                               wr_vld;
    logic [16:0]                        wr_pa_base;
    logic [ 4:0]                        wr_pa_up;
    logic [10:0]                        wr_eid;
    logic [ 9:0]                        wr_token_id;
    logic [17:0]                        wr_s_pfn;
    logic                               wr_grn;

    // 置无效 (刷新) 请求
    logic                               inv_all;
    logic                               inv_en;
    logic [PA_WIDTH-1:0]                inv_pa;

    // driver: 驱动 DUT 输入, 回读 DUT 输出
    clocking drv @(posedge clk);
        default input #1 output #1;

        output req_vld;
        output req_pa;
        output wr_vld;
        output wr_pa_base;
        output wr_pa_up;
        output wr_eid;
        output wr_token_id;
        output wr_s_pfn;
        output wr_grn;
        output inv_all;
        output inv_en;
        output inv_pa;

        input  req_hit_vld;
        input  req_hit_idx;
        input  rd_eid;
        input  rd_token_id;
        input  rd_s_pfn;
        input  rd_grn;
        input  rd_pa_base;
        input  rd_pa_up;
        input  rd_sla;
        input  rd_sla_ovf;
    endclocking

    // monitor: 全部采样
    clocking mon @(posedge clk);
        default input #1 output #1;

        input  req_vld;
        input  req_pa;
        input  req_hit_vld;
        input  req_hit_idx;
        input  rd_eid;
        input  rd_token_id;
        input  rd_s_pfn;
        input  rd_grn;
        input  rd_pa_base;
        input  rd_pa_up;
        input  rd_sla;
        input  rd_sla_ovf;
        input  wr_vld;
        input  wr_pa_base;
        input  wr_pa_up;
        input  wr_eid;
        input  wr_token_id;
        input  wr_s_pfn;
        input  wr_grn;
        input  inv_all;
        input  inv_en;
        input  inv_pa;
    endclocking

endinterface
