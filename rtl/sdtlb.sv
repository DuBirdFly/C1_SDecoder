`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// 命中读出的 tag/data 与命中向量一起在请求拍打拍:
//   请求拍 T 用 fill 之前的旧 tag 做命中判定; 同一拍用 tag_hit_vector 从旧的
//   tag_item / data_item 选出命中内容, 并在时钟沿寄存.
//   下一拍 req_hit / req_hit_tag_item / req_hit_data_item 都来自 T 拍快照.
//   因此 req_en 和 fill_en (或 inv_en) 同拍有效时, 表项更新只影响后续请求,
//   不会出现 "旧命中 + 新 tag/data" 的不一致.

module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 查表. 地址是整条 PA[47:0] (条目里只存 PA[47:30], 见 sdtlb_tag_item)
    // req_en 被采到的那一拍是请求拍, 响应 (req_hit 与读出数据) 下一拍才有效
    input  logic                                req_en,
    input  logic [PA_WIDTH-1:0]                 req_pa,
    output logic                                req_hit,
    output SDTLB_TAG_ITEM_t                     req_hit_tag_item,
    output SDTLB_DATA_ITEM_t                    req_hit_data_item,

    // 装填: SDPTW 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目.
    // 注意这里与 req_pa / inv_pa 口径不同: 装填来自 sdptw, 它本来就算在 PA[47:30] 上,
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

    // 命中向量由 sdtlb_tag 组合给出 (比较链长, 时序差), 这里打 1 拍后再用:
    // req_en / req_pa 被采到的那一拍 (记作 T) 只是请求拍, 响应 (req_hit 与读出数据)
    // 在 T+1 拍才有效; req_en 可以拍拍有效, 响应逐拍滞后 1 拍 (流水线)
    logic [SDTLB_ENTRIES-1:0] tag_hit_vector;
    logic [SDTLB_ENTRIES-1:0] tag_hit_vector_r1;
    logic [SDTLB_ENTRIES-1:0] fill_sel;
    logic [SDTLB_ENTRIES-1:0] fill_hit_vector;
    logic [SDTLB_ENTRIES-1:0] fill_en_vector;
    logic [SDTLB_ENTRIES-1:0] victim_sel;

    // 请求拍 T 选出的命中 tag/data 快照, 和 tag_hit_vector_r1 同一沿寄存
    SDTLB_TAG_ITEM_t  hit_tag_sel;
    SDTLB_DATA_ITEM_t hit_data_sel;
    SDTLB_TAG_ITEM_t  req_hit_tag_item_r;
    SDTLB_DATA_ITEM_t req_hit_data_item_r;

    assign req_hit = |tag_hit_vector_r1;
    assign fill_en_vector = fill_en ? fill_sel : 0;

    // fill 去重: 每个 tag item 比较本次 fill tag, fill_hit_vector 由 sdtlb_tag 给出.
    // 同一个 tag 已经存在时, 更新原条目, 不再分配新条目.
    assign fill_sel = (|fill_hit_vector) ? fill_hit_vector : victim_sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_hit_vector_r1   <= '0;
            req_hit_tag_item_r  <= '0;
            req_hit_data_item_r <= '0;
        end
        else begin
            tag_hit_vector_r1   <= tag_hit_vector;
            req_hit_tag_item_r  <= hit_tag_sel;
            req_hit_data_item_r <= hit_data_sel;
        end
    end

    // 被替换条目指针: 严格 one-hot 左移循环, 只有真正分配新条目时才步进
    tlb_victim_pointer #(
        .TLB_ENTRY_NUMBER   (SDTLB_ENTRIES)
    ) u_tlb_victim_pointer (
        .clk                (clk),
        .rst_n              (rst_n),
        .step               (fill_en && !(|fill_hit_vector)),
        .victim_sel         (victim_sel)
    );

    sdtlb_tag u_sdtlb_tag(
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .req_en             (req_en             ),
        .req_pa             (req_pa             ),
        .req_hit_vector     (tag_hit_vector     ),

        .fill_pa_base       (fill_pa_base       ),
        .fill_pa_up         (fill_pa_up         ),
        .fill_en_vector     (fill_en_vector     ),
        .fill_hit_vector    (fill_hit_vector    ),

        .inv_all            (inv_all            ),
        .inv_en             (inv_en             ),
        .inv_pa             (inv_pa             ),

        .tag_item           (tag_item           )
    );

    sdtlb_data u_sdtlb_data(
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .fill_en_vector     (fill_en_vector     ),
        .fill_eid           (fill_eid           ),
        .fill_token_id      (fill_token_id      ),
        .fill_s_pfn         (fill_s_pfn         ),

        .data_item          (data_item          )
    );

    // 命中读出: 请求拍 T 用组合 hit vector 从旧 tag/data 选出快照,
    // 和 tag_hit_vector_r1 在同一沿寄存; 同拍 fill/inv 不会改到本次响应.
    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_TAG_ITEM_WIDTH)
    ) u_onehot0_mux_tag (
        .sel    (tag_hit_vector),
        .din    (tag_item),
        .dout   (hit_tag_sel)
    );

    onehot0_mux #(
        .N      (SDTLB_ENTRIES),
        .WIDTH  (SDTLB_DATA_ITEM_WIDTH)
    ) u_onehot0_mux_data (
        .sel    (tag_hit_vector),
        .din    (data_item),
        .dout   (hit_data_sel)
    );

    assign req_hit_tag_item  = req_hit_tag_item_r;
    assign req_hit_data_item = req_hit_data_item_r;

`ifdef ASSERT_ON
    `assert_clk(a_tag_hit_vector_onehot0, $onehot0(tag_hit_vector_r1))
    // fill_hit_vector 是"已有相同 tag"的选择结果, 正常情况下最多一个
    `assert_clk(a_fill_hit_onehot0, $onehot0(fill_hit_vector))
    // fill_sel 是写使能, 必须严格 one-hot (空指针会让一次装填悄悄丢掉)
    `assert_clk(a_fill_sel_onehot, $onehot(fill_sel))

    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间): 查表 / 装填 / 置无效地址的 PA[47] 都必须为 0.
    // 口径: req_pa / inv_pa 是整条 PA[47:0] (bit[PA_WIDTH-1] 就是 PA[47]),
    //       fill_pa_base 是 PA[47:30] (bit[PA_BASE_WIDTH-1] 才是 PA[47])
    `assert_clk(a_req_pa47_zero,  (req_en  |-> !req_pa[PA_WIDTH-1]))
    `assert_clk(a_fill_pa47_zero, (fill_en |-> !fill_pa_base[PA_BASE_WIDTH-1]))
    `assert_clk(a_inv_pa47_zero,  (inv_en   |-> !inv_pa[PA_WIDTH-1]))
`endif

endmodule

`default_nettype wire
