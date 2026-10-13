`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 代换请求
    input  logic                        req_vld,
    input  logic [PA_BASE_WIDTH-1:0]    req_pa,
    output logic                        req_hit,

    // 装填请求
    input  logic [PA_BASE_WIDTH-1:0]    fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      fill_pa_up,
    input  logic                        fill_vld,

    // 置无效 (刷新) 请求, 置无效全部 TLB ENTRIES
    input  logic                        inv_all,

    // 置无效 (刷新) 请求, 置无效指定 pa 范围覆盖的条目
    input  logic                        inv_en,
    input  logic [PA_BASE_WIDTH-1:0]    inv_pa,

    // 本条目内容静默输出
    output SDTLB_TAG_ITEM_t             tag_item
);

    wire req_high_hit  = (req_pa[PA_BASE_WIDTH-1:PA_UP_WIDTH] == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire req_range_hit = (req_pa[PA_UP_WIDTH-1:0] >= tag_item.pa_base[PA_UP_WIDTH-1:0]) &&
                         (req_pa[PA_UP_WIDTH-1:0] <= tag_item.pa_up);

    wire inv_high_hit  = (inv_pa[PA_BASE_WIDTH-1:PA_UP_WIDTH] == tag_item.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]);
    wire inv_range_hit = (inv_pa[PA_UP_WIDTH-1:0] >= tag_item.pa_base[PA_UP_WIDTH-1:0]) &&
                         (inv_pa[PA_UP_WIDTH-1:0] <= tag_item.pa_up);

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
        else if (fill_vld) begin
            tag_item <= '{pa_base: fill_pa_base, pa_up: fill_pa_up, valid: fill_vld};
        end
    end

    assign req_hit = req_vld && tag_item.valid && req_match;

`ifdef ASSERT_ON
    `assert_clk(a_fill_pa_range_valid, (fill_vld == 1'b0) || (fill_pa_up >= fill_pa_base[4:0]))
`endif

endmodule

`default_nettype wire
