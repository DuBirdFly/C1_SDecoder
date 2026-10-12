interface sdecoder_if
import sdecoder_pkg::*;

(
    input  logic                    clk,
    input  logic                    rst_n
);

    timeunit 1ns;
    timeprecision 1ps;

    // 代换请求
    logic                       req_valid;
    logic                       req_ready;
    logic [PA_WIDTH-1:0]        req_pa;
    logic                       req_rw;
    logic [REQ_ID_WIDTH-1:0]    req_id;

    // 代换响应 (SMD 或异常)
    logic                       rsp_valid;
    logic                       rsp_ready;
    logic [REQ_ID_WIDTH-1:0]    rsp_id;
    logic                       rsp_fault;
    logic [EID_WIDTH-1:0]       rsp_eid;
    logic [TOKEN_ID_WIDTH-1:0]  rsp_tokenid;
    logic [SLA_WIDTH-1:0]       rsp_sla;
    logic [FCODE_WIDTH-1:0]     rsp_fcode;

    // Page Walk 访存: DUT 是主端口, 从端口 (本地存储模型) 由 tb 直接驱动
    logic                       tw_req_valid;
    logic                       tw_req_ready;
    logic [PA_WIDTH-1:0]        tw_req_addr;
    logic                       tw_req_size;
    logic                       tw_rsp_valid;
    logic                       tw_rsp_ready;
    logic [127:0]               tw_rsp_data;
    logic [1:0]                 tw_rsp_err;

    // 配置与刷新
    logic                       cfg_enable;
    logic [PA_WIDTH-1:0]        cfg_sdt_l1_base;
    logic                       cfg_inv_all;
    logic                       cfg_inv_addr_valid;
    logic [PA_BASE_WIDTH-1:0]   cfg_inv_addr;
    logic                       cfg_inv_busy;

    // 异常信息 (SDEC_ERRINFO)
    logic [FCODE_WIDTH-1:0]     errinfo_fcode;
    logic                       errinfo_rw;
    logic [PA_WIDTH-1:0]        errinfo_pa;

    // driver: 驱动请求与配置, 回读响应与异常
    clocking drv @(posedge clk);
        default input #1 output #1;

        output req_valid;
        output req_pa;
        output req_rw;
        output req_id;
        output rsp_ready;
        output cfg_enable;
        output cfg_sdt_l1_base;
        output cfg_inv_all;
        output cfg_inv_addr_valid;
        output cfg_inv_addr;

        input  req_ready;
        input  rsp_valid;
        input  rsp_id;
        input  rsp_fault;
        input  rsp_eid;
        input  rsp_tokenid;
        input  rsp_sla;
        input  rsp_fcode;
        input  cfg_inv_busy;
        input  errinfo_fcode;
        input  errinfo_rw;
        input  errinfo_pa;
    endclocking

endinterface
