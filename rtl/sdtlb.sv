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
// 装填时序 (见设计方案 "装填时序"):
//   1. 请求拍 T: tlb_fill_pointer 按当拍 Valid 位图选出目标, 与 fill_en、装填数据一起寄存;
//   2. T+1 拍: 用寄存后的 one-hot 使能写 Latch / 置 Valid, T+2 拍起才能被查表命中.
//   写阵列那一拍不能有 camN_req_en (Latch 不支持同拍读写, 由上游反压, 内部断言兜底);
//   那一拍若有置无效, 置无效优先, 但只丢真正冲突的装填: inv_all 无条件丢弃; inv_sel 只有
//   命中本次装填地址才丢弃 (命中别的地址说明那条旧映射本来就被这次覆盖掉了, 照常写);
//   请求拍 T 的 inv_sel 若覆盖本装填地址, 本次装填同样作废 (否则会把刚清掉的映射写回去).
//
// 接口约定 (由外界保证):
//   1. 装填请求之间至少隔 1 拍: 写数据在请求拍打入后要保持到写阵列那拍结束, 否则在使能
//      落下的那个沿上数据会变, Latch 会把下一笔的数据写进上一条;
//   2. 装填 / 置无效的使能与写数据都由上游用 FF 给出 (见 doc/design_plan/AI 易错点.md);
//   3. 写使能是 "目标 one-hot" 与 "写拍有效" 合成的**一根**网络 (fill_en_vector), 不要拆成
//      fill_en & fill_vector[i] 两根独立网络: 沿后会混出 "新目标 × 旧使能", 写到别的条目上.
//
// 装填目标 (见设计方案 "装填指针"):
//   1. 有空闲条目时, 优先装填最低位的空闲条目;
//   2. 没有空闲条目时, 用轮转 $onehot 指针 (设计方案里的 "伪随机指针" 早期先用轮转代替).
//   空闲集合 = 当拍 Valid | 本拍正在写阵列的目标 (后者下一拍才置 Valid);
//   选目标那一拍发生的置无效要下一拍才对空闲集合可见.

