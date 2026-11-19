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
    input  logic                        fill_en,
    input  logic [PA_BASE_WIDTH-1:0]    fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      fill_pa_up,

    // 置无效 (刷新) 请求
    input  logic                        inv_en,
    input  logic                        inv_all,
    input  logic                        inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]    inv_sel_pa,

    // 本条目内容透传输出
    output SDTLB_TAG_ITEM_t             tag_item,
    output logic                        tag_valid
);

    wire cam0_req_match;
    wire cam1_req_match;
    wire inv_sel_match;

    sdtlb_tag_item_match u_cam0_match (
        .tag_pa_base (tag_item.pa_base),
        .tag_pa_up   (tag_item.pa_up),
        .pa          (cam0_req_pa[PA_WIDTH-1:PA_BASE_LSB]),
        .match       (cam0_req_match)
    );

    sdtlb_tag_item_match u_cam1_match (
        .tag_pa_base (tag_item.pa_base),
        .tag_pa_up   (tag_item.pa_up),
        .pa          (cam1_req_pa[PA_WIDTH-1:PA_BASE_LSB]),
        .match       (cam1_req_match)
    );

    sdtlb_tag_item_match u_inv_match (
        .tag_pa_base (tag_item.pa_base),
        .tag_pa_up   (tag_item.pa_up),
        .pa          (inv_sel_pa),
        .match       (inv_sel_match)
    );

    // 同拍同时发生 `inv` 和 `fill` 时, 优先实现 `inv`, 且本次 `fill` 被**丢弃**
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_valid <= 1'b0;
        end
        // 刻意不带 tag_valid: 当发生 `inv` 和 `fill` 同拍有效, 且该条目是 !tag_valid 的空闲条目时,
        // 如果 tag_valid 放入置无效的 if 匹配条件, 则这条 inv 分支必然被跳过, 同拍的装填会照常执行,
        // 把一条覆盖 "正在被刷新的地址" 的映射填进去.
        else if (inv_en & (inv_all | (inv_sel & inv_sel_match))) begin
            tag_valid <= 1'b0;
        end
        else if (fill_en) begin
            tag_valid <= 1'b1;
        end
    end

    always_latch begin
        if (fill_en) begin
            tag_item.pa_base <= fill_pa_base;
            tag_item.pa_up   <= fill_pa_up;
        end
    end

    assign cam0_hit = cam0_req_en && tag_valid && cam0_req_match;
    assign cam1_hit = cam1_req_en && tag_valid && cam1_req_match;

`ifdef ASSERT_ON
    // fill_pa_base 是 PA[47:30], 所以它的低 5 位就是段下界 PA[34:30]
    `assert_clk(a_fill_pa_range_valid, ((fill_en == 1'b0) || (fill_pa_up >= fill_pa_base[PA_UP_WIDTH-1:0])))
`endif

endmodule

`default_nettype wire
