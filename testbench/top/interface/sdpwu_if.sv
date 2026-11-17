// SDPWU_TOP 的接口
//   tb 扮演 SDMQ (发 Page Walk 请求) 和外部存储器 (响应读请求)
interface sdpwu_if
import sdecoder_pkg::*;

(
    input  logic                        clk,
    input  logic                        rst_n
);

    timeunit      1ns;
    timeprecision 1ps;

    // 一级表基地址
    logic [PA_WIDTH-1:0]                l1_base;

    // SDMQ -> SDPWU_TOP: Page Walk 请求
    logic                               sdmq_pw_valid;
    logic [$bits(SDPWU_START_t)-1:0]    sdmq_pw_item;
    logic                               sdmq_pw_ready;

    // 访存接口 (读地址通道)
    logic                               pw_mem_raddr_valid;
    logic [PA_WIDTH-1:0]                pw_mem_raddr;
    logic [PW_ID_WIDTH-1:0]             pw_mem_raddr_id;
    logic                               pw_mem_raddr_ready;

    // 写端口: tb 用存储器模型布置页表 (一拍写入一个 16B 条目)
    logic                               pw_mem_wen;
    logic [PA_WIDTH-1:0]                pw_mem_waddr;
    logic [PW_RDATA_WIDTH-1:0]          pw_mem_wdata;

    // 访存接口 (读数据通道)
    logic [PW_RDATA_WIDTH-1:0]          pw_mem_rdata;
    logic [PW_ID_WIDTH-1:0]             pw_mem_rdata_id;
    logic                               pw_mem_rdata_valid;
    logic [PW_RDATA_ERR_WIDTH-1:0]      pw_mem_rdata_err;
    logic                               pw_mem_rdata_ready;

    // Page Walk 结果
    logic                               pwu_finish_valid;
    logic [$bits(SDPWU_FINISH_t)-1:0]   pwu_finish_item;

    clocking drv @(posedge clk);
        default input #1 output #1;

        output l1_base;
        output sdmq_pw_valid;
        output sdmq_pw_item;
        input  sdmq_pw_ready;

        input  pw_mem_raddr_valid;
        input  pw_mem_raddr;
        input  pw_mem_raddr_id;
        output pw_mem_raddr_ready;

        output pw_mem_rdata;
        output pw_mem_rdata_id;
        output pw_mem_rdata_valid;
        output pw_mem_rdata_err;
        input  pw_mem_rdata_ready;

        input  pwu_finish_valid;
        input  pwu_finish_item;
    endclocking

    clocking mon @(posedge clk);
        default input #1step;

        input l1_base;
        input sdmq_pw_valid;
        input sdmq_pw_item;
        input sdmq_pw_ready;
        input pw_mem_raddr_valid;
        input pw_mem_raddr;
        input pw_mem_raddr_id;
        input pw_mem_raddr_ready;
        input pw_mem_wen;
        input pw_mem_waddr;
        input pw_mem_wdata;
        input pw_mem_rdata;
        input pw_mem_rdata_id;
        input pw_mem_rdata_valid;
        input pw_mem_rdata_err;
        input pw_mem_rdata_ready;
        input pwu_finish_valid;
        input pwu_finish_item;
    endclocking

endinterface