module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

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

    SDTLB_TAG_ITEM_t  tag_item  [SDTLB_ENTRIES];
    SDTLB_DATA_ITEM_t data_item [SDTLB_ENTRIES];

    logic [SDTLB_ENTRIES-1:0] cam0_hit_vector;
    logic [SDTLB_ENTRIES-1:0] cam1_hit_vector;
    logic [SDTLB_ENTRIES-1:0] cam0_hit_vector_r;
    logic [SDTLB_ENTRIES-1:0] cam1_hit_vector_r;
    logic [SDTLB_ENTRIES-1:0] tag_valid_vector;   // 各条目的有效位
    logic                     fill_en_d;          // 上一拍有装填请求 (做间隔断言用)

    // ---- 装填流水 (设计方案 "装填时序"): T 拍选目标 + 打拍, T+1 拍写阵列 ----
    logic [SDTLB_ENTRIES-1:0]   fill_vector;      // T 拍选出的目标 (组合)
    logic [SDTLB_ENTRIES-1:0]   fill_vector_q;    // T+1 拍写阵列的目标
    logic [SDTLB_ENTRIES-1:0]   fill_occupy;      // 选目标用的占用位图
    logic                       fill_en_q;
    logic                       fill_cancel_q;    // 请求拍被判作废
    logic [SDTLB_ENTRIES-1:0]   fill_en_vector;   // 写阵列的 one-hot 使能 (含目标)
    logic [PA_BASE_WIDTH-1:0]   fill_pa_base_q;
    logic [PA_UP_WIDTH-1:0]     fill_pa_up_q;
    logic [EID_WIDTH-1:0]       fill_eid_q;
    logic [TOKEN_ID_WIDTH-1:0]  fill_token_id_q;
    logic [TOKEN_VALUE_WIDTH-1:0] fill_token_value_q;
    logic [S_PFN_WIDTH-1:0]     fill_s_pfn_q;

    // 请求拍选出的命中 tag / data 快照, 与命中向量在同一沿寄存
    SDTLB_TAG_ITEM_t  cam0_hit_tag_sel;
    SDTLB_DATA_ITEM_t cam0_hit_data_sel;
    SDTLB_TAG_ITEM_t  cam1_hit_tag_sel;
    SDTLB_DATA_ITEM_t cam1_hit_data_sel;
    SDTLB_TAG_ITEM_t  cam0_hit_tag_r;
    SDTLB_DATA_ITEM_t cam0_hit_data_r;
    SDTLB_TAG_ITEM_t  cam1_hit_tag_r;
    SDTLB_DATA_ITEM_t cam1_hit_data_r;

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

    // 请求拍的置无效是否覆盖本次装填的地址区间 (只比输入侧寄存器, 不读 Latch)
    logic fill_inv_hit;

    sdtlb_tag_item_match u_fill_inv_match (
        .tag_pa_base (fill_pa_base),
        .tag_pa_up   (fill_pa_up),
        .pa          (inv_sel_pa),
        .match       (fill_inv_hit)
    );

    // 选目标的占用位图: 当前有效位 + 本拍正在写阵列的那个条目 (它下一拍才置 Valid).
    // 用 fill_en_q 门控: fill_vector_q 在没有装填在飞时也残留着上一次的选择, 不能算占用
    assign fill_occupy = tag_valid_vector | (fill_en_q ? fill_vector_q : '0);

    // 装填目标指针: 有空闲条目时指向最低位空闲条目, TLB 满时指向轮转指针
    tlb_fill_pointer #(
        .TLB_ENTRY_NUMBER   (SDTLB_ENTRIES      )
    ) u_tlb_fill_pointer (
        .clk                (clk                ),
        .rst_n              (rst_n              ),
        .fill_en            (fill_en            ),
        .tag_valid_vector   (fill_occupy        ),
        .fill_vector        (fill_vector        )
    );

    // 写阵列拍: 置无效优先, 但只丢真正冲突的装填
    //   inv_all  -> 无条件丢弃 (所有条目都要变无效)
    //   inv_sel  -> 只有命中本次装填地址 (要装的映射正被失效) 才丢弃; 命中别的地址时照常写
    //               (那条旧映射本来就被这次覆盖掉了)
    //   这里用**寄存器**里的装填地址比较, 不读条目的 Latch
    logic fill_wr_inv_hit;

    sdtlb_tag_item_match u_fill_wr_inv_match (
        .tag_pa_base (fill_pa_base_q),
        .tag_pa_up   (fill_pa_up_q),
        .pa          (inv_sel_pa),
        .match       (fill_wr_inv_hit)
    );

    wire fill_drop = inv_en & (inv_all | (inv_sel & fill_wr_inv_hit));

    // 使能和目标必须是**同一根网络**: 写成 "fill_en & fill_vector[i]" 的话两者是两根独立
    // 更新的网络, 沿后会有一瞬间 "新目标 × 旧的使能", 把这次装填的数据写进另一个
    // (可能本来就有效的) 条目 —— 实测会出两条一样的映射, 丢一条装填
    assign fill_en_vector = fill_vector_q & {(SDTLB_ENTRIES){fill_en_q & ~fill_cancel_q & ~fill_drop}};

    wire fill_write_en = |fill_en_vector;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_en_q          <= 1'b0;
            fill_en_d          <= 1'b0;
            fill_vector_q      <= '0;
            fill_cancel_q      <= 1'b0;
            fill_pa_base_q     <= '0;
            fill_pa_up_q       <= '0;
            fill_eid_q         <= '0;
            fill_token_id_q    <= '0;
            fill_token_value_q <= '0;
            fill_s_pfn_q       <= '0;
        end
        else begin
            fill_en_q          <= fill_en;
            fill_en_d          <= fill_en;
            fill_vector_q      <= fill_vector;
            fill_cancel_q      <= inv_en & (inv_all | (inv_sel & fill_inv_hit));
            // 数据只在请求拍更新: 写阵列那一拍不能让写数据变化, 否则 Latch 会在使能
            // 还没落下的时候把新数据写进上一条
            if (fill_en) begin
                fill_pa_base_q     <= fill_pa_base;
                fill_pa_up_q       <= fill_pa_up;
                fill_eid_q         <= fill_eid;
                fill_token_id_q    <= fill_token_id;
                fill_token_value_q <= fill_token_value;
                fill_s_pfn_q       <= fill_s_pfn;
            end
        end
    end

    sdtlb_tag u_sdtlb_tag (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .cam0_req_en        (cam0_req_en        ),
        .cam0_req_pa        (cam0_req_pa        ),
        .cam0_hit_vector    (cam0_hit_vector    ),

        .cam1_req_en        (cam1_req_en        ),
        .cam1_req_pa        (cam1_req_pa        ),
        .cam1_hit_vector    (cam1_hit_vector    ),

        .fill_en_vector     (fill_en_vector     ),
        .fill_pa_base       (fill_pa_base_q     ),
        .fill_pa_up         (fill_pa_up_q       ),

        .inv_en             (inv_en             ),
        .inv_all            (inv_all            ),
        .inv_sel            (inv_sel            ),
        .inv_sel_pa         (inv_sel_pa         ),

        .tag_item           (tag_item           ),
        .tag_valid_vector   (tag_valid_vector   )
    );

    sdtlb_data u_sdtlb_data (
        .fill_en_vector     (fill_en_vector     ),
        .fill_eid           (fill_eid_q         ),
        .fill_token_id      (fill_token_id_q    ),
        .fill_token_value   (fill_token_value_q ),
        .fill_s_pfn         (fill_s_pfn_q       ),

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
    // 装填目标必须严格 one-hot (否则这次装填会漏填 / 多填条目)
    `assert_clk(a_fill_onehot0, (fill_en |-> $onehot(fill_vector)))

    // 写阵列拍的目标同样必须严格 one-hot
    `assert_clk(a_fill_write_onehot0, (fill_write_en |-> $onehot(fill_vector_q)))

    // 写阵列拍的两个丢弃条件: inv_all 的拍不写; inv_sel 命中本装填地址的拍也不写
    `assert_clk(a_fill_wr_no_inv_all, (fill_write_en |-> !(inv_en && inv_all)))
    `assert_clk(a_fill_wr_no_inv_hit, (fill_write_en |-> !(inv_en && inv_sel && fill_wr_inv_hit)))

    // 装填请求之间至少隔 1 拍: 写阵列拍不能同时又是请求拍, 否则写数据会在写使能落下
    // 的那个沿上变化, Latch 会把新数据写进上一条 (设计方案 "装填时序")
    `assert_clk(a_fill_req_gap, (fill_en |-> !fill_en_d))

    // 外界约定: 写阵列那一拍不能查表 (Latch 不支持同拍读写)
    `assert_clk(a_cam0_req_fill_exclusive, (!(cam0_req_en && fill_write_en)))
    `assert_clk(a_cam1_req_fill_exclusive, (!(cam1_req_en && fill_write_en)))

    // 两条有效条目覆盖同一个 PA 时响应数据未定义 (设计方案要求上报 tlb_multi_hit, 暂未实现)
    // 这里先把它当错误抓出来; 实现多命中上报后应改成告警口径
    `assert_clk(a_cam0_hit_vector_onehot0, $onehot0(cam0_hit_vector_r))
    `assert_clk(a_cam1_hit_vector_onehot0, $onehot0(cam1_hit_vector_r))

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
