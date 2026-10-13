interface sdtlb_if
import sdecoder_pkg::*;

(
    input  logic                    clk,
    input  logic                    rst_n
);

    timeunit 1ns;
    timeprecision 1ps;

    // 代换请求 (查表): 请求地址只到 PA[46:30] (17 bit, 见 sdecoder_pkg 的 PA_BASE_WIDTH).
    // PA[47] = 1 是 IO 空间, SDecoder 直接不接受这一位 (索引与 Tag 都只到 [46:30])
    logic                               req_vld;
    logic [PA_BASE_WIDTH-1:0]           req_pa;
    logic                               req_hit;             // 命中
    SDTLB_TAG_ITEM_t                    req_hit_tag_item;    // 命中条目的 Tag 段内容
    SDTLB_DATA_ITEM_t                   req_hit_data_item;   // 命中条目的 Data 段内容

    // 装填请求 (Page Walk 结果)
    logic                               fill_vld;
    logic [PA_BASE_WIDTH-1:0]           fill_pa_base;
    logic [PA_UP_WIDTH-1:0]             fill_pa_up;
    logic [EID_WIDTH-1:0]               fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]          fill_token_id;
    logic [S_PFN_WIDTH-1:0]             fill_s_pfn;
    logic                               fill_grn;

    // 置无效 (刷新) 请求
    logic                               inv_all;
    logic                               inv_en;
    logic [PA_BASE_WIDTH-1:0]           inv_pa;

    // driver: 驱动 DUT 输入, 回读 DUT 输出
    clocking drv @(posedge clk);
        default input #1 output #1;

        output req_vld;
        output req_pa;
        output fill_vld;
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

        input  req_vld;
        input  req_pa;
        input  req_hit;
        input  req_hit_tag_item;
        input  req_hit_data_item;
        input  fill_vld;
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
