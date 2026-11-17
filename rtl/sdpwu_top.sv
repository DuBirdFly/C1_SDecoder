`default_nettype none

// SDPWU_TOP: SDPWU_CTRL + N 个 SDPWU + 共享访存接口的仲裁 / 路由
//   访存请求: N 个 SDPWU 轮转仲裁成 1 路
//   访存响应: 按 pw_mem_rdata_id 路由回对应的 SDPWU
//   Page Walk 结果: 由 SDPWU_CTRL 做 onehot 合并
module sdpwu_top
import sdecoder_pkg::*;
#(
    parameter int unsigned PWU_NUM = SDPWU_NUM
)(
    input  logic                            clk,
    input  logic                            rst_n,

    // 一级表基地址 (来自 sdior 的 SDecoder_PTBR)
    input  logic [PA_WIDTH-1:0]             l1_base,

    // SDMQ <-> SDPWU_CTRL
    input  logic                            sdmq_pw_valid,
    input  SDPWU_START_t                    sdmq_pw_item,
    output logic                            sdmq_pw_ready,

    // 访存接口 (读地址通道)
    output logic                            pw_mem_raddr_valid,
    output logic [PA_WIDTH-1:0]             pw_mem_raddr,
    output logic [PW_ID_WIDTH-1:0]          pw_mem_raddr_id,
    input  logic                            pw_mem_raddr_ready,

    // 访存接口 (读数据通道)
    input  logic [PW_RDATA_WIDTH-1:0]       pw_mem_rdata,
    input  logic [PW_ID_WIDTH-1:0]          pw_mem_rdata_id,
    input  logic                            pw_mem_rdata_valid,
    input  logic [PW_RDATA_ERR_WIDTH-1:0]   pw_mem_rdata_err,
    output logic                            pw_mem_rdata_ready,

    // Page Walk 结果 (单拍)
    output logic                            pwu_finish_valid,
    output logic [$bits(SDPWU_FINISH_t)-1:0] pwu_finish_item
);

    // CTRL <-> SDPWU
    logic [PWU_NUM-1:0]     start_valid_vec;
    logic [PWU_NUM-1:0]     start_ready_vec;
    logic [PWU_NUM-1:0][$bits(SDPWU_START_t)-1:0]  start_item_vec;
    logic [PWU_NUM-1:0]     finish_valid_vec;
    logic [PWU_NUM-1:0][$bits(SDPWU_FINISH_t)-1:0] finish_item_vec;

    // SDPWU <-> 访存接口
    logic [PWU_NUM-1:0]     m_raddr_valid_vec;
    logic [PWU_NUM-1:0]     m_raddr_ready_vec;
    logic [PA_WIDTH-1:0]    m_raddr_vec [PWU_NUM];
    logic [PWU_NUM-1:0]     m_rdata_valid_vec;
    logic [PWU_NUM-1:0]     m_rdata_ready_vec;

    sdpwu_ctrl #(
        .PWU_NUM (PWU_NUM)
    ) u_sdpwu_ctrl (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .sdmq_pw_valid          (sdmq_pw_valid),
        .sdmq_pw_item           (sdmq_pw_item),
        .sdmq_pw_ready          (sdmq_pw_ready),
        .pwu_start_valid        (start_valid_vec),
        .pwu_start_ready        (start_ready_vec),
        .pwu_start_item         (start_item_vec),
        .pwu_finish_valid_vec   (finish_valid_vec),
        .pwu_finish_item_vec    (finish_item_vec),
        .pwu_finish_valid       (pwu_finish_valid),
        .pwu_finish_item        (pwu_finish_item)
    );

    for (genvar i = 0; i < PWU_NUM; i++) begin : g_sdpwu
        sdpwu #(
            .PWU_ID (i)
        ) u_sdpwu (
            .clk                (clk),
            .rst_n              (rst_n),
            .l1_base            (l1_base),
            .start_item         (start_item_vec[i]),
            .start_valid        (start_valid_vec[i]),
            .start_ready        (start_ready_vec[i]),
            .mem_raddr_valid    (m_raddr_valid_vec[i]),
            .mem_raddr          (m_raddr_vec[i]),
            .mem_raddr_id       (),
            .mem_raddr_ready    (m_raddr_ready_vec[i]),
            .mem_rdata          (pw_mem_rdata),
            .mem_rdata_id       (pw_mem_rdata_id),
            .mem_rdata_valid    (m_rdata_valid_vec[i]),
            .mem_rdata_err      (pw_mem_rdata_err),
            .mem_rdata_ready    (m_rdata_ready_vec[i]),
            .finish_valid       (finish_valid_vec[i]),
            .finish_item        (finish_item_vec[i])
        );
    end

    // 访存请求: 轮转仲裁
    int unsigned        mem_last;
    logic [PWU_NUM-1:0] mem_grant;

    always_comb begin
        int unsigned idx;
        mem_grant = '0;
        for (int i = 0; i < PWU_NUM; i++) begin
            idx = (mem_last + 1 + i) % PWU_NUM;
            if ((mem_grant == '0) && m_raddr_valid_vec[idx]) begin
                mem_grant[idx] = 1'b1;
            end
        end
    end

    always_comb begin
        pw_mem_raddr      = '0;
        pw_mem_raddr_id   = '0;
        for (int i = 0; i < PWU_NUM; i++) begin
            if (mem_grant[i]) begin
                pw_mem_raddr    = m_raddr_vec[i];
                pw_mem_raddr_id = PW_ID_WIDTH'(i);
            end
        end
    end

    assign pw_mem_raddr_valid = |mem_grant;

    for (genvar i = 0; i < PWU_NUM; i++) begin : g_raddr_ready
        assign m_raddr_ready_vec[i] = mem_grant[i] && pw_mem_raddr_ready;
    end

    // 访存响应: 按 id 路由
    for (genvar i = 0; i < PWU_NUM; i++) begin : g_rdata
        assign m_rdata_valid_vec[i] = pw_mem_rdata_valid &&
                                      (pw_mem_rdata_id == PW_ID_WIDTH'(i));
    end

    assign pw_mem_rdata_ready = m_rdata_ready_vec[pw_mem_rdata_id];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_last <= 0;
        end
        else if (pw_mem_raddr_valid && pw_mem_raddr_ready) begin
            mem_last <= pw_mem_raddr_id;
        end
    end

`ifdef ASSERT_ON
    `assert_clk(a_mem_req_onehot0, ($onehot0(mem_grant)))
`endif

endmodule

`default_nettype wire
