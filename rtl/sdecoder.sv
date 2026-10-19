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
    input  logic                            req_valid,
    output logic                            req_ready,
    input  logic [PA_WIDTH-1:0]             req_pa,
    input  logic [REQ_ID_WIDTH-1:0]         req_id,

    // 代换响应
    output logic                            rsp_valid,
    input  logic                            rsp_ready,
    output logic [REQ_ID_WIDTH-1:0]         rsp_id,
    output logic [2:0]                      rsp_fcode,
    output logic [EID_WIDTH-1:0]            rsp_eid,
    output logic [TOKEN_ID_WIDTH-1:0]       rsp_token_id,
    output logic [SLA_WIDTH-1:0]            rsp_sla,

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

    // 响应包: id + fcode + eid + token_id + sla
    typedef struct packed {
        logic [REQ_ID_WIDTH-1:0]    id;
        logic [2:0]                 fcode;
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [SLA_WIDTH-1:0]       sla;
    } rsp_t;

    localparam int unsigned RSP_WIDTH  = REQ_ID_WIDTH + 3 + EID_WIDTH + TOKEN_ID_WIDTH + SLA_WIDTH;
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
    logic                       sdtlb_fill_valid;
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
    rsp_t                       rsp_wr_pkt;
    rsp_t                       rsp_rd_pkt;
    rsp_t                       hit_rsp;
    rsp_t                       miss_rsp;

    // 命中 / 未命中结果
    logic                       hit_result_valid;
    logic                       push_hit;
    logic                       push_miss;
    logic                       miss_ok;
    logic                       miss_seg;
    logic                       hit_sla_err;
    logic                       seg_sla_err;
    logic                       page_sla_err;
    logic                       seg_len_bad;
    logic                       seg_hit;
    logic [5:0]                 seg_up;
    logic [4:0]                 pa_up;
    logic [4:0]                 seg_offset;
    logic [18:0]                seg_sla_sum;
    logic [18:0]                hit_sla_sum;
    logic [4:0]                 hit_offset;
    logic [SLA_WIDTH-1:0]       hit_sla;
    logic [SLA_WIDTH-1:0]       seg_sla;
    logic [SLA_WIDTH-1:0]       page_sla;
    logic [SLA_WIDTH-1:0]       miss_sla;
    logic [2:0]                 hit_fcode;
    logic [2:0]                 miss_fcode;
    logic [EID_WIDTH-1:0]       miss_eid;
    logic [TOKEN_ID_WIDTH-1:0]  miss_token_id;
    logic [S_PFN_WIDTH-1:0]     miss_s_pfn;
    logic [PA_BASE_WIDTH-1:0]   miss_fill_pa_base;
    logic [PA_UP_WIDTH-1:0]     miss_fill_pa_up;
    logic                       miss_fill_valid;

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

    // 命中路径: SDTLB 的 tag/data + 请求 PA[34:0] -> SLA
    assign hit_offset  = req_pa_r[PA_BASE_LSB +: PA_UP_WIDTH] - sdtlb_hit_tag.pa_base[PA_UP_WIDTH-1:0];
    assign hit_sla_sum = {1'b0, sdtlb_hit_data.s_pfn} + {14'b0, hit_offset};
    assign hit_sla_err = hit_sla_sum[18] || hit_sla_sum[17];
    assign hit_sla     = {hit_sla_sum[17:0], req_pa_r[PA_BASE_LSB-1:0]};
    assign hit_fcode   = hit_sla_err ? 3'b001 : 3'b000;

    assign hit_result_valid = req_valid_r && sdtlb_req_hit;

    always_comb begin
        hit_rsp = '0;
        hit_rsp.id    = req_id_r;
        hit_rsp.fcode = hit_fcode;
        if (!hit_sla_err) begin
            hit_rsp.eid      = sdtlb_hit_data.eid;
            hit_rsp.token_id = sdtlb_hit_data.token_id;
            hit_rsp.sla      = hit_sla;
        end
    end

    // 未命中路径: 先判段, 再判页
    assign seg_up     = {1'b0, sdptw_l1_item.seg_base} + {1'b0, sdptw_l1_item.seg_len};
    assign pa_up      = walk_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    assign seg_hit    = sdptw_l1_item.valid && sdptw_l1_item.type_bit &&
                        (pa_up >= sdptw_l1_item.seg_base) &&
                        ({1'b0, pa_up} <= seg_up);
    assign seg_len_bad = sdptw_l1_item.valid && sdptw_l1_item.type_bit && (seg_up > 6'd31);

    assign seg_offset  = pa_up - sdptw_l1_item.seg_base;
    assign seg_sla_sum = {1'b0, sdptw_l1_item.s_pfn} + {14'b0, seg_offset};
    assign seg_sla_err = seg_sla_sum[18] || seg_sla_sum[17];
    assign seg_sla     = {seg_sla_sum[17:0], walk_pa[PA_BASE_LSB-1:0]};

    assign page_sla     = {sdptw_l2_item.s_pfn, walk_pa[PA_BASE_LSB-1:0]};
    assign page_sla_err = sdptw_l2_item.s_pfn[17];

    assign miss_ok = sdptw_l1_item.valid && !seg_len_bad &&
                     ((sdptw_l1_item.type_bit && seg_hit && !seg_sla_err) ||
                      (!seg_hit && sdptw_l2_read && sdptw_l2_item.valid && !page_sla_err));

    assign miss_seg   = miss_ok && sdptw_l1_item.type_bit && seg_hit;
    assign miss_fcode = miss_ok ? 3'b000 : 3'b001;
    assign miss_eid      = miss_seg ? sdptw_l1_item.eid      : sdptw_l2_item.eid;
    assign miss_token_id = miss_seg ? sdptw_l1_item.token_id : sdptw_l2_item.token_id;
    assign miss_s_pfn    = miss_seg ? sdptw_l1_item.s_pfn    : sdptw_l2_item.s_pfn;
    assign miss_sla      = miss_seg ? seg_sla                : page_sla;

    assign miss_fill_pa_base = miss_seg ?
        {walk_pa[PA_WIDTH-1:PA_HIGH_LSB], sdptw_l1_item.seg_base} :
        walk_pa[PA_WIDTH-1:PA_BASE_LSB];
    assign miss_fill_pa_up = miss_seg ?
        seg_up[PA_UP_WIDTH-1:0] :
        walk_pa[PA_BASE_LSB +: PA_UP_WIDTH];

    always_comb begin
        miss_rsp = '0;
        miss_rsp.id    = walk_id;
        miss_rsp.fcode = miss_fcode;
        if (miss_ok) begin
            miss_rsp.eid      = miss_eid;
            miss_rsp.token_id = miss_token_id;
            miss_rsp.sla      = miss_sla;
        end
    end

    // 响应仲裁: 命中优先; 未命中结果留在 SDPTW DONE, 等响应 FIFO 有空位
    assign push_hit  = hit_result_valid;
    assign push_miss = sdptw_rsp_valid && !push_hit && !rsp_fifo_full;
    assign sdptw_rsp_ready = push_miss;

    assign miss_fill_valid = miss_ok && push_miss;

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
    assign rsp_rd_pkt    = rsp_t'(rsp_fifo_rd_data);
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

    // 顶层填给 SDTLB 的数据来自未命中结果; 成功且被响应 FIFO 接收时才回填
    assign sdtlb_fill_valid    = miss_fill_valid;
    assign sdtlb_fill_pa_base  = miss_fill_pa_base;
    assign sdtlb_fill_pa_up    = miss_fill_pa_up;
    assign sdtlb_fill_eid      = miss_eid;
    assign sdtlb_fill_token_id = miss_token_id;
    assign sdtlb_fill_s_pfn    = miss_s_pfn;

    sdtlb u_sdtlb (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (req_accept),
        .req_pa             (req_pa),
        .req_hit            (sdtlb_req_hit),
        .req_hit_tag_item   (sdtlb_hit_tag),
        .req_hit_data_item  (sdtlb_hit_data),

        .fill_valid         (sdtlb_fill_valid),
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
