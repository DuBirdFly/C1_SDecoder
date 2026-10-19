interface sdecoder_if
import sdecoder_pkg::*;
(
    input logic                 clk,
    input logic                 rst_n
);

    // 代换请求
    logic                       req_valid;
    logic                       req_ready;
    logic [PA_WIDTH-1:0]        req_pa;
    logic [REQ_ID_WIDTH-1:0]    req_id;

    // 代换响应
    logic                       rsp_valid;
    logic                       rsp_ready;
    logic [REQ_ID_WIDTH-1:0]    rsp_id;
    logic [2:0]                 rsp_fcode;
    logic [EID_WIDTH-1:0]       rsp_eid;
    logic [TOKEN_ID_WIDTH-1:0]  rsp_token_id;
    logic [SLA_WIDTH-1:0]       rsp_sla;

    // Page Walk 访存: tw_araddr / tw_arvalid / tw_rready 由 DUT 驱动,
    // tw_arready / tw_rdata / tw_rvalid 由 bench 的存储模型驱动
    logic [PA_WIDTH-1:0]        tw_araddr;
    logic                       tw_arvalid;
    logic                       tw_arready;
    logic [127:0]               tw_rdata;
    logic                       tw_rvalid;
    logic                       tw_rready;

    // 配置与刷新
    logic                       cfg_wr;
    logic                       cfg_rd;
    logic [SDIOR_ADDR_WIDTH-1:0] cfg_addr;
    logic [SDIOR_DATA_WIDTH-1:0] cfg_wdata;
    logic [SDIOR_DATA_WIDTH-1:0] cfg_rdata;

    clocking drv @(posedge clk);
        default input #0 output #1;

        output req_valid;
        output req_pa;
        output req_id;
        output rsp_ready;
        output cfg_wr;
        output cfg_rd;
        output cfg_addr;
        output cfg_wdata;

        input  req_ready;
        input  rsp_valid;
        input  rsp_id;
        input  rsp_fcode;
        input  rsp_eid;
        input  rsp_token_id;
        input  rsp_sla;
        input  cfg_rdata;
        input  tw_araddr;
        input  tw_arvalid;
        input  tw_rready;
    endclocking

    clocking mon @(posedge clk);
        default input #1step;

        input req_valid;
        input req_ready;
        input req_pa;
        input req_id;
        input rsp_valid;
        input rsp_ready;
        input rsp_id;
        input rsp_fcode;
        input rsp_eid;
        input rsp_token_id;
        input rsp_sla;
        input tw_araddr;
        input tw_arvalid;
        input tw_arready;
        input tw_rdata;
        input tw_rvalid;
        input tw_rready;
        input cfg_wr;
        input cfg_rd;
        input cfg_addr;
        input cfg_wdata;
        input cfg_rdata;
    endclocking

endinterface
