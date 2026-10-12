`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdecoder page table walker: 遍历 SDT_L1 / SDT_L2, 算出 PA 对应的 SMD
//   并行度 1: 同一时刻只走一个请求; 最坏两次本地读 (一级条目 16B, 二级条目 8B)
//   状态机: IDLE -> WALK_L1 -> (段命中) DONE / (否则) WALK_L2 -> DONE, 异常进 FAULT
//   一次走表以 done_vld 脉冲给出结果 (SMD 或异常); 段式/页式成功时同时回填 SDTLB
module sdptw
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 未命中队列给出的走表请求
    input  logic                        walk_vld,
    input  SDEC_REQ_t                   walk_req,
    output logic                        walk_ready,

    // 代换表基地址
    input  logic [PA_WIDTH-1:0]         sdt_l1_base,

    // Page Walk 访存接口 (主端口)
    output logic                        tw_req_valid,
    input  logic                        tw_req_ready,
    output logic [PA_WIDTH-1:0]         tw_req_addr,
    output logic                        tw_req_size,
    input  logic                        tw_rsp_valid,
    output logic                        tw_rsp_ready,
    input  logic [127:0]                tw_rsp_data,
    input  logic [1:0]                  tw_rsp_err,

    // 回填 SDTLB (刷新期间禁止)
    output logic                        fill_vld,
    output logic [PA_BASE_WIDTH-1:0]    fill_pa_base,
    output logic [PA_UP_WIDTH-1:0]      fill_pa_up,
    output logic [EID_WIDTH-1:0]        fill_eid,
    output logic [TOKEN_ID_WIDTH-1:0]   fill_token_id,
    output logic [S_PFN_WIDTH-1:0]      fill_s_pfn,
    output logic                        fill_grn,

    // 走表结果 (SMD 或异常): 保持到被 done_ready 收走
    output logic                        done_vld,
    output SDEC_RSP_t                   done_rsp,
    input  logic                        done_ready,

    // 置无效 (刷新) 进行中, 期间不回填
    input  logic                        inv_busy
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_WALK_L1,
        ST_WALK_L2,
        ST_DONE,
        ST_FAULT
    } state_e;

    state_e                     state;
    logic [PA_WIDTH-1:0]        req_pa;
    logic [REQ_ID_WIDTH-1:0]    req_id;
    logic                       req_sent;       // 本次访存请求已被本地存储接收
    logic                       fill_vld_r;     // 回填 SDTLB: 成功的那一拍拉高一次
    logic [44:0]                l2_base;        // 一级条目给出的二级表基地址, 取回后锁存

    // 读回条目: 只在 tw_rsp_valid 那一拍有效, 其中二级表基址用到的字段必须锁存
    SDT_L1_ITEM_t               l1_item;
    SDT_L2_ITEM_t               l2_item;
    assign l1_item = tw_rsp_data;
    assign l2_item = tw_rsp_data[63:0];

    // 段命中: Type = 1 且 PA[34:30] 落在闭区间 [SEG_BASE, SEG_BASE + SEG_LEN]
    wire [PA_UP_WIDTH:0]        seg_up     = {1'b0, l1_item.seg_base} + {1'b0, l1_item.seg_len};
    wire                        seg_hit    = l1_item.type_bit &&
                                             (req_pa[PA_UP_MSB:PA_UP_LSB] >= l1_item.seg_base) &&
                                             ({1'b0, req_pa[PA_UP_MSB:PA_UP_LSB]} <= seg_up);
    wire [PA_UP_WIDTH-1:0]      seg_offset = req_pa[PA_UP_MSB:PA_UP_LSB] - l1_item.seg_base;

    // SLA = {S_PFN + 段内偏移, 页内偏移}; 段式的加法产生进位即溢出
    wire [S_PFN_WIDTH:0]        sla_hi_seg = {1'b0, l1_item.s_pfn} +
                                             {{(S_PFN_WIDTH + 1 - PA_UP_WIDTH){1'b0}}, seg_offset};
    wire [S_PFN_WIDTH:0]        sla_hi_pag = {1'b0, l2_item.s_pfn};
    wire                        seg_ovf    = sla_hi_seg[S_PFN_WIDTH];

    // 条目地址 (见设计方案 两级代换表结构)
    wire [PA_WIDTH-1:0]         l1_addr = {sdt_l1_base[PA_WIDTH-1:4], 4'h0} +
                                          {{(PA_WIDTH - PA_L1_IDX_WIDTH - 4){1'b0}},
                                            req_pa[PA_L1_IDX_MSB:PA_L1_IDX_LSB], 4'h0};
    wire [PA_WIDTH-1:0]         l2_addr = {l2_base, 3'h0} +
                                          {{(PA_WIDTH - PA_UP_WIDTH - 3){1'b0}},
                                            req_pa[PA_UP_MSB:PA_UP_LSB], 3'h0};

    // tw_rsp_err: 2'b00 正常, 2'b01 可纠错(硬件已纠正, 继续), 2'b10 / 2'b11 不可纠错
    wire                        rsp_err_fatal = tw_rsp_err[1];

    localparam SDEC_RSP_t RSP_NONE  = '{req_id: '0, fault: 1'b0, fcode: FCODE_NONE,
                                        eid: '0, token_id: '0, sla: '0};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            req_pa        <= '0;
            req_id        <= '0;
            req_sent      <= 1'b0;
            fill_vld_r    <= 1'b0;
            l2_base       <= '0;
            fill_pa_base  <= '0;
            fill_pa_up    <= '0;
            fill_eid      <= '0;
            fill_token_id <= '0;
            fill_s_pfn    <= '0;
            fill_grn      <= 1'b0;
            done_rsp      <= RSP_NONE;
        end
        else begin
            fill_vld_r <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (walk_vld && walk_ready) begin
                        req_pa   <= walk_req.pa;
                        req_id   <= walk_req.req_id;
                        req_sent <= 1'b0;
                        state    <= ST_WALK_L1;
                    end
                end
                ST_WALK_L1: begin
                    if (!req_sent) begin
                        if (tw_req_valid && tw_req_ready) begin
                            req_sent <= 1'b1;
                        end
                    end
                    else if (tw_rsp_valid && tw_rsp_ready) begin
                        if (rsp_err_fatal) begin
                            done_rsp <= '{req_id: req_id, fault: 1'b1, fcode: FCODE_UNCORRECT,
                                                   eid: '0, token_id: '0, sla: '0};
                            state    <= ST_FAULT;
                        end
                        else if (!l1_item.valid) begin
                            done_rsp <= '{req_id: req_id, fault: 1'b1, fcode: FCODE_ADDR_ILLEGAL,
                                                   eid: '0, token_id: '0, sla: '0};
                            state    <= ST_FAULT;
                        end
                        else if (seg_hit) begin
                            if (seg_ovf) begin
                                done_rsp <= '{req_id: req_id, fault: 1'b1, fcode: FCODE_ADDR_ILLEGAL,
                                                   eid: '0, token_id: '0, sla: '0};
                                state    <= ST_FAULT;
                            end
                            else begin
                                done_rsp      <= '{req_id: req_id, fault: 1'b0, fcode: FCODE_NONE,
                                                   eid: l1_item.eid, token_id: l1_item.token_id,
                                                   sla: {sla_hi_seg[S_PFN_WIDTH-1:0],
                                                         req_pa[PA_OFFSET_WIDTH-1:0]}};
                                fill_vld_r    <= 1'b1;
                                fill_pa_base  <= {req_pa[PA_L1_IDX_MSB:PA_L1_IDX_LSB], l1_item.seg_base};
                                fill_pa_up    <= seg_up[PA_UP_WIDTH-1:0];
                                fill_eid      <= l1_item.eid;
                                fill_token_id <= l1_item.token_id;
                                fill_s_pfn    <= l1_item.s_pfn;
                                fill_grn      <= 1'b1;
                                state         <= ST_DONE;
                            end
                        end
                        else begin
                            l2_base  <= l1_item.l2_base;
                            req_sent <= 1'b0;
                            state    <= ST_WALK_L2;
                        end
                    end
                end
                ST_WALK_L2: begin
                    if (!req_sent) begin
                        if (tw_req_valid && tw_req_ready) begin
                            req_sent <= 1'b1;
                        end
                    end
                    else if (tw_rsp_valid && tw_rsp_ready) begin
                        if (rsp_err_fatal) begin
                            done_rsp <= '{req_id: req_id, fault: 1'b1, fcode: FCODE_UNCORRECT,
                                                   eid: '0, token_id: '0, sla: '0};
                            state    <= ST_FAULT;
                        end
                        else if (!l2_item.valid) begin
                            done_rsp <= '{req_id: req_id, fault: 1'b1, fcode: FCODE_ADDR_ILLEGAL,
                                                   eid: '0, token_id: '0, sla: '0};
                            state    <= ST_FAULT;
                        end
                        else begin
                            done_rsp      <= '{req_id: req_id, fault: 1'b0, fcode: FCODE_NONE,
                                               eid: l2_item.eid, token_id: l2_item.token_id,
                                               sla: {sla_hi_pag[S_PFN_WIDTH-1:0],
                                                     req_pa[PA_OFFSET_WIDTH-1:0]}};
                            fill_vld_r    <= 1'b1;
                            fill_pa_base  <= req_pa[PA_L1_IDX_MSB:PA_UP_LSB];
                            fill_pa_up    <= req_pa[PA_UP_MSB:PA_UP_LSB];
                            fill_eid      <= l2_item.eid;
                            fill_token_id <= l2_item.token_id;
                            fill_s_pfn    <= l2_item.s_pfn;
                            fill_grn      <= 1'b0;
                            state         <= ST_DONE;
                        end
                    end
                end
                ST_DONE: begin
                    if (done_ready) begin
                        state <= ST_IDLE;
                    end
                end
                ST_FAULT: begin
                    if (done_ready) begin
                        state <= ST_IDLE;
                    end
                end
                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // 走表请求: 空闲时可以接收 (tw_req_valid 不组合依赖 tw_req_ready)
    assign walk_ready   = (state == ST_IDLE);

    // 访存请求: 发出后保持到被接收; 一级条目 16B, 二级条目 8B
    assign tw_req_valid = ((state == ST_WALK_L1) || (state == ST_WALK_L2)) && !req_sent;
    assign tw_req_addr  = (state == ST_WALK_L2) ? l2_addr : l1_addr;
    assign tw_req_size  = (state == ST_WALK_L2) ? 1'b0 : 1'b1;
    assign tw_rsp_ready = (state == ST_WALK_L1) || (state == ST_WALK_L2);

    // 回填 SDTLB: 只在 DONE 那一拍, 刷新 (置无效) 期间禁止
    assign fill_vld     = fill_vld_r && !inv_busy;

    // 走表结果 (结果或异常): 保持到 done_ready 收走, 避免下游忙时丢结果
    assign done_vld     = (state == ST_DONE) || (state == ST_FAULT);

`ifdef ASSERT_ON
    // 软件约束: 段必须落在本条目所属的 32GB 区间内
    `assert_clk(a_seg_range_valid,
                (((state == ST_WALK_L1) && req_sent && tw_rsp_valid && tw_rsp_ready &&
                  l1_item.valid && l1_item.type_bit) |-> (seg_up <= 31)))
`endif

endmodule

`default_nettype wire
