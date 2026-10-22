`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdecoder: SDecoder 顶层
//   - 请求打 1 拍, 和 SDTLB 打 1 拍的 hit_vector 对齐; 命中直通 SLMD_CALC, 未命中写 MISS_FIFO.
//   - SDPTW 按 MISS_FIFO 顺序走表; 走表结果由 SLMD_CALC 组装成响应, 成功时回填 SDTLB.
//   - 命中与未命中共用一个 2 深响应 FIFO, 允许乱序; rsp_id 回显 req_id.
//   - MISS_FIFO 满或响应 FIFO 将满时拉低 req_ready.
module sdecoder
import sdecoder_pkg::*;
(
    input  logic                            clk,
    input  logic                            rst_n,

    // 代换请求
    input  logic [REQ_ID_WIDTH-1:0]         req_id,
    input  logic [PA_WIDTH-1:0]             req_pa,
    input  logic                            req_valid,
    output logic                            req_ready,

    // 代换响应
    output logic [REQ_ID_WIDTH-1:0]         rsp_id,
    output logic [2:0]                      rsp_fcode,
    output logic [EID_WIDTH-1:0]            rsp_eid,
    output logic [TOKEN_ID_WIDTH-1:0]       rsp_token_id,
    output logic [SLA_WIDTH-1:0]            rsp_sla,
    output logic                            rsp_valid,
    input  logic                            rsp_ready,

    // Page Walk 访存
    output logic [PA_WIDTH-1:0]             tw_araddr,
    output logic                            tw_arvalid,
    input  logic                            tw_arready,
    input  logic [127:0]                    tw_rdata,
    input  logic                            tw_rvalid,
    output logic                            tw_rready,

    // 配置与刷新
    input  logic                            cfg_wr,
    input  logic                            cfg_rd,
    input  logic [SDIOR_ADDR_WIDTH-1:0]     cfg_addr,
    input  logic [SDIOR_DATA_WIDTH-1:0]     cfg_wdata,
    output logic [SDIOR_DATA_WIDTH-1:0]     cfg_rdata
);

    localparam int unsigned MISS_FIFO_DEPTH = 4;
    localparam int unsigned RSP_FIFO_DEPTH  = 2;

    localparam int unsigned RSP_WIDTH  = $bits(SDT_RSP_t);
    localparam int unsigned MISS_WIDTH = PA_WIDTH + REQ_ID_WIDTH;

    // 请求流水: 请求拍 T 采到 req_valid / req_pa / req_id, 下一拍和 SDTLB 的 req_hit 对齐
    logic                       req_valid_r;
    logic [PA_WIDTH-1:0]        req_pa_r;
    logic [REQ_ID_WIDTH-1:0]    req_id_r;
    wire                        req_accept = req_valid && req_ready;

    // MISS_FIFO: {PA[47:0], req_id}
    logic [MISS_WIDTH-1:0]      miss_wr_data;
    logic [MISS_WIDTH-1:0]      miss_rd_data;
    logic                       miss_fifo_wr;
    logic                       miss_fifo_rd;
    logic                       miss_fifo_full;
    logic                       miss_fifo_empty;

    // 当前 Page Walk 的请求上下文: SDPTW 只收 PA[47:30], 这里保留整条 PA 和 id
    logic [PA_WIDTH-1:0]        walk_pa;
    logic [REQ_ID_WIDTH-1:0]    walk_id;

    // SDPTW
    logic                       sdptw_req_ready;
    logic                       sdptw_rsp_valid;
    logic                       sdptw_rsp_ready;
    SDT_L1_ITEM_t               sdptw_l1_item;
    SDT_L2_ITEM_t               sdptw_l2_item;
    logic                       sdptw_l2_read;

    // SDTLB
    logic                       sdtlb_req_hit;
    SDTLB_TAG_ITEM_t            sdtlb_hit_tag;
    SDTLB_DATA_ITEM_t           sdtlb_hit_data;
    logic                       sdtlb_fill_en;
    logic [PA_BASE_WIDTH-1:0]   sdtlb_fill_pa_base;
    logic [PA_UP_WIDTH-1:0]     sdtlb_fill_pa_up;
    logic [EID_WIDTH-1:0]       sdtlb_fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]  sdtlb_fill_token_id;
    logic [S_PFN_WIDTH-1:0]     sdtlb_fill_s_pfn;

    // SDIOR
    logic [PA_WIDTH-1:0]        sdt_l1_base;
    logic                       inv_all;
    logic                       inv_en;
    logic [PA_WIDTH-1:0]        inv_pa;

    // 响应 FIFO
    logic                       rsp_fifo_wr;
    logic                       rsp_fifo_rd;
    logic [RSP_WIDTH-1:0]       rsp_fifo_wr_data;
    logic [RSP_WIDTH-1:0]       rsp_fifo_rd_data;
    logic                       rsp_fifo_full;
    logic                       rsp_fifo_almost_full;
    logic                       rsp_fifo_empty;
    SDT_RSP_t                   rsp_wr_pkt;
    SDT_RSP_t                   rsp_rd_pkt;
    SDT_RSP_t                   hit_rsp;
    SDT_RSP_t                   miss_rsp;

    // 命中 / 未命中结果
    logic                       hit_result_valid;
    logic                       push_hit;
    logic                       push_miss;
    logic                       miss_ok;

    // 请求握手: MISS_FIFO 满或响应 FIFO 将满时不再接收新请求
    assign req_ready = rst_n && !miss_fifo_full && !rsp_fifo_almost_full;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_valid_r <= 1'b0;
            req_pa_r    <= '0;
            req_id_r    <= '0;
        end
        else begin
            req_valid_r <= req_accept;
            req_pa_r    <= req_pa;
            req_id_r    <= req_id;
        end
    end

    // 未命中: 请求拍后一拍写 MISS_FIFO
    assign miss_fifo_wr = req_valid_r && !sdtlb_req_hit;
    assign miss_wr_data = {req_pa_r, req_id_r};

    // SDPTW 从 MISS_FIFO 取请求
    assign miss_fifo_rd = !miss_fifo_empty && sdptw_req_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            walk_pa <= '0;
            walk_id <= '0;
        end
        else if (miss_fifo_rd) begin
            walk_pa <= miss_rd_data[PA_WIDTH+REQ_ID_WIDTH-1:REQ_ID_WIDTH];
            walk_id <= miss_rd_data[REQ_ID_WIDTH-1:0];
        end
    end

    assign hit_result_valid = req_valid_r && sdtlb_req_hit;

    // 命中 / 未命中结果统一由 slmd_calc 组装; 回填字段也由它给出
    slmd_calc u_slmd_calc (
        .hit_valid          (hit_result_valid),
        .hit_pa             (req_pa_r),
        .hit_id             (req_id_r),
        .hit_tag            (sdtlb_hit_tag),
        .hit_data           (sdtlb_hit_data),
        .hit_rsp            (hit_rsp),

        .miss_valid         (sdptw_rsp_valid),
        .miss_pa            (walk_pa),
        .miss_id            (walk_id),
        .l1_item            (sdptw_l1_item),
        .l2_item            (sdptw_l2_item),
        .l2_read            (sdptw_l2_read),
        .miss_rsp           (miss_rsp),

        .miss_ok            (miss_ok),
        .miss_fill_pa_base  (sdtlb_fill_pa_base),
        .miss_fill_pa_up    (sdtlb_fill_pa_up),
        .miss_fill_eid      (sdtlb_fill_eid),
        .miss_fill_token_id (sdtlb_fill_token_id),
        .miss_fill_s_pfn    (sdtlb_fill_s_pfn)
    );

    // 响应仲裁: 命中优先; 未命中结果留在 SDPTW DONE, 等响应 FIFO 有空位
    assign push_hit  = hit_result_valid;
    assign push_miss = sdptw_rsp_valid && !push_hit && !rsp_fifo_full;
    assign sdptw_rsp_ready = push_miss;

    assign sdtlb_fill_en = miss_ok && push_miss;

    assign rsp_fifo_wr = push_hit || push_miss;
    always_comb begin
        rsp_wr_pkt = '0;
        if (push_hit) begin
            rsp_wr_pkt = hit_rsp;
        end
        else if (push_miss) begin
            rsp_wr_pkt = miss_rsp;
        end
    end

    assign rsp_fifo_wr_data = {rsp_wr_pkt.id, rsp_wr_pkt.fcode, rsp_wr_pkt.eid,
                               rsp_wr_pkt.token_id, rsp_wr_pkt.sla};

    assign rsp_fifo_rd   = rsp_ready && !rsp_fifo_empty;
    assign rsp_rd_pkt    = SDT_RSP_t'(rsp_fifo_rd_data);
    assign rsp_valid     = !rsp_fifo_empty;
    assign rsp_id        = rsp_valid ? rsp_rd_pkt.id       : '0;
    assign rsp_fcode     = rsp_valid ? rsp_rd_pkt.fcode    : '0;
    assign rsp_eid       = rsp_valid ? rsp_rd_pkt.eid      : '0;
    assign rsp_token_id  = rsp_valid ? rsp_rd_pkt.token_id : '0;
    assign rsp_sla       = rsp_valid ? rsp_rd_pkt.sla      : '0;

    // 响应 FIFO: 2 深, 命中/未命中共用
    syn_fifo #(
        .WIDTH              (RSP_WIDTH),
        .DEPTH              (RSP_FIFO_DEPTH),
        .ALMOST_FULL_LEVEL  (RSP_FIFO_DEPTH - 1)
    ) u_rsp_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (rsp_fifo_wr),
        .wrdata      (rsp_fifo_wr_data),
        .rd_en       (rsp_fifo_rd),
        .rd_data     (rsp_fifo_rd_data),
        .full        (rsp_fifo_full),
        .almost_full (rsp_fifo_almost_full),
        .empty       (rsp_fifo_empty),
        .almost_empty()
    );

    // MISS_FIFO: 4 深, {PA[47:0], req_id}
    syn_fifo #(
        .WIDTH  (MISS_WIDTH),
        .DEPTH  (MISS_FIFO_DEPTH)
    ) u_miss_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (miss_fifo_wr),
        .wrdata      (miss_wr_data),
        .rd_en       (miss_fifo_rd),
        .rd_data     (miss_rd_data),
        .full        (miss_fifo_full),
        .almost_full(),
        .empty       (miss_fifo_empty),
        .almost_empty()
    );

    sdtlb u_sdtlb (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_en             (req_accept),
        .req_pa             (req_pa),
        .req_hit            (sdtlb_req_hit),
        .req_hit_tag_item   (sdtlb_hit_tag),
        .req_hit_data_item  (sdtlb_hit_data),

        .fill_en           (sdtlb_fill_en),
        .fill_pa_base       (sdtlb_fill_pa_base),
        .fill_pa_up         (sdtlb_fill_pa_up),
        .fill_eid           (sdtlb_fill_eid),
        .fill_token_id      (sdtlb_fill_token_id),
        .fill_s_pfn         (sdtlb_fill_s_pfn),

        .inv_all            (inv_all),
        .inv_en             (inv_en),
        .inv_pa             (inv_pa)
    );

    sdptw u_sdptw (
        .clk                (clk),
        .rst_n              (rst_n),

        .sdt_l1_base        (sdt_l1_base),

        .req_pa_base        (miss_rd_data[PA_WIDTH+REQ_ID_WIDTH-1 -: PA_BASE_WIDTH]),
        .req_valid          (!miss_fifo_empty),
        .req_ready          (sdptw_req_ready),

        .rsp_valid          (sdptw_rsp_valid),
        .rsp_ready          (sdptw_rsp_ready),
        .rsp_sdt_l1_item    (sdptw_l1_item),
        .rsp_sdt_l2_item    (sdptw_l2_item),
        .rsp_sdt_l2_read    (sdptw_l2_read),

        .tw_araddr          (tw_araddr),
        .tw_arvalid         (tw_arvalid),
        .tw_arready         (tw_arready),
        .tw_rdata           (tw_rdata),
        .tw_rvalid          (tw_rvalid),
        .tw_rready          (tw_rready)
    );

    sdior u_sdior (
        .clk                (clk),
        .rst_n              (rst_n),

        .cfg_wr             (cfg_wr),
        .cfg_rd             (cfg_rd),
        .cfg_addr           (cfg_addr),
        .cfg_wdata          (cfg_wdata),
        .cfg_rdata          (cfg_rdata),

        .sdt_l1_base        (sdt_l1_base),
        .inv_all            (inv_all),
        .inv_en             (inv_en),
        .inv_pa             (inv_pa)
    );

`ifdef ASSERT_ON
    `assert_clk(a_req_pa47_zero, ((req_valid && req_ready) |-> !req_pa[PA_WIDTH-1]))
    `assert_clk(a_miss_fifo_room, (miss_fifo_wr |-> !miss_fifo_full))
    `assert_clk(a_hit_rsp_room, (push_hit |-> !rsp_fifo_full))
    `assert_clk(a_rsp_fcode_known, (rsp_valid |-> (rsp_fcode <= 3'b001)))
`endif

endmodule

`default_nettype wire
