interface sdtlb_if
import sdecoder_pkg::*;

(
    input  logic                    clk,
    input  logic                    rst_n
);

    timeunit 1ns;
    timeprecision 1ps;

    // 代换请求 (查表): 请求地址是 PA[47:30] (18 bit, 见 sdecoder_pkg 的 PA_BASE_WIDTH).
    // PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间, 因此断言 PA[47] 为 0 (字段保留这一位
    // 只为维持 48 位地址口径, 索引与 Tag 都比较 [47:35], 但装填时该位恒为 0)
    logic                               req_valid;
    logic [PA_WIDTH-1:0]                req_pa;
    logic                               req_hit;             // 命中
    SDTLB_TAG_ITEM_t                    req_hit_tag_item;    // 命中条目的 Tag 段内容
    SDTLB_DATA_ITEM_t                   req_hit_data_item;   // 命中条目的 Data 段内容

    // 装填请求 (Page Walk 结果)
    logic                               fill_valid;
    logic [PA_BASE_WIDTH-1:0]           fill_pa_base;
    logic [PA_UP_WIDTH-1:0]             fill_pa_up;
    logic [EID_WIDTH-1:0]               fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]          fill_token_id;
    logic [S_PFN_WIDTH-1:0]             fill_s_pfn;
    logic                               fill_grn;

    // 置无效 (刷新) 请求
    logic                               inv_all;
    logic                               inv_en;
    logic [PA_WIDTH-1:0]                inv_pa;

    // driver: 驱动 DUT 输入, 回读 DUT 输出
    clocking drv @(posedge clk);
        default input #1 output #1;

        output req_valid;
        output req_pa;
        output fill_valid;
        output fill_pa_base;
        output fill_pa_up;
        output fill_eid;
        output fill_token_id;
        output fill_s_pfn;
        output fill_grn;
        output inv_all;
        output inv_en;
        output inv_pa;

        input  req_hit;
        input  req_hit_tag_item;
        input  req_hit_data_item;
    endclocking

    // monitor: 全部采样
    clocking mon @(posedge clk);
        default input #1 output #1;

        input  req_valid;
        input  req_pa;
        input  req_hit;
        input  req_hit_tag_item;
        input  req_hit_data_item;
        input  fill_valid;
        input  fill_pa_base;
        input  fill_pa_up;
        input  fill_eid;
        input  fill_token_id;
        input  fill_s_pfn;
        input  fill_grn;
        input  inv_all;
        input  inv_en;
        input  inv_pa;
    endclocking

endinterface
