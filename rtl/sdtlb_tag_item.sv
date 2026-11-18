`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                                   clk,
    input  logic                                   rst_n,

    // 查表端口: 下标就是 CAM 号
    input  logic                                    cam_req_en [SDTLB_CAM_NUM],
    input  logic [PA_WIDTH-1:0]                     cam_req_pa [SDTLB_CAM_NUM],
    output logic                                    cam_hit    [SDTLB_CAM_NUM],

    // 装填写入
    input  logic                                   fill_wr_en,
    input  logic [PA_BASE_WIDTH-1:0]               fill_wr_pa_base,
    input  logic [PA_UP_WIDTH-1:0]                 fill_wr_pa_up,

    // 置无效 (刷新) 请求
    input  logic                                   inv_all,
    input  logic                                   inv_sel,
    input  logic [PA_BASE_WIDTH-1:0]               inv_sel_pa,

    // 本条目内容透传输出
    output SDTLB_TAG_ITEM_t                        tag_item
);

    // 每个 CAM 端口一份比较器: 条目只存 PA[47:30], 所以先把整条 PA 切到那个窗口
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_CAM_NUM; genvar_i++) begin : gen_cam
            wire match;

            sdtlb_tag_item_match u_match (
                .tag_pa_base (tag_item.pa_base),
                .tag_pa_up   (tag_item.pa_up),
                .pa          (cam_req_pa[genvar_i][PA_WIDTH-1:PA_BASE_LSB]),
                .match       (match)
            );

            // 命中 = 本拍该端口有请求 && 条目有效 && 地址落在段里
            assign cam_hit[genvar_i] = cam_req_en[genvar_i] && tag_item.valid && match;
        end
    endgenerate

    // 无效化地址本来就对齐 PA[47:30], 直接比较; 再与 inv_sel 相与得到 inv_match
    wire inv_sel_match;

    sdtlb_tag_item_match u_inv_match (
        .tag_pa_base (tag_item.pa_base),
        .tag_pa_up   (tag_item.pa_up),
        .pa          (inv_sel_pa),
        .match       (inv_sel_match)
    );

    // inv_match: 本条目被无效化地址覆盖 (不含有效位)
    // note: 这里刻意不带 tag_item.valid (为了同拍 ).
    //       "else if" 的优先级只在分支条件成立时才起作用:
    //       若把有效位并进匹配条件, 条目当前无效时清位分支根本不会被选中,
    //       同拍的装填会照常执行, 把一条覆盖 "正在被刷新的地址" 的映射填进去.
    wire inv_match = inv_sel && inv_sel_match;

    // 除 valid 外的字段用 Latch, 只在写周期打开.
    // 使能直接用寄存器出来的 fill_wr_en, 不再串组合门: 使能与写数据同拍变化时,
    // 组合门会晚一个 delta 稳定, Latch 可能在使能还高的时候抓到下一拍的写数据.
    always_latch begin
        if (fill_wr_en) begin
            tag_item.pa_base <= fill_wr_pa_base;
            tag_item.pa_up   <= fill_wr_pa_up;
        end
    end

    // 同拍同时发生 `inv` 和 `fill` 时, 优先实现 `inv`, 且本次 `fill` 被**丢弃**
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

`ifdef ASSERT_ON
    // fill_wr_pa_base 是 PA[47:30], 所以它的低 5 位就是段下界 PA[34:30]
    `assert_clk(a_fill_pa_range_valid, ((fill_wr_en == 1'b0) || (fill_wr_pa_up >= fill_wr_pa_base[PA_UP_WIDTH-1:0])))
`endif

endmodule

`default_nettype wire
