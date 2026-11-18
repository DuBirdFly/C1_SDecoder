`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 查表端口 0 (CAM0)
    input  logic                        cam0_req_en,
    input  logic [PA_WIDTH-1:0]         cam0_req_pa,
    output logic                        cam0_hit,

    // 查表端口 1 (CAM1)
    input  logic                        cam1_req_en,
    input  logic [PA_WIDTH-1:0]         cam1_req_pa,
    output logic                        cam1_hit,

    // 装填写入
    input  logic                        fill_wr_en,
    input  logic [PA_BASE_WIDTH-1:0]    fill_wr_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      fill_wr_pa_up,

    // 置无效 (刷新) 请求
    input  logic                        inv_all,
    input  logic                        inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]    inv_sel_pa,

    // 本条目内容透传输出
    output SDTLB_TAG_ITEM_t             tag_item
);

    // camN_req_pa 是 PA[47:0] (48 bit)
    // inv_sel_pa 是 PA[47:30] (18 bit)
    // 条目里只存 PA[47:30] (pa_base) 与 段上限 PA[34:30] (pa_up)
    // (pa_up), 所以命中判定要按 "整条 PA 上的位段" 切片, 坐标与设计方案 SDTLB 命中条件一致
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] cam0_high = cam0_req_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               cam0_up   = cam0_req_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] cam1_high = cam1_req_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               cam1_up   = cam1_req_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] inv_high  = inv_sel_pa[PA_BASE_WIDTH-1:PA_UP_WIDTH];
    wire [PA_UP_WIDTH-1:0]               inv_up    = inv_sel_pa[PA_UP_WIDTH-1:0];

    wire cam0_high_hit  = (cam0_high == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire cam0_range_hit = (cam0_up >= tag_item.pa_base[PA_UP_WIDTH-1:0]) && (cam0_up <= tag_item.pa_up);
    wire cam1_high_hit  = (cam1_high == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire cam1_range_hit = (cam1_up >= tag_item.pa_base[PA_UP_WIDTH-1:0]) && (cam1_up <= tag_item.pa_up);
    wire inv_high_hit   = (inv_high == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire inv_range_hit  = (inv_up >= tag_item.pa_base[PA_UP_WIDTH-1:0]) && (inv_up <= tag_item.pa_up);

    // camN_match: 请求地址命中本条目 (不含有效位)
    wire cam0_match = cam0_high_hit && cam0_range_hit;
    wire cam1_match = cam1_high_hit && cam1_range_hit;

    // inv_match: 本条目被无效化地址覆盖 (不含有效位)
    // note: 这里刻意不带 tag_item.valid (为了同拍 ).
    //       "else if" 的优先级只在分支条件成立时才起作用:
    //       若把有效位并进匹配条件, 条目当前无效时 inv_match 就是 0, 清位分支根本不会
    //       被选中, 同拍的装填会照常执行, 把一条覆盖 "正在被刷新的地址" 的映射填进去.
    wire inv_match = inv_sel && inv_high_hit && inv_range_hit;

    // 除 valid 外的字段用 Latch, 只在写周期打开.
    // 使能直接用寄存器出来的 fill_wr_en, 不再串组合门: 使能与写数据同拍变化时,
    // 组合门会晚一个 delta 稳定, Latch 可能在使能还高的时候抓到下一拍的写数据.
    always_latch begin
        if (fill_wr_en) begin
            tag_item.pa_base <= fill_wr_pa_base;
            tag_item.pa_up   <= fill_wr_pa_up;
        end
    end

    // Valid 用 FF: 复位为空, 装填置位, 置无效清位
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_item.valid <= 1'b0;
        end
        else if (inv_all || inv_match) begin
            tag_item.valid <= 1'b0;
        end
        else if (fill_wr_en) begin
            tag_item.valid <= 1'b1;
        end
    end

    assign cam0_hit = cam0_req_en && tag_item.valid && cam0_match;
    assign cam1_hit = cam1_req_en && tag_item.valid && cam1_match;

`ifdef ASSERT_ON
    // fill_wr_pa_base 是 PA[47:30], 所以它的低 5 位就是段下界 PA[34:30]
    `assert_clk(a_fill_pa_range_valid, ((fill_wr_en == 1'b0) || (fill_wr_pa_up >= fill_wr_pa_base[PA_UP_WIDTH-1:0])))
`endif

endmodule

`default_nettype wire
