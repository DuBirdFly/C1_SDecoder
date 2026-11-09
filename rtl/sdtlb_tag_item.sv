`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDTLB 单个条目的 Tag 段
// 存储: Valid 用 FF (可复位), PA_Base / PA_Up 用 Latch.
// 两个查表端口 (CAM0 / CAM1) 各自与本条目比较, 各自给出命中.
//
// 装填与置无效都晚 1 拍写入 (写数据与写使能都由 sdtlb 寄存后再进来):
// Latch 的使能必须来自寄存器, 否则 fill_en / inv_* 与写数据同拍变化时, 使能会
// 短暂指向上一次的目标条目, 把新数据写进别的条目.
//
// Latch 在写周期内对输入透明, 因此写周期不可被查表读; 顶层的 camN_req_ready
// 在写周期拉低, 由它保证这一点, 本模块不再重复判断.
module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 查表端口 0 (CAM0)
    input  logic                        req0_en,
    input  logic [PA_WIDTH-1:0]         req0_pa,
    output logic                        req0_hit,

    // 查表端口 1 (CAM1)
    input  logic                        req1_en,
    input  logic [PA_WIDTH-1:0]         req1_pa,
    output logic                        req1_hit,

    // 装填写入: 下一拍生效, 数据与使能都已寄存
    input  logic                        fill_wr_en,
    input  logic [PA_BASE_WIDTH-1:0]    fill_wr_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      fill_wr_pa_up,

    // 置无效 (刷新) 请求: 立即生效, 清本条目 Valid
    input  logic                        inv_all,
    input  logic                        inv_en,
    input  logic [PA_WIDTH-1:0]         inv_pa,

    // 本条目内容静默输出 (valid 来自 FF, 其余字段来自 Latch)
    output SDTLB_TAG_ITEM_t             tag_item
);

    // req_pa / inv_pa 收的是整条 PA[47:0], 而条目里只存 PA[47:30] (pa_base) 与段上限 PA[34:30]
    // (pa_up), 所以命中判定要按 "整条 PA 上的位段" 切片, 坐标与设计方案 SDTLB 命中条件一致
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] req0_high = req0_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               req0_up   = req0_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] req1_high = req1_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               req1_up   = req1_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] inv_high  = inv_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               inv_up    = inv_pa[PA_BASE_LSB +: PA_UP_WIDTH];

    // 存储体: pa_base / pa_up 是 Latch, valid 是 FF
    logic [PA_BASE_WIDTH-1:0] pa_base_q;
    logic [PA_UP_WIDTH-1:0]   pa_up_q;
    logic                     valid_q;

    wire req0_high_hit  = (req0_high == pa_base_q[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire req0_range_hit = (req0_up >= pa_base_q[PA_UP_WIDTH-1:0]) && (req0_up <= pa_up_q);
    wire req1_high_hit  = (req1_high == pa_base_q[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire req1_range_hit = (req1_up >= pa_base_q[PA_UP_WIDTH-1:0]) && (req1_up <= pa_up_q);
    wire inv_high_hit   = (inv_high == pa_base_q[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire inv_range_hit  = (inv_up >= pa_base_q[PA_UP_WIDTH-1:0]) && (inv_up <= pa_up_q);

    // req_match: 请求地址命中本条目 (不含有效位)
    wire req0_match = req0_high_hit && req0_range_hit;
    wire req1_match = req1_high_hit && req1_range_hit;

    // inv_match: 本条目被无效化地址覆盖 (不含有效位)
    // note: 这里刻意不带 valid_q. else if 的优先级只在分支条件成立时才起作用:
    //       若把有效位并进匹配条件, 条目当前无效时 inv_match 就是 0, 清位分支根本不会
    //       被选中, 同拍的装填会照常执行, 把一条覆盖 "正在被刷新的地址" 的映射填进去.
    wire inv_match = inv_en && inv_high_hit && inv_range_hit;

    // 除 valid 外的字段用 Latch, 只在写周期打开.
    // 使能直接用寄存器出来的 fill_wr_en, 不再串组合门: 使能与写数据同拍变化时,
    // 组合门会晚一个 delta 稳定, Latch 可能在使能还高的时候抓到下一拍的写数据.
    always_latch begin
        if (fill_wr_en) begin
            pa_base_q <= fill_wr_pa_base;
            pa_up_q   <= fill_wr_pa_up;
        end
    end

    // Valid 用 FF: 复位为空, 装填置位, 置无效清位
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= 1'b0;
        end
        else if (inv_all || inv_match) begin
            valid_q <= 1'b0;
        end
        else if (fill_wr_en) begin
            valid_q <= 1'b1;
        end
    end

    assign tag_item = '{pa_base: pa_base_q, pa_up: pa_up_q, valid: valid_q};

    assign req0_hit = req0_en && valid_q && req0_match;
    assign req1_hit = req1_en && valid_q && req1_match;

`ifdef ASSERT_ON
    // fill_wr_pa_base 是 PA[47:30], 所以它的低 5 位就是段下界 PA[34:30]
    `assert_clk(a_fill_pa_range_valid,
                ((fill_wr_en == 1'b0) || (fill_wr_pa_up >= fill_wr_pa_base[PA_UP_WIDTH-1:0])))
`endif

endmodule

`default_nettype wire
