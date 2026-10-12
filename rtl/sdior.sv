`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdecoder-io-register: SDecoder 的 IO 寄存器
//   三个主要寄存器: inv_all, inv_sel, sdecoder_page_table_base
//     对应接口手册的 SDEC_IA / SDEC_IS / SDEC_PTBR;
//     另按手册带上 SDEC_CTRL.ENABLE 与 SDEC_STATUS / SDEC_ERRINFO.
//   inv_all / inv_sel 是写 1 触发 (W1P): 写入脉冲即刷新脉冲, 一次刷新只作用一拍, 直接透传给 SDTLB.
//   首版不实现 APB 从口, 由 cfg_* 端口直接体现, 见接口手册 寄存器列表.
module sdior
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 软件侧配置
    input  logic                        cfg_enable,
    input  logic [PA_WIDTH-1:0]         cfg_sdt_l1_base,
    input  logic                        cfg_inv_all,
    input  logic                        cfg_inv_addr_valid,
    input  logic [PA_BASE_WIDTH-1:0]    cfg_inv_addr,

    // 给顶层用的配置
    output logic                        enable,
    output logic [PA_WIDTH-1:0]         sdt_l1_base,

    // 给 SDTLB 的置无效 (刷新)
    output logic                        inv_all,
    output logic                        inv_en,
    output logic [PA_BASE_WIDTH-1:0]    inv_pa,
    output logic                        inv_busy,

    // 异常登记 (SDEC_ERRINFO)
    input  logic                        err_set,
    input  logic [FCODE_WIDTH-1:0]      err_fcode,
    input  logic                        err_rw,
    input  logic [PA_WIDTH-1:0]         err_pa,
    output logic [FCODE_WIDTH-1:0]      errinfo_fcode,
    output logic                        errinfo_rw,
    output logic [PA_WIDTH-1:0]         errinfo_pa
);

    // SDEC_CTRL / SDEC_PTBR: 软件先写寄存器再发请求, 这里打一拍
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable      <= 1'b0;
            sdt_l1_base <= '0;
        end
        else begin
            enable      <= cfg_enable;
            sdt_l1_base <= cfg_sdt_l1_base;
        end
    end

    // SDEC_IA / SDEC_IS: 刷新只需一拍, 直接透传
    assign inv_all  = cfg_inv_all;
    assign inv_en   = cfg_inv_addr_valid;
    assign inv_pa   = cfg_inv_addr;
    assign inv_busy = cfg_inv_all || cfg_inv_addr_valid;

    // SDEC_ERRINFO: 只登记最近一次异常; FCODE = 0 表示尚未记录
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            errinfo_fcode <= FCODE_NONE;
            errinfo_rw    <= 1'b0;
            errinfo_pa    <= '0;
        end
        else if (err_set) begin
            errinfo_fcode <= err_fcode;
            errinfo_rw    <= err_rw;
            errinfo_pa    <= err_pa;
        end
    end

`ifdef ASSERT_ON
    // 全部置无效与按地址置无效不能同拍下发
    `assert_clk(a_inv_one_at_a_time, ((cfg_inv_all && cfg_inv_addr_valid) == 1'b0))
`endif

endmodule

`default_nettype wire
