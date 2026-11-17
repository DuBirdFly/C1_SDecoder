`default_nettype none

// SDPWU: 单个 Page Walk 子状态机 (见设计方案 "SDPWU" 一节)
//   一次处理一个未命中请求, 最多访存 2 次: 先读一级表, 段式命中就结束; 否则再读二级表
//
//   IDLE -> L1_RD_ADDR -> L1_RD_DATA -> L1_CHK
//        -> L2_RD_ADDR -> L2_RD_DATA -> L2_CHK -> FINISH -> IDLE
module sdpwu
import sdecoder_pkg::*;
#(
    parameter int unsigned PWU_ID = 0       // 本 SDPWU 的编号, 用作访存请求的 id
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // 一级表基地址 (来自 SDecoder_PTBR, 48 bit)
    input  logic [PA_WIDTH-1:0]             l1_base,

    // start 握手: 由 SDPWU_CTRL 分配待 Walk 的请求
    input  logic [$bits(SDPWU_START_t)-1:0] start_item,
    input  logic                            start_valid,
    output logic                            start_ready,

    // 访存接口 (读地址通道)
    output logic                            mem_raddr_valid,
    output logic [PA_WIDTH-1:0]             mem_raddr,
    output logic [PW_ID_WIDTH-1:0]          mem_raddr_id,
    input  logic                            mem_raddr_ready,

    // 访存接口 (读数据通道)
    input  logic [PW_RDATA_WIDTH-1:0]       mem_rdata,
    input  logic [PW_ID_WIDTH-1:0]          mem_rdata_id,
    input  logic                            mem_rdata_valid,
    input  logic [PW_RDATA_ERR_WIDTH-1:0]   mem_rdata_err,
    output logic                            mem_rdata_ready,

    // Page Walk 结束 (单拍, 无握手)
    output logic                            finish_valid,
    output logic [$bits(SDPWU_FINISH_t)-1:0] finish_item
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_L1_RD_ADDR,
        S_L1_RD_DATA,
        S_L1_CHK,
        S_L2_RD_ADDR,
        S_L2_RD_DATA,
        S_L2_CHK,
        S_FINISH
    } state_e;

    state_e                         state;
    SDPWU_START_t                   req_q;          // 本次 Page Walk 的请求
    logic [PW_RDATA_WIDTH-1:0]      l1_word_q;      // 一级表条目
    logic [PW_RDATA_WIDTH-1:0]      l2_word_q;      // 二级表条目
    logic [PW_RDATA_ERR_WIDTH-1:0]  rd_err_q;       // 访存返回的错误
    SDPWU_FINISH_t                  finish_q;       // FINISH 那一拍输出

    // ---- 一级表条目地址 = {L1_BASE[47:4], 4'h0} + PA[46:35] * 16 ----
    // 用 PA_WIDTH+1 位加, 最高位 c 即越界
    wire [PA_WIDTH:0] l1_base_align = {1'b0, l1_base[PA_WIDTH-1:SDIOR_PTBR_LSB],
                                       {SDIOR_PTBR_LSB{1'b0}}};
    wire [PA_WIDTH:0] l1_index      = {{(PA_WIDTH + 1 - 12 - 4){1'b0}}, req_q.pa[46:PA_HIGH_LSB], 4'h0};
    wire [PA_WIDTH:0] l1_addr_sum   = l1_base_align + l1_index;

    // ---- 二级表条目地址 = {L1.SDT_L2_BASE[47:3], 3'h0} + PA[34:30] * 8 ----
    wire [PA_WIDTH:0] l2_base_align = {1'b0, l1_word_q[L1_L2_BASE_LSB +: L2_BASE_WIDTH], 3'h0};
    wire [PA_WIDTH:0] l2_index      = {{(PA_WIDTH + 1 - PA_UP_WIDTH - 3){1'b0}},
                                       req_q.pa[PA_BASE_LSB +: PA_UP_WIDTH], 3'h0};
    wire [PA_WIDTH:0] l2_addr_sum   = l2_base_align + l2_index;

    // ---- 一级表条目字段 ----
    wire [PA_UP_WIDTH-1:0] req_up       = req_q.pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_UP_WIDTH-1:0] l1_seg_base  = l1_word_q[L1_SEG_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_UP_WIDTH-1:0] l1_seg_len   = l1_word_q[L1_SEG_LEN_LSB  +: PA_UP_WIDTH];
    wire [PA_UP_WIDTH:0]   l1_seg_end   = {1'b0, l1_seg_base} + {1'b0, l1_seg_len};
    wire                   l1_valid     = l1_word_q[L1_VALID_BIT];
    wire                   l1_type      = l1_word_q[L1_TYPE_BIT];
    wire                   l1_seg_hit   = l1_type && (req_up >= l1_seg_base) &&
                                          (req_up <= l1_seg_base + l1_seg_len);

    // ---- 二级表条目字段 ----
    wire l2_valid = l2_word_q[L2_VALID_BIT];

    // ---- 判定结果 (组合) ----
    logic                          chk_done;      // 本次判定已经有结论, 直接进 FINISH
    logic                          chk_hit;
    logic [SDMQ_RSP_ERR_WIDTH-1:0] chk_err;
    logic [S_PFN_WIDTH-1:0]        chk_s_pfn;
    logic [EID_WIDTH-1:0]          chk_eid;
    logic [TOKEN_ID_WIDTH-1:0]     chk_token_id;
    logic [TOKEN_VALUE_WIDTH-1:0]  chk_token_value;

    always_comb begin
        chk_done        = 1'b0;
        chk_hit         = 1'b0;
        chk_err         = '0;
        chk_s_pfn       = '0;
        chk_eid         = '0;
        chk_token_id    = '0;
        chk_token_value = '0;

        if (state == S_L1_CHK) begin
            // 访存报错 (ctrl / ecc / oob) 优先
            if (rd_err_q[PW_RDATA_ERR_CTRL_BIT]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_CTRL_BIT] = 1'b1;
            end
            else if (rd_err_q[PW_RDATA_ERR_ECC_BIT]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_ECC_BIT] = 1'b1;
            end
            else if (rd_err_q[PW_RDATA_ERR_OOB_BIT] || l1_addr_sum[PA_WIDTH]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_OOB_BIT] = 1'b1;
            end
            // 一级表条目本身非法
            else if (l1_seg_end > 6'd31) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_MALFORMED_BIT] = 1'b1;
            end
            else if (!l1_valid) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_PAGE_FAULT_BIT] = 1'b1;
            end
            else if (l1_seg_hit) begin
                // 段式命中: SLA[52:30] = S_PFN + (PA[34:30] - SEG_BASE)
                chk_done        = 1'b1;
                chk_hit         = 1'b1;
                chk_s_pfn       = l1_word_q[L1_S_PFN_LSB +: S_PFN_WIDTH] +
                                  {18'b0, req_up - l1_seg_base};
                chk_eid         = l1_word_q[L1_EID_LSB +: EID_WIDTH];
                chk_token_id    = l1_word_q[L1_TOKEN_ID_LSB +: TOKEN_ID_WIDTH];
                chk_token_value = l1_word_q[L1_TOKEN_VALUE_LSB +: TOKEN_VALUE_WIDTH];
            end
            // 否则 (Type = 0 或段式未命中) 继续查二级表
        end
        else if (state == S_L2_CHK) begin
            if (rd_err_q[PW_RDATA_ERR_CTRL_BIT]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_CTRL_BIT] = 1'b1;
            end
            else if (rd_err_q[PW_RDATA_ERR_ECC_BIT]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_ECC_BIT] = 1'b1;
            end
            else if (rd_err_q[PW_RDATA_ERR_OOB_BIT] || l2_addr_sum[PA_WIDTH]) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_OOB_BIT] = 1'b1;
            end
            else if (!l2_valid) begin
                chk_done = 1'b1;
                chk_err[SDMQ_RSP_ERR_PAGE_FAULT_BIT] = 1'b1;
            end
            else begin
                chk_done        = 1'b1;
                chk_hit         = 1'b1;
                chk_s_pfn       = l2_word_q[L2_S_PFN_LSB +: S_PFN_WIDTH];
                chk_eid         = l2_word_q[L2_EID_LSB +: EID_WIDTH];
                chk_token_id    = l2_word_q[L2_TOKEN_ID_LSB +: TOKEN_ID_WIDTH];
                chk_token_value = l2_word_q[L2_TOKEN_VALUE_LSB +: TOKEN_VALUE_WIDTH];
            end
        end
    end

    assign start_ready     = (state == S_IDLE);
    assign mem_raddr_valid = (state == S_L1_RD_ADDR) || (state == S_L2_RD_ADDR);
    assign mem_raddr       = (state == S_L1_RD_ADDR) ? l1_addr_sum[PA_WIDTH-1:0]
                                                     : l2_addr_sum[PA_WIDTH-1:0];
    assign mem_raddr_id    = PW_ID_WIDTH'(PWU_ID);
    assign mem_rdata_ready = ((state == S_L1_RD_DATA) || (state == S_L2_RD_DATA)) &&
                             (mem_rdata_id == PW_ID_WIDTH'(PWU_ID));

    assign finish_valid = (state == S_FINISH);
    assign finish_item  = finish_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            req_q    <= '0;
            l1_word_q <= '0;
            l2_word_q <= '0;
            rd_err_q <= '0;
            finish_q <= '0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (start_valid && start_ready) begin
                        req_q <= SDPWU_START_t'(start_item);
                        state <= S_L1_RD_ADDR;
                    end
                end

                S_L1_RD_ADDR: begin
                    if (mem_raddr_ready) begin
                        state <= S_L1_RD_DATA;
                    end
                end

                S_L1_RD_DATA: begin
                    if (mem_rdata_valid && mem_rdata_ready) begin
                        l1_word_q <= mem_rdata;
                        rd_err_q  <= mem_rdata_err;
                        state     <= S_L1_CHK;
                    end
                end

                S_L1_CHK: begin
                    if (chk_done) begin
                        finish_q <= '{sdmq_idx: req_q.sdmq_idx, hit: chk_hit,
                                      eid: chk_eid, token_id: chk_token_id,
                                      token_value: chk_token_value, s_pfn: chk_s_pfn,
                                      err: chk_err};
                        state <= S_FINISH;
                    end
                    else begin
                        state <= S_L2_RD_ADDR;
                    end
                end

                S_L2_RD_ADDR: begin
                    if (mem_raddr_ready) begin
                        state <= S_L2_RD_DATA;
                    end
                end

                S_L2_RD_DATA: begin
                    if (mem_rdata_valid && mem_rdata_ready) begin
                        l2_word_q <= mem_rdata;
                        rd_err_q  <= mem_rdata_err;
                        state     <= S_L2_CHK;
                    end
                end

                S_L2_CHK: begin
                    finish_q <= '{sdmq_idx: req_q.sdmq_idx, hit: chk_hit,
                                  eid: chk_eid, token_id: chk_token_id,
                                  token_value: chk_token_value, s_pfn: chk_s_pfn,
                                  err: chk_err};
                    state <= S_FINISH;
                end

                S_FINISH: begin
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
