`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// SDecoder Miss Queue (SDMQ) 条目, 用于缓存 TLB miss 请求, 以便后续装填.

module sdmq_item
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 命中查询请求 (Page Walk 完成后, 查看合法的 PTE 能不能覆盖本条目)
    // 这组接口的 input 值只在 Page Walk 返回合法 PTE 时才进行修改
    // chk_hit 只有在这个条目 valid 时才有意义 (无效条目固定为 0)
    input  logic [PA_BASE_WIDTH-1:0]    chk_hit_pa_base,
    input  logic [PA_UP_WIDTH-1:0]      chk_hit_pa_up,
    output logic                        chk_hit,

    // 装填请求 (TLB miss 后, 把本次地址代换请求装入 sdmq 缓冲)
    input  logic                        fill_en,
    input  logic [REQ_ID_WIDTH-1:0]     fill_id,
    input  logic [PA_WIDTH-1:0]         fill_pa,

    // 删除请求 (Page Walk 完成后, 弹出可被删除的 sdmq 条目, 一次弹出 1 个)
    input  logic                        del_en,

    // 置无效 (刷新) 请求, 置无效全部 sdmq 条目
    input  logic                        inv_all,

    // 置无效 (刷新) 请求, 置无效指定 pa 范围覆盖的条目
    // 对于 SDMQ 来说, 即 inv_pa 和 item.pa 的 PA[47:30] 相等
    input  logic                        inv_en,
    input  logic [PA_WIDTH-1:0]         inv_pa,

    // 条目内容静默输出
    output SDMQ_ITEM_t                  sdmq_item

);

    // 控制信号: 带复位
    logic                    item_valid;
    logic                    item_flushed;

    // 数据信号: 无复位, 只在装填时更新
    logic [PA_WIDTH-1:0]     item_pa;
    logic [REQ_ID_WIDTH-1:0] item_id;

    // 置无效判定: 条目里只有单个未命中请求, 按 PA[47:30] 相等即可
    wire [PA_BASE_WIDTH-1:0] inv_base  = inv_pa[PA_BASE_LSB +: PA_BASE_WIDTH];
    wire [PA_BASE_WIDTH-1:0] item_base = item_pa[PA_BASE_LSB +: PA_BASE_WIDTH];
    wire inv_match = inv_en && (item_base == inv_base);

    // 命中查询: 与 SDTLB 的范围命中同口径,
    //   chk_hit_pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH] 是 32GB 段号 (PA[47:35]),
    //   chk_hit_pa_base[PA_UP_WIDTH-1:0] ~ chk_hit_pa_up 是段内覆盖的 1GB 页范围 (PA[34:30])
    wire [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] item_high = item_pa[PA_HIGH_LSB +: (PA_BASE_WIDTH-PA_UP_WIDTH)];
    wire [PA_UP_WIDTH-1:0]               item_up   = item_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    wire hit_match = (item_high == chk_hit_pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]) &&
                     (item_up >= chk_hit_pa_base[PA_UP_WIDTH-1:0]) &&
                     (item_up <= chk_hit_pa_up);

    assign chk_hit = item_valid && hit_match;

    // 控制信号 (valid / flushed): 带复位
    // 同拍优先级: 装填 > 删除 > 置无效
    //   装填只作用于空闲条目, 新请求不受同拍 inv 影响;
    //   删除直接把条目置回空闲, 同拍 inv 无需再置 flushed;
    //   inv 只把已存在的有效条目标成 flushed, 等 SDMQ 按年龄弹出.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            item_valid   <= 1'b0;
            item_flushed <= 1'b0;
        end
        else if (fill_en) begin
            item_valid   <= 1'b1;
            item_flushed <= 1'b0;
        end
        else if (del_en) begin
            item_valid   <= 1'b0;
            item_flushed <= 1'b0;
        end
        else if (item_valid && (inv_all || inv_match)) begin
            item_flushed <= 1'b1;
        end
    end

    // 数据信号 (pa / id): 无复位, 只在装填时更新
    always_ff @(posedge clk) begin
        if (fill_en) begin
            item_pa <= fill_pa;
            item_id <= fill_id;
        end
    end

    // 条目内容输出
    assign sdmq_item = '{valid: item_valid, flushed: item_flushed, id: item_id, pa: item_pa};

`ifdef ASSERT_ON
    // 同一拍最多只能有 1 种置无效 (刷新) 请求
    `assert_clk(a_inv_onehot0, !(inv_all && inv_en))

    // 装填只作用于空闲条目, 删除只作用于有效条目
    `assert_clk(a_fill_on_free, (fill_en |-> !item_valid))
    `assert_clk(a_del_on_valid, (del_en |->  item_valid))

    // 控制器不会对同一条目同拍又删又填 (由上面两条也能推出, 这里显式写成交互约定)
    `assert_clk(a_fill_del_exclusive, !(fill_en && del_en))

    // 空闲条目的 chk_hit 必须为 0
    `assert_clk(a_hit_on_valid, (chk_hit |-> item_valid))
`endif

endmodule

`default_nettype wire
