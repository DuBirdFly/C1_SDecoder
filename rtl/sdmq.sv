`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdmq
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 未命中申请 (来自 SDTLB 的 cam0 / cam1), en 单拍有效
    input  logic                        cam0_miss_en,
    input  logic [PA_WIDTH-1:0]         cam0_miss_pa,
    input  logic [REQ_ID_WIDTH-1:0]     cam0_miss_id,

    input  logic                        cam1_miss_en,
    input  logic [PA_WIDTH-1:0]         cam1_miss_pa,
    input  logic [REQ_ID_WIDTH-1:0]     cam1_miss_id,

    // 队列将满: 已用条目数超过 SDMQ_DEPTH-2 时拉高 (剩余空闲不足 2 个),
    // 上游据此反压两路请求;
    // 由 sdmq 自己维护的 item_num_cnt 产生, 不依赖条目 valid 的归约 (怕时序不好)
    output logic                        queue_almost_full,

    // 与 SDPWU 的接口 (全是组合逻辑接口)
    input  logic [SDMQ_DEPTH-1:0]       item_read_en,
    output SDMQ_ITEM_t                  item_read_data,

    input  logic [SDMQ_DEPTH-1:0]       item_age_find,          // 候选的 age 条目
    output logic [SDMQ_DEPTH-1:0]       item_age_oldest_vec,    // 从候选的 age 条目里选出的最老条目 (one-hot)

    input  logic [SDMQ_DEPTH-1:0]       item_del,

    input  logic [PA_BASE_WIDTH-1:0]    chk_hit_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      chk_hit_pa_up,
    output logic [SDMQ_DEPTH-1:0]       chk_hit_vec,

    output logic [SDMQ_DEPTH-1:0]       item_valid_vec,
    output logic [SDMQ_DEPTH-1:0]       item_flushed_vec,

    // 置无效 (刷新), 来自 SDIOR
    input  logic                        inv_all,
    input  logic                        inv_en,
    input  logic [PA_WIDTH-1:0]         inv_pa
);

    localparam int unsigned ITEM_CNT_WIDTH = $clog2(SDMQ_DEPTH + 1);

    // 已用条目数: 每个未命中申请 +1, 每弹出一个条目 -1, 范围 0 ~ SDMQ_DEPTH
    logic [ITEM_CNT_WIDTH-1:0] item_num_cnt;
    wire  [ITEM_CNT_WIDTH-1:0] item_num_fill = cam0_miss_en + cam1_miss_en;

    // 空闲不足 2 个 (还剩 0/1 个空闲条目) 时反压, 保证同拍最多 2 个申请不会溢出
    assign queue_almost_full = (item_num_cnt > SDMQ_DEPTH - 2);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            item_num_cnt <= '0;
        end
        else begin
            item_num_cnt <= item_num_cnt + item_num_fill - (|item_del);
        end
    end

    // [TODO] 条目数组、年龄矩阵、分配 / 弹出 / 扫描选择

`ifdef ASSERT_ON
    // [TODO] 断言 item_num_cnt 与所有条目 valid 的统计值一致:
    //        item_num_cnt == $countbits(item_valid_vec, 1'b1)
    //        (item_valid_vec 是 SDMQ_DEPTH 个条目的 valid 拼成的向量)

    // [TODO] 断言 item_read_en 是 $onehot0
    //        断言 item_read_en 来自于 item_valid_vec (只读有效条目)

    // [TODO] 断言 item_age_find 来自于 item_valid_vec (只选有效条目)

    // [TODO] 断言 item_age_oldest_vec 在 item_age_find 非 0 时为 $onehot
    //        断言 item_age_oldest_vec 在 item_age_find 为 0 时为 0
    //        断言 item_age_oldest_vec 来自于 item_age_find (只选候选条目)

    // [TODO] 断言 item_del 是 $onehot0

    // [TODO] 断言 item_del 来自于 item_valid_vec (只删有效条目)

`endif

endmodule

`default_nettype wire
