`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// cam 端口, fill 端口, inv 端口同拍发生的约束
//   1. 断言 cam 和 fill 不可能同拍发生
//   2. 断言 inv_all 和 inv_sel 不可能同拍发生
//   3. 只有不命中 tlb 的 cam 请求才会去做 Page Walk, 装填的条目不能与已有条目冲突
//      3.1 Testbench 的 scoreboard 里查条目冲突: fill 有效时, 遍历所有当前有效 tlb 的条目,
//          断言 [fill_pa_base, fill_pa_up] 与它们的 [tag_item.pa_base, tag_item.pa_up]都不相交
//   4. 当 cam 和 inv 同拍发生时
//      4.1 因为 inv 下一拍才更新 tag_valid, 所以 camN_hit 结果按旧条目内容值输出
//      4.2 因为 inv 只影响 tag_valid, 不影响 tlb_data 的数值, 所以 inv 不影响 camN_hit 下一拍读 tlb_data
//      4.3 cam 和 inv 可以说是各管个的
//   5. 当 fill 和 inv 同拍发生时
//      5.1 inv_all 时, inv_all 优先, 当拍 fill_en 丢弃
//      5.2 inv_sel 时, 因为 inv_sel 本身相当于 1 次 CAM 查表, 而且装填不会与已有条目冲突, 所以
//          inv_sel 最多只能匹配 1 个条目
//      5.3 inv_sel 和 fill 同拍发生时, 因为 fill 是来自于 Page Walk 的随机时间行为, 所以 inv_sel 和 fill 没有
//          明显的优先级关系, 下面给出了几种解决方案
//          5.3.1 (采用) inv 无条件优先, 不管是什么类型的 inv, 统一丢弃本次 fill 装填, 简化硬件逻辑; 因为 inv 时
//                不关心性能, 不做 fill 的后果不过是后面可能要多一次 Page walk 而已
//          5.3.2 (不采用) fill 无条件优先, 既然不能预测 fill 的时机, 那么就认为 fill 就是什么时候装填都可以接受的,
//                所以认为 fill 总是会发生在 inv_sel 之后也是可以接受的
//          5.3.3 (不采用) 如果 inv_sel 命中 fill, 则 inv_sel 优先 (下一拍该条目是 !tag_valid); 如果 inv_sel没有
//                         命中 fill, 则 fill 优先 (下一拍该条目是 tag_valid)

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

    // 同拍 inv + fill: 置无效优先, 本次装填丢弃.
    // 上层已经把冲突的装填丢掉了 (写阵列拍不会有 inv), 这里保留 inv 优先只是兜底:
    // 万一有冲突的装填漏过来, 宁可丢装填也不要留下一条本该失效的映射.
    // note: inv 分支刻意不带 tag_valid, 否则条目当前无效时清位分支不会被选中
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_valid <= 1'b0;
        end
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

    wire inv_match_for_assert = tag_valid & inv_en & inv_sel & inv_sel_match;
`endif

endmodule

`default_nettype wire
