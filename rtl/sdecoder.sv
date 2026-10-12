`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdecoder: 含 sdior (IO 寄存器), sdptw (Page Walk), sdtlb (代换快表)
//   请求按序进未命中队列; 解析引擎只处理队头:
//     命中   -> 直接算 SLA 并回响应
//     未命中 -> 交给 sdptw 走表, 走完回填 SDTLB 并回响应
//     队头没处理完不会碰后面的请求, 所以响应与请求天然同序 (并行度 1, 见设计方案评审结论 Q7)
module sdecoder
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 代换请求 (来自核心 / LCPM 侧)
    input  logic                        req_valid,
    output logic                        req_ready,
    input  logic [PA_WIDTH-1:0]         req_pa,
    input  logic                        req_rw,
    input  logic [REQ_ID_WIDTH-1:0]     req_id,

    // 代换响应 (SMD 或异常)
    output logic                        rsp_valid,
    input  logic                        rsp_ready,
    output logic [REQ_ID_WIDTH-1:0]     rsp_id,
    output logic                        rsp_fault,
    output logic [EID_WIDTH-1:0]        rsp_eid,
    output logic [TOKEN_ID_WIDTH-1:0]   rsp_tokenid,
    output logic [SLA_WIDTH-1:0]        rsp_sla,
    output logic [FCODE_WIDTH-1:0]      rsp_fcode,

    // Page Walk 访存接口 (主端口)
    output logic                        tw_req_valid,
    input  logic                        tw_req_ready,
    output logic [PA_WIDTH-1:0]         tw_req_addr,
    output logic                        tw_req_size,
    output logic [WALK_ID_WIDTH-1:0]    tw_req_id,
    input  logic                        tw_rsp_valid,
    output logic                        tw_rsp_ready,
    input  logic [127:0]                tw_rsp_data,
    input  logic [WALK_ID_WIDTH-1:0]    tw_rsp_id,
    input  logic [1:0]                  tw_rsp_err,

    // 配置与刷新
    input  logic                        cfg_enable,
    input  logic [PA_WIDTH-1:0]         cfg_sdt_l1_base,
    input  logic                        cfg_inv_all,
    input  logic                        cfg_inv_addr_valid,
    input  logic [PA_BASE_WIDTH-1:0]    cfg_inv_addr,
    output logic                        cfg_inv_busy,

    // 异常信息 (SDEC_ERRINFO)
    output logic [FCODE_WIDTH-1:0]      errinfo_fcode,
    output logic                        errinfo_rw,
    output logic [PA_WIDTH-1:0]         errinfo_pa
);

    localparam int unsigned PTR_WIDTH = (SDEC_REQ_FIFO_DEPTH <= 1) ? 1 : $clog2(SDEC_REQ_FIFO_DEPTH);
    localparam int unsigned CNT_WIDTH = $clog2(SDEC_REQ_FIFO_DEPTH + 1);

    localparam SDEC_RSP_t RSP_NONE = '{req_id: '0, fault: 1'b0, fcode: FCODE_NONE,
                                       eid: '0, token_id: '0, sla: '0};

    // ---- 配置与刷新 ----
    logic                       enable;
    logic [PA_WIDTH-1:0]        sdt_l1_base;
    logic                       inv_all;
    logic                       inv_en;
    logic [PA_BASE_WIDTH-1:0]   inv_pa;
    logic                       inv_busy;

    // ---- SDTLB 回填 (由 sdptw 驱动) ----
    logic                       fill_vld;
    logic [PA_BASE_WIDTH-1:0]   fill_pa_base;
    logic [PA_UP_WIDTH-1:0]     fill_pa_up;
    logic [EID_WIDTH-1:0]       fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]  fill_token_id;
    logic [S_PFN_WIDTH-1:0]     fill_s_pfn;
    logic                       fill_grn;

    // ---- 未命中队列: 按请求顺序排队, 深度 4 ----
    SDEC_REQ_t                  req_fifo [SDEC_REQ_FIFO_DEPTH];
    logic [PTR_WIDTH-1:0]       rd_ptr;
    logic [PTR_WIDTH-1:0]       wr_ptr;
    logic [CNT_WIDTH-1:0]       fifo_cnt;

    wire                        fifo_empty = (fifo_cnt == '0);
    wire                        fifo_full  = (fifo_cnt == CNT_WIDTH'(SDEC_REQ_FIFO_DEPTH));
    wire                        req_accept = req_valid && req_ready;

    SDEC_REQ_t                  head;
    assign head = req_fifo[rd_ptr];

    // ---- 解析引擎: 逐个处理队头 ----
    typedef enum logic [1:0] {
        E_IDLE,
        E_WALK
    } engine_e;

    engine_e                    engine;

    wire                        head_in_mem = (head.pa[PA_WIDTH-1] == 1'b0);   // PA[47] = 0

    // SDTLB 查表 (组合): 只在引擎空闲且队头在 Mem 空间时查
    logic                       sdtlb_req_hit;
    SDTLB_TAG_ITEM_t            sdtlb_hit_tag;
    SDTLB_DATA_ITEM_t           sdtlb_hit_data;
    wire                        sdtlb_req_vld = !fifo_empty && (engine == E_IDLE) && head_in_mem;

    // 队头命中时算 SLA: {S_PFN + 段内偏移, 页内偏移}
    wire [PA_UP_WIDTH-1:0]      hit_offset  = head.pa[PA_UP_MSB:PA_UP_LSB] -
                                              sdtlb_hit_tag.pa_base[PA_UP_WIDTH-1:0];
    wire [S_PFN_WIDTH:0]        hit_sla_hi  = {1'b0, sdtlb_hit_data.s_pfn} +
                                              {{(S_PFN_WIDTH + 1 - PA_UP_WIDTH){1'b0}}, hit_offset};
    wire                        hit_sla_ovf = hit_sla_hi[S_PFN_WIDTH];
    wire [SLA_WIDTH-1:0]        hit_sla     = {hit_sla_hi[S_PFN_WIDTH-1:0], head.pa[PA_OFFSET_WIDTH-1:0]};

    // ---- 走表 ----
    logic                       walk_ready;
    logic                       walk_done_vld;
    SDEC_RSP_t                  walk_done_rsp;
    wire                        walk_vld = !fifo_empty && (engine == E_IDLE) && head_in_mem &&
                                            !sdtlb_req_hit;
    wire                        walk_go  = walk_vld && walk_ready;

    // ---- 响应寄存器 ----
    logic                       rsp_vld_r;
    SDEC_RSP_t                  rsp_r;
    wire                        rsp_free = !rsp_vld_r || rsp_ready;

    // ---- 队头处理: 本拍能否给出响应 ----
    logic                       head_fin;
    SDEC_RSP_t                  head_rsp;
    always_comb begin
        head_fin = 1'b0;
        head_rsp = RSP_NONE;
        if (!fifo_empty && (engine == E_IDLE) && rsp_free) begin
            if (!head_in_mem) begin
                // PA[47] = 1: IO 空间, 本 IP 不处理
                head_fin = 1'b1;
                head_rsp = '{req_id: head.req_id, fault: 1'b1, fcode: FCODE_ADDR_ILLEGAL,
                             eid: '0, token_id: '0, sla: '0};
            end
            else if (sdtlb_req_hit) begin
                head_fin = 1'b1;
                if (hit_sla_ovf) begin
                    head_rsp = '{req_id: head.req_id, fault: 1'b1, fcode: FCODE_ADDR_ILLEGAL,
                                 eid: '0, token_id: '0, sla: '0};
                end
                else begin
                    head_rsp = '{req_id: head.req_id, fault: 1'b0, fcode: FCODE_NONE,
                                 eid: sdtlb_hit_data.eid, token_id: sdtlb_hit_data.token_id,
                                 sla: hit_sla};
                end
            end
        end
        else if (!fifo_empty && (engine == E_WALK) && walk_done_vld && rsp_free) begin
            head_fin = 1'b1;
            head_rsp = walk_done_rsp;
        end
    end

    // 队头出队: 命中/异常当拍出队; 交给走表的请求要等走完才出队
    wire                        head_pop = head_fin;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            engine   <= E_IDLE;
            rd_ptr   <= '0;
            wr_ptr   <= '0;
            fifo_cnt <= '0;
        end
        else begin
            if (walk_go) begin
                engine <= E_WALK;
            end
            else if (head_fin && (engine == E_WALK)) begin
                engine <= E_IDLE;
            end

            if (req_accept) begin
                req_fifo[wr_ptr] <= '{pa: req_pa, rw: req_rw, req_id: req_id};
                wr_ptr           <= wr_ptr + 1'b1;
            end

            if (head_pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({req_accept, head_pop})
                2'b10:   fifo_cnt <= fifo_cnt + 1'b1;
                2'b01:   fifo_cnt <= fifo_cnt - 1'b1;
                default: ;
            endcase
        end
    end

    // ---- 响应 ----
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_vld_r <= 1'b0;
            rsp_r     <= RSP_NONE;
        end
        else begin
            if (rsp_vld_r && rsp_ready) begin
                rsp_vld_r <= 1'b0;
            end
            if (head_fin) begin
                rsp_vld_r <= 1'b1;
                rsp_r     <= head_rsp;
            end
        end
    end

    assign rsp_valid   = rsp_vld_r;
    assign rsp_id      = rsp_r.req_id;
    assign rsp_fault   = rsp_r.fault;
    assign rsp_eid     = rsp_r.eid;
    assign rsp_tokenid = rsp_r.token_id;
    assign rsp_sla     = rsp_r.sla;
    assign rsp_fcode   = rsp_r.fcode;

    // 队列满就反压上游; cfg_enable = 0 时不再接收新请求
    assign req_ready   = enable && !fifo_full;

    // 给出异常响应那一拍登记 SDEC_ERRINFO
    wire err_set = head_fin && head_rsp.fault;

    // ---- 子模块 ----
    sdior u_sdior (
        .clk                 (clk                 ),
        .rst_n               (rst_n               ),
        .cfg_enable          (cfg_enable          ),
        .cfg_sdt_l1_base     (cfg_sdt_l1_base     ),
        .cfg_inv_all         (cfg_inv_all         ),
        .cfg_inv_addr_valid  (cfg_inv_addr_valid  ),
        .cfg_inv_addr        (cfg_inv_addr        ),
        .enable              (enable              ),
        .sdt_l1_base         (sdt_l1_base         ),
        .inv_all             (inv_all             ),
        .inv_en              (inv_en              ),
        .inv_pa              (inv_pa              ),
        .inv_busy            (inv_busy            ),
        .err_set             (err_set             ),
        .err_fcode           (head_rsp.fcode      ),
        .err_rw              (head.rw             ),
        .err_pa              (head.pa             ),
        .errinfo_fcode       (errinfo_fcode       ),
        .errinfo_rw          (errinfo_rw          ),
        .errinfo_pa          (errinfo_pa          )
    );

    assign cfg_inv_busy = inv_busy;

    sdtlb u_sdtlb (
        .clk                 (clk                 ),
        .rst_n               (rst_n               ),
        .req_vld             (sdtlb_req_vld       ),
        .req_pa              (head.pa[PA_L1_IDX_MSB:PA_UP_LSB]),
        .req_hit             (sdtlb_req_hit       ),
        .req_hit_tag_item    (sdtlb_hit_tag       ),
        .req_hit_data_item   (sdtlb_hit_data      ),
        .fill_vld            (fill_vld            ),
        .fill_pa_base        (fill_pa_base        ),
        .fill_pa_up          (fill_pa_up          ),
        .fill_eid            (fill_eid            ),
        .fill_token_id       (fill_token_id       ),
        .fill_s_pfn          (fill_s_pfn          ),
        .fill_grn            (fill_grn            ),
        .inv_all             (inv_all             ),
        .inv_en              (inv_en              ),
        .inv_pa              (inv_pa              )
    );

    sdptw u_sdptw (
        .clk                 (clk                 ),
        .rst_n               (rst_n               ),
        .walk_vld            (walk_vld            ),
        .walk_req            (head                ),
        .walk_id             (rd_ptr              ),
        .walk_ready          (walk_ready          ),
        .sdt_l1_base         (sdt_l1_base         ),
        .tw_req_valid        (tw_req_valid        ),
        .tw_req_ready        (tw_req_ready        ),
        .tw_req_addr         (tw_req_addr         ),
        .tw_req_size         (tw_req_size         ),
        .tw_req_id           (tw_req_id           ),
        .tw_rsp_valid        (tw_rsp_valid        ),
        .tw_rsp_ready        (tw_rsp_ready        ),
        .tw_rsp_data         (tw_rsp_data         ),
        .tw_rsp_id           (tw_rsp_id           ),
        .tw_rsp_err          (tw_rsp_err          ),
        .fill_vld            (fill_vld            ),
        .fill_pa_base        (fill_pa_base        ),
        .fill_pa_up          (fill_pa_up          ),
        .fill_eid            (fill_eid            ),
        .fill_token_id       (fill_token_id       ),
        .fill_s_pfn          (fill_s_pfn          ),
        .fill_grn            (fill_grn            ),
        .done_vld            (walk_done_vld       ),
        .done_rsp            (walk_done_rsp       ),
        .done_ready          (rsp_free            ),
        .inv_busy            (inv_busy            )
    );

`ifdef ASSERT_ON
    // 被接收的请求不会丢: 每来一个请求就有一个响应 (由 tb 与形式检查覆盖);
    // 这里只查内部握手: 走表请求被接收时 walker 一定空闲
    `assert_clk(a_walk_vld_implies_ready, (walk_go |-> walk_ready))
`endif

endmodule

`default_nettype wire
