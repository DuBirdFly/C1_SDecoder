`default_nettype none

// SDPWU_CTRL: 把 SDMQ 里最老的待 Page Walk 条目分配给一个空闲的 SDPWU
//   - 空闲 SDPWU 的选择用轮转仲裁
//   - 多个 SDPWU 的 Page Walk 结果用 onehot 合并成 1 个 (访存接口只有一套)
module sdpwu_ctrl
import sdecoder_pkg::*;
#(
    parameter int unsigned PWU_NUM = SDPWU_NUM
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // SDMQ -> CTRL: 有最老的待 Page Walk 条目
    input  logic                    sdmq_pw_valid,
    input  SDPWU_START_t            sdmq_pw_item,
    output logic                    sdmq_pw_ready,

    // CTRL -> SDPWU[i]: start 握手
    output logic [PWU_NUM-1:0]      pwu_start_valid,
    input  logic [PWU_NUM-1:0]      pwu_start_ready,
    output logic [PWU_NUM-1:0][$bits(SDPWU_START_t)-1:0] pwu_start_item,

    // SDPWU[i] -> CTRL: finish, 合并成 1 路给 SDMQ
    input  logic [PWU_NUM-1:0]      pwu_finish_valid_vec,
    input  logic [PWU_NUM-1:0][$bits(SDPWU_FINISH_t)-1:0] pwu_finish_item_vec,
    output logic                    pwu_finish_valid,
    output logic [$bits(SDPWU_FINISH_t)-1:0] pwu_finish_item
);

    // 轮转仲裁: 上次选中的下一条开始找, 取第一个 ready 的 SDPWU
    int unsigned              last;
    logic [PWU_NUM-1:0]       grant;

    always_comb begin
        int unsigned idx;
        grant = '0;
        for (int i = 0; i < PWU_NUM; i++) begin
            idx = (last + 1 + i) % PWU_NUM;
            if ((grant == '0) && pwu_start_ready[idx]) begin
                grant[idx] = 1'b1;
            end
        end
    end

    assign sdmq_pw_ready   = |grant;

    // 没有待 Walk 的请求时不能给 SDPWU 发 start (否则空闲 SDPWU 会把 X / 0 当成请求)
    assign pwu_start_valid = {PWU_NUM{sdmq_pw_valid}} & grant;

    for (genvar i = 0; i < PWU_NUM; i++) begin : g_start_item
        assign pwu_start_item[i] = sdmq_pw_item;
    end

    // onehot 合并 finish (外界约定: 一拍最多 1 个 SDPWU 结束)
    always_comb begin
        pwu_finish_valid = |pwu_finish_valid_vec;
        pwu_finish_item  = '0;
        for (int i = 0; i < PWU_NUM; i++) begin
            if (pwu_finish_valid_vec[i]) begin
                pwu_finish_item = pwu_finish_item_vec[i];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last <= 0;
        end
        else if (sdmq_pw_valid && sdmq_pw_ready) begin
            for (int i = 0; i < PWU_NUM; i++) begin
                if (grant[i]) begin
                    last <= i;
                end
            end
        end
    end

`ifdef ASSERT_ON
    // 一拍最多一个 SDPWU 结束 (访存接口只有一套, SDMQ 一拍最多收 1 个 PTE)
    `assert_clk(a_finish_onehot0, ($onehot0(pwu_finish_valid_vec)))
    `assert_clk(a_start_onehot0,  ($onehot0(pwu_start_valid)))
`endif

endmodule

`default_nettype wire
