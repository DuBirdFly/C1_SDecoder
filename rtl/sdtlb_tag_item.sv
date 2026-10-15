`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 代换请求
    input  logic                        req_valid,
    input  logic [PA_WIDTH-1:0]         req_pa,
    output logic                        req_hit,

    // 装填请求
    input  logic [PA_BASE_WIDTH-1:0]    fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      fill_pa_up,
    input  logic                        fill_valid,

    // 置无效 (刷新) 请求, 置无效全部 TLB ENTRIES
    input  logic                        inv_all,

    // 置无效 (刷新) 请求, 置无效指定 pa 范围覆盖的条目
    input  logic                        inv_en,
    input  logic [PA_WIDTH-1:0]         inv_pa,

    // 本条目内容静默输出
    output SDTLB_TAG_ITEM_t             tag_item
);

    // req_pa / inv_pa 收的是整条 PA[47:0], 而条目里只存 PA[47:30] (pa_base) 与段上限 PA[34:30]
    // (pa_up), 所以命中判定要按"整条 PA 上的位段"切片, 坐标与设计方案 表5 的命中条件一致;
    // fill_pa_base 收的就是 PA[47:30] (来自只算页号的 sdptw), 可以直接存 / 直接比低位
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] req_high = req_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               req_up   = req_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] inv_high = inv_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               inv_up   = inv_pa[PA_BASE_LSB +: PA_UP_WIDTH];

    wire req_high_hit  = (req_high == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire req_range_hit = (req_up >= tag_item.pa_base[PA_UP_WIDTH-1:0]) && (req_up <= tag_item.pa_up);

    wire inv_high_hit  = (inv_high == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire inv_range_hit = (inv_up >= tag_item.pa_base[PA_UP_WIDTH-1:0]) && (inv_up <= tag_item.pa_up);

    // req_match: 请求地址命中本条目 (不含有效位)
    wire req_match = req_high_hit && req_range_hit;

    // inv_match: 本条目被无效化地址覆盖 (不含有效位)
    // note: 这里刻意不带 tag_item.valid. else if 的优先级只在分支条件成立时才起作用:
    //       若把有效位并进匹配条件, 条目当前无效时 inv_match 就是 0, 清位分支根本不会
    //       被选中, 同拍的装填会照常执行, 把一条覆盖"正在被刷新的地址"的映射填进去
    //       (无效条目本就无需清位, 谈不上"写回"). 去掉有效位不影响"清哪些条目".
    wire inv_match = inv_en && inv_high_hit && inv_range_hit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_item <= '0;
        end
        else if (inv_all || inv_match) begin
            tag_item.valid <= 1'b0;
        end
        else if (fill_valid) begin
            tag_item <= '{pa_base: fill_pa_base, pa_up: fill_pa_up, valid: fill_valid};
        end
    end

    assign req_hit = req_valid && tag_item.valid && req_match;

`ifdef ASSERT_ON
    // fill_pa_base 是 PA[47:30], 所以它的低 5 位就是段下界 PA[34:30]
    `assert_clk(a_fill_pa_range_valid,
                ((fill_valid == 1'b0) || (fill_pa_up >= fill_pa_base[PA_UP_WIDTH-1:0])))
`endif

endmodule

`default_nettype wire
