`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB: 全相联 (CAM + FF + Latch), 2 个查表端口 (CAM0 / CAM1)
//
// 查表时序:
//   请求拍 T 两路各自握手 (valid && ready), 用当拍条目的内容做组合比较;
//   命中向量与选出的 tag / data 快照在 T 的上升沿打 1 拍, T+1 拍由
//   camN_hit / camN_hit_tag_item / camN_hit_data_item 给出.
//   camN_hit 同时充当响应的 valid: 没有握手的拍按 0 打拍, 所以请求撤掉后
//   下一拍命中自然归 0, 被反压的拍也不会漏出上一拍的陈旧结果.
//
// 装填 / 置无效时序:
//   条目除 Valid (FF) 外都用 Latch. Latch 的写使能必须来自寄存器, 否则
//   fill_en / inv_* 与写数据同拍变化时, 使能会短暂指向上一次的目标条目,
//   把数据写进别的条目. 因此装填与置无效都先在请求拍寄存:
//     T   拍: fill_en 有效, 选定目标条目 (空闲 / 轮转 victim)
//     T+1 拍: Latch 用寄存的使能和数据写入, Valid 也在这一拍置位 / 清位
//   写周期内 Latch 对输入透明, 不能查表, 因此 T+1 拍把两路 camN_req_ready 都拉低.
module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 查表端口 0 (CAM0). 地址是整条 PA[47:0] (条目里只存 PA[47:30], 见 sdtlb_tag_item)
    input  logic                                cam0_req_valid,
    output logic                                cam0_req_ready,
    input  logic [PA_WIDTH-1:0]                 cam0_req_pa,
    output logic                                cam0_hit,
    output SDTLB_TAG_ITEM_t                     cam0_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    cam0_hit_data_item,

    // 查表端口 1 (CAM1)
    input  logic                                cam1_req_valid,
    output logic                                cam1_req_ready,
    input  logic [PA_WIDTH-1:0]                 cam1_req_pa,
    output logic                                cam1_hit,
    output SDTLB_TAG_ITEM_t                     cam1_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    cam1_hit_data_item,

    // 装填: sdptw 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目, 请求拍有效.
    // 注意这里与 camN_req_pa / inv_pa 口径不同: 装填来自 sdptw, 它本来就算在 PA[47:30] 上,
    // 所以 fill_pa_base 就保持 PA[47:30] (18 位), 不必先补齐到整条 PA 再切回来
    input  logic                                fill_en,
    input  logic [PA_BASE_WIDTH-1:0]            fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_pa_up,
    input  logic [EID_WIDTH-1:0]                fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]           fill_token_id,
    input  logic [S_PFN_WIDTH-1:0]              fill_s_pfn,

    // 置无效 (刷新): 只作用于 Tag 侧的有效位; 地址也是整条 PA[47:0]
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_WIDTH-1:0]                 inv_pa
);

    SDTLB_TAG_ITEM_t  tag_item  [SDTLB_ENTRIES];
    SDTLB_DATA_ITEM_t data_item [SDTLB_ENTRIES];

    // 装填的写使能: 选中的条目在本拍写 Latch (目标由轮转指针给出)
    logic [SDTLB_ENTRIES-1:0]   fill_en_vector;

    logic [SDTLB_ENTRIES-1:0] cam0_hit_vector;
    logic [SDTLB_ENTRIES-1:0] cam1_hit_vector;
    logic [SDTLB_ENTRIES-1:0] cam0_hit_vector_r;
    logic [SDTLB_ENTRIES-1:0] cam1_hit_vector_r;
    logic [SDTLB_ENTRIES-1:0] victim_sel;

    // 请求拍选出的命中 tag / data 快照, 与命中向量在同一沿寄存
    SDTLB_TAG_ITEM_t  cam0_hit_tag_sel;
    SDTLB_DATA_ITEM_t cam0_hit_data_sel;
    SDTLB_TAG_ITEM_t  cam1_hit_tag_sel;
    SDTLB_DATA_ITEM_t cam1_hit_data_sel;
    SDTLB_TAG_ITEM_t  cam0_hit_tag_r;
    SDTLB_DATA_ITEM_t cam0_hit_data_r;
    SDTLB_TAG_ITEM_t  cam1_hit_tag_r;
    SDTLB_DATA_ITEM_t cam1_hit_data_r;

    // 写 Latch 当拍反压两路查表: Latch 不支持同拍读写
    assign cam0_req_ready = rst_n && !fill_en;
    assign cam1_req_ready = rst_n && !fill_en;

    // 比较使能取 "accept": 只有真正握手的那一拍才产生命中, 被反压的拍按 0 打拍
    wire cam0_en = cam0_req_valid && cam0_req_ready;
    wire cam1_en = cam1_req_valid && cam1_req_ready;

    assign fill_en_vector = fill_en ? victim_sel : '0;

    assign cam0_hit           = |cam0_hit_vector_r;
    assign cam0_hit_tag_item  = cam0_hit_tag_r;
    assign cam0_hit_data_item = cam0_hit_data_r;
    assign cam1_hit           = |cam1_hit_vector_r;
    assign cam1_hit_tag_item  = cam1_hit_tag_r;
    assign cam1_hit_data_item = cam1_hit_data_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cam0_hit_vector_r <= '0;
            cam1_hit_vector_r <= '0;
            cam0_hit_tag_r    <= '0;
            cam0_hit_data_r   <= '0;
            cam1_hit_tag_r    <= '0;
            cam1_hit_data_r   <= '0;
        end
        else begin
            cam0_hit_vector_r <= cam0_hit_vector;
            cam1_hit_vector_r <= cam1_hit_vector;
            cam0_hit_tag_r    <= cam0_hit_tag_sel;
            cam0_hit_data_r   <= cam0_hit_data_sel;
            cam1_hit_tag_r    <= cam1_hit_tag_sel;
            cam1_hit_data_r   <= cam1_hit_data_sel;
        end
    end

    // 被替换条目指针: 严格 one-hot 左移循环, 每次装填都步进
    tlb_victim_pointer #(
        .TLB_ENTRY_NUMBER   (SDTLB_ENTRIES)
    ) u_tlb_victim_pointer (
        .clk                (clk),
        .rst_n              (rst_n),
        .step               (fill_en),
        .victim_sel         (victim_sel)
    );

    sdtlb_tag u_sdtlb_tag (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .req0_en            (cam0_en            ),
        .req0_pa            (cam0_req_pa        ),
        .req0_hit_vector    (cam0_hit_vector    ),

        .req1_en            (cam1_en            ),
        .req1_pa            (cam1_req_pa        ),
        .req1_hit_vector    (cam1_hit_vector    ),

        .fill_wr_en_vector  (fill_en_vector     ),
        .fill_wr_pa_base    (fill_pa_base       ),
        .fill_wr_pa_up      (fill_pa_up         ),

        .inv_all            (inv_all            ),
        .inv_en             (inv_en             ),
        .inv_pa             (inv_pa             ),

        .tag_item           (tag_item           )
    );

    sdtlb_data u_sdtlb_data (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .fill_en_vector     (fill_en_vector     ),
        .fill_eid           (fill_eid           ),
        .fill_token_id      (fill_token_id      ),
        .fill_s_pfn         (fill_s_pfn         ),

        .data_item          (data_item          )
    );

    // 命中读出: 请求拍用组合命中向量从旧 tag / data 选出快照, 与命中向量在同一沿寄存
    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_TAG_ITEM_WIDTH)
    ) u_onehot0_mux_tag0 (
        .sel    (cam0_hit_vector),
        .din    (tag_item),
        .dout   (cam0_hit_tag_sel)
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_DATA_ITEM_WIDTH)
    ) u_onehot0_mux_data0 (
        .sel    (cam0_hit_vector),
        .din    (data_item),
        .dout   (cam0_hit_data_sel)
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_TAG_ITEM_WIDTH)
    ) u_onehot0_mux_tag1 (
        .sel    (cam1_hit_vector),
        .din    (tag_item),
        .dout   (cam1_hit_tag_sel)
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_DATA_ITEM_WIDTH)
    ) u_onehot0_mux_data1 (
        .sel    (cam1_hit_vector),
        .din    (data_item),
        .dout   (cam1_hit_data_sel)
    );

`ifdef ASSERT_ON
    `assert_clk(a_cam0_hit_vector_onehot0, $onehot0(cam0_hit_vector_r))
    `assert_clk(a_cam1_hit_vector_onehot0, $onehot0(cam1_hit_vector_r))
    // 写选择就是轮转指针, 必须严格 one-hot (空指针会让一次装填悄悄丢掉)
    `assert_clk(a_fill_wr_onehot0, $onehot0(fill_en_vector))

    // 写 Latch 当拍两路查表都必须被反压: Latch 不支持同拍读写
    `assert_clk(a_fill_backpressure,
                (fill_en |-> (!cam0_req_ready && !cam1_req_ready)))

    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间): 查表 / 装填 / 置无效地址的 PA[47] 都必须为 0.
    // 口径: camN_req_pa / inv_pa 是整条 PA[47:0] (bit[PA_WIDTH-1] 就是 PA[47]),
    //       fill_pa_base 是 PA[47:30] (bit[PA_BASE_WIDTH-1] 才是 PA[47])
    `assert_clk(a_cam0_pa47_zero, (cam0_en |-> !cam0_req_pa[PA_WIDTH-1]))
    `assert_clk(a_cam1_pa47_zero, (cam1_en |-> !cam1_req_pa[PA_WIDTH-1]))
    `assert_clk(a_fill_pa47_zero, (fill_en |-> !fill_pa_base[PA_BASE_WIDTH-1]))
    `assert_clk(a_inv_pa47_zero,  (inv_en  |-> !inv_pa[PA_WIDTH-1]))
`endif

endmodule

`default_nettype wire
