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
    input  logic [SDMQ_DEPTH-1:0]       item_read_en,           // 读条目, one-hot 选择
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
    localparam int unsigned ITEM_WIDTH = $bits(SDMQ_ITEM_t);

    // ========================================================================
    // 空闲条目数计算
    // ========================================================================

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

    // ========================================================================
    // 条目、年龄矩阵与分配
    // ========================================================================

    SDMQ_ITEM_t item [SDMQ_DEPTH];
    logic [ITEM_WIDTH-1:0] item_data [SDMQ_DEPTH];
    logic [ITEM_WIDTH-1:0] item_read_data_vec;
    logic [SDMQ_DEPTH-1:0] matrix [SDMQ_DEPTH-1:0];

    logic [SDMQ_DEPTH-1:0] cam0_free;
    logic [SDMQ_DEPTH-1:0] cam1_free;

    find_first_zero #(
        .A_WIDTH (SDMQ_DEPTH)
    ) u_cam0_free (
        .a         (item_valid_vec),
        .direction (1'b0),
        .dec       (cam0_free),
        .enc       ()
    );

    find_first_zero #(
        .A_WIDTH (SDMQ_DEPTH)
    ) u_cam1_free (
        .a         (item_valid_vec),
        .direction (1'b1),
        .dec       (cam1_free),
        .enc       ()
    );

    wire [SDMQ_DEPTH-1:0] cam0_pos = cam0_miss_en ? cam0_free : '0;
    wire [SDMQ_DEPTH-1:0] cam1_pos = cam1_miss_en ? cam1_free : '0;
    wire [SDMQ_DEPTH-1:0] fill_vec = cam0_pos | cam1_pos;

    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDMQ_DEPTH; genvar_i++) begin : gen_item
            sdmq_item u_item (
                .clk             (clk),
                .rst_n           (rst_n),

                .chk_hit_pa_base (chk_hit_pa_base),
                .chk_hit_pa_up   (chk_hit_pa_up),
                .chk_hit         (chk_hit_vec[genvar_i]),

                .fill_en         (fill_vec[genvar_i]),
                .fill_id         (cam0_pos[genvar_i] ? cam0_miss_id : cam1_miss_id),
                .fill_pa         (cam0_pos[genvar_i] ? cam0_miss_pa : cam1_miss_pa),

                .del_en          (item_del[genvar_i]),

                .inv_all         (inv_all),
                .inv_en          (inv_en),
                .inv_pa          (inv_pa),

                .sdmq_item       (item[genvar_i])
            );

            assign item_valid_vec[genvar_i]   = item[genvar_i].valid;
            assign item_flushed_vec[genvar_i] = item[genvar_i].flushed;
            assign item_data[genvar_i]        = item[genvar_i];
        end
    endgenerate

    age_matrix #(
        .ITEM_DEPTH (SDMQ_DEPTH)
    ) u_age_matrix (
        .clk        (clk),
        .req_pos_1  (cam0_pos),
        .req_pos_2  (cam1_pos),
        .matrix     (matrix)
    );

    age_matrix_find_oldest #(
        .ITEM_DEPTH (SDMQ_DEPTH)
    ) u_find_oldest (
        .matrix     (matrix),
        .item_valid (item_age_find),
        .oldest_vec (item_age_oldest_vec)
    );

    // 读条目: item_read_en 是 one-hot 选择, sel 全 0 时输出全 0
    onehot0_mux #(
        .N     (SDMQ_DEPTH),
        .WIDTH (ITEM_WIDTH)
    ) u_item_read_mux (
        .sel  (item_read_en),
        .din  (item_data),
        .dout (item_read_data_vec)
    );

    assign item_read_data = item_read_data_vec;

`ifdef ASSERT_ON
    // 计数器和条目 valid 的统计值一致
    `assert_clk(a_num_cnt_match, item_num_cnt == $countbits(item_valid_vec, 1'b1))

    // SDPWU 侧接口: 读 / 选 / 删都只作用于有效条目, 且都是 one-hot
    `assert_clk(a_read_onehot0,         $onehot0(item_read_en))
    `assert_clk(a_read_from_valid,      (item_read_en & ~item_valid_vec) == '0)
    `assert_clk(a_age_find_from_valid,  (item_age_find & ~item_valid_vec) == '0)
    `assert_clk(a_age_oldest_from_find, (item_age_oldest_vec & ~item_age_find) == '0)
    `assert_clk(a_age_oldest_onehot,    (item_age_find != '0) |-> $onehot(item_age_oldest_vec))
    `assert_clk(a_age_oldest_zero,      (item_age_find == '0) |-> (item_age_oldest_vec == '0))
    `assert_clk(a_del_onehot0,          $onehot0(item_del))
    `assert_clk(a_del_from_valid,       (item_del & ~item_valid_vec) == '0)
`endif

endmodule

`default_nettype wire
