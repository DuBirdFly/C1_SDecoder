`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB: 全相联 (CAM + FF + Latch), 2 个查表端口 (CAM0 / CAM1)
//
// 查表时序 (没有 valid/ready 握手, 只有一个 1 拍使能 camN_req_en):
//   请求拍 T 的 camN_req_en 为 1, 用当拍条目的内容做组合比较;
//   命中向量与选出的 tag / data 快照在 T 的上升沿打 1 拍, T+1 拍由
//   camN_hit / camN_hit_tag_item / camN_hit_data_item 给出.
//   camN_hit 同时充当响应的 valid: 使能为 0 的拍按 0 打拍, 所以请求撤掉后
//   下一拍命中自然归 0, 不会漏出上一拍的陈旧结果.
//
// 接口约定 (由外界保证, SDTLB 内部不再做握手 / 反压):
//   1. camN_req_en 与 fill_en 不会同拍为高.
//      条目除 Valid (FF) 外都用 Latch, Latch 不支持同拍读写, 所以"写 Latch 的那一拍
//      不能查表"由上游保证: 上游在发出 fill_en 的同一拍不许再发 camN_req_en.
//      这里用断言 a_camN_req_fill_exclusive 兜底, 违反时仿真报错.
//   2. 装填 / 置无效的使能与写数据都由上游用 FF 给出 (见 doc/design_plan/AI 易错点.md).
//      本模块内部送给 Latch 的写使能也只是 FF 的组合 (victim_sel 与 fill_en 相与),
//      不再为了仿真竞争额外加打拍寄存器: 时序节拍属于设计, 仿真竞争由 tb 的 wrapper 打拍解决.
//
// 装填 / 置无效时序:
//   装填与置无效都在请求拍当拍作用到阵列 (Latch 写入 / Valid 清位), 不额外打拍.
//
// 装填目标 (暂定):
//   全部按轮转替换指针 victim_sel 装填, 每次装填指针步进一格; 不区分空闲 / 有效条目.
//   设计方案 "装填条目 (SDTLB)" 要求 "有空闲条目时优先装填最低位空闲条目", 这一条先不实现,
//   等替换策略定稿后再补 (届时会把 victim_sel 换成 "空闲指针 / 轮转指针" 二选一).
module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 查表端口 0 (CAM0). 地址是整条 PA[47:0] (条目里只存 PA[47:30], 见 sdtlb_tag_item)
    // req_en 是 1 拍使能, 与 fill_en 不同拍 (外界保证)
    input  logic                                cam0_req_en,
    input  logic [PA_WIDTH-1:0]                 cam0_req_pa,
    output logic                                cam0_hit,
    output SDTLB_TAG_ITEM_t                     cam0_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    cam0_hit_data_item,

    // 查表端口 1 (CAM1)
    input  logic                                cam1_req_en,
    input  logic [PA_WIDTH-1:0]                 cam1_req_pa,
    output logic                                cam1_hit,
    output SDTLB_TAG_ITEM_t                     cam1_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    cam1_hit_data_item,

    // 装填: sdptw 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目, 请求拍有效.
    // 注意这里与 camN_req_pa 口径不同: 装填来自 sdptw, 它本来就算在 PA[47:30] 上,
    // 所以 fill_pa_base 就保持 PA[47:30] (18 位), 不必先补齐到整条 PA 再切回来
    input  logic                                fill_en,
    input  logic [PA_BASE_WIDTH-1:0]            fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]              fill_pa_up,
    input  logic [EID_WIDTH-1:0]                fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]           fill_token_id,
    input  logic [TOKEN_VALUE_WIDTH-1:0]        fill_token_value,
    input  logic [S_PFN_WIDTH-1:0]              fill_s_pfn,

    // 置无效 (刷新): 只作用于 Tag 侧的有效位; 地址是 PA[47:30]
    // inv_en 是软件刷新的总使能, inv_all / inv_sel 只在它有效的当拍起作用, 且两者不同时为 1
    input  logic                                inv_en,
    input  logic                                inv_all,
    input  logic                                inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]            inv_sel_pa
);

    // 软件置无效: 只有 inv_en 的当拍才真正生效
    wire inv_all_q = inv_all & inv_en;
    wire inv_sel_q = inv_sel & inv_en;

    SDTLB_TAG_ITEM_t  tag_item  [SDTLB_ENTRIES];
    SDTLB_DATA_ITEM_t data_item [SDTLB_ENTRIES];

    // 写 Latch 的使能 (victim_sel 与 fill_en 都是 FF, 见文件头的约定)
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

    // 装填目标 = 轮转替换指针 (暂不做 "空闲优先", 见文件头)
    assign fill_en_vector = fill_en ? victim_sel : '0;

    // 注: 设计方案要求多命中时上报 tlb_multi_hit (响应 err 位 + 异常寄存器), 暂不实现;
    //     多命中时命中数据未定义, 行为与原来一致.

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

        .cam0_req_en        (cam0_req_en        ),
        .cam0_req_pa        (cam0_req_pa        ),
        .cam0_hit_vector    (cam0_hit_vector    ),

        .cam1_req_en        (cam1_req_en        ),
        .cam1_req_pa        (cam1_req_pa        ),
        .cam1_hit_vector    (cam1_hit_vector    ),

        .fill_wr_en_vector  (fill_en_vector     ),
        .fill_wr_pa_base    (fill_pa_base       ),
        .fill_wr_pa_up      (fill_pa_up         ),

        .inv_all            (inv_all_q          ),
        .inv_sel            (inv_sel_q          ),
        .inv_sel_pa         (inv_sel_pa         ),

        .tag_item           (tag_item           )
    );

    sdtlb_data u_sdtlb_data (
        .fill_en_vector     (fill_en_vector     ),
        .fill_eid           (fill_eid           ),
        .fill_token_id      (fill_token_id      ),
        .fill_token_value   (fill_token_value   ),
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
    // 写 Latch 的使能必须严格 one-hot (空指针会让一次装填悄悄丢掉)
    `assert_clk(a_fill_wr_onehot0, (fill_en |-> $onehot(fill_en_vector)))

    // 外界约定: 装填与查表不同拍 (Latch 不支持同拍读写)
    `assert_clk(a_cam0_req_fill_exclusive, (!(cam0_req_en && fill_en)))
    `assert_clk(a_cam1_req_fill_exclusive, (!(cam1_req_en && fill_en)))

    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间): 查表 / 装填 / 置无效地址的 PA[47] 都必须为 0.
    // 口径: camN_req_pa 是整条 PA[47:0] (bit[PA_WIDTH-1] 就是 PA[47]),
    //       fill_pa_base 是 PA[47:30] (bit[PA_BASE_WIDTH-1] 才是 PA[47])
    `assert_clk(a_cam0_pa47_zero, (cam0_req_en |-> !cam0_req_pa[PA_WIDTH-1]))
    `assert_clk(a_cam1_pa47_zero, (cam1_req_en |-> !cam1_req_pa[PA_WIDTH-1]))
    `assert_clk(a_fill_pa47_zero, (fill_en |-> !fill_pa_base[PA_BASE_WIDTH-1]))
    `assert_clk(a_inv_sel_pa47_zero,  ((inv_en && inv_sel) |-> !inv_sel_pa[PA_BASE_WIDTH-1]))

    // 同一次软件刷新只允许一种方式: inv_en 当拍 inv_all 与 inv_sel 不能同时为 1
    `assert_clk(a_inv_exclusive, (inv_en |-> !(inv_all && inv_sel)))
`endif

endmodule

`default_nettype wire
