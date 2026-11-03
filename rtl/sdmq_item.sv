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
    // 由于 valid 为 0 时条目无意义, 所以空闲条目 hit 必定为 0
    input  logic [PA_BASE_WIDTH-1:0]    pa_base,
    input  logic [PA_UP_WIDTH-1:0]      pa_up,
    output logic                        hit,

    // 装填请求 (TLB miss 后, 把本次地址代换请求装入 sdmq 缓冲)
    input  logic                        req_en,
    input  logic [REQ_ID_WIDTH-1:0]     req_id,
    input  logic [PA_WIDTH-1:0]         req_pa,

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









    // [TODO] 断言同一拍只能有 1 种置无效 (刷新) 请求
    // [TODO] 断言 req_en 有效时, 当前条目必然是空闲的 (valid = 0)
    // [TODO] 断言 del_en 有效时, 当前条目必然是有效的 (valid = 1)

endmodule


`default_nettype wire
