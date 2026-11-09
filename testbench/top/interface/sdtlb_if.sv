interface sdtlb_if
import sdecoder_pkg::*;

(
    input  logic                    clk,
    input  logic                    rst_n
);

    timeunit 1ns;
    timeprecision 1ps;

    // 查表端口 0 (CAM0): 请求地址是整条 PA[47:0].
    // PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间, 因此断言 PA[47] 为 0 (字段保留这一位
    // 只为维持 48 位地址口径, 索引与 Tag 都比较 [47:35], 但装填时该位恒为 0)
    // 请求拍握手 (valid && ready), 命中结果在下一拍由 hit / hit_tag_item / hit_data_item 给出
    logic                               cam0_req_valid;
    logic                               cam0_req_ready;
    logic [PA_WIDTH-1:0]                cam0_req_pa;
    logic                               cam0_hit;             // 命中 (同时充当响应 valid)
    SDTLB_TAG_ITEM_t                    cam0_hit_tag_item;    // 命中条目的 Tag 段内容
    SDTLB_DATA_ITEM_t                   cam0_hit_data_item;   // 命中条目的 Data 段内容

    // 查表端口 1 (CAM1): 与 CAM0 完全独立, 可以和 CAM0 同拍握手、同拍命中
    logic                               cam1_req_valid;
    logic                               cam1_req_ready;
    logic [PA_WIDTH-1:0]                cam1_req_pa;
    logic                               cam1_hit;
    SDTLB_TAG_ITEM_t                    cam1_hit_tag_item;
    SDTLB_DATA_ITEM_t                   cam1_hit_data_item;

    // 装填请求 (Page Walk 结果)
    logic                               fill_en;
    logic [PA_BASE_WIDTH-1:0]           fill_pa_base;
    logic [PA_UP_WIDTH-1:0]             fill_pa_up;
    logic [EID_WIDTH-1:0]               fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]          fill_token_id;
    logic [S_PFN_WIDTH-1:0]             fill_s_pfn;

    // 置无效 (刷新) 请求
    logic                               inv_all;
    logic                               inv_en;
    logic [PA_WIDTH-1:0]                inv_pa;

    // driver: 驱动 DUT 输入, 回读 DUT 输出
    clocking drv @(posedge clk);
        default input #1 output #1;

        output cam0_req_valid;
        output cam0_req_pa;
        output cam1_req_valid;
        output cam1_req_pa;
        output fill_en;
        output fill_pa_base;
        output fill_pa_up;
        output fill_eid;
        output fill_token_id;
        output fill_s_pfn;
        output inv_all;
        output inv_en;
        output inv_pa;

        input  cam0_req_ready;
        input  cam0_hit;
        input  cam0_hit_tag_item;
        input  cam0_hit_data_item;
        input  cam1_req_ready;
        input  cam1_hit;
        input  cam1_hit_tag_item;
        input  cam1_hit_data_item;
    endclocking

    // monitor: 全部采样
    clocking mon @(posedge clk);
        default input #1 output #1;

        input  cam0_req_valid;
        input  cam0_req_ready;
        input  cam0_req_pa;
        input  cam0_hit;
        input  cam0_hit_tag_item;
        input  cam0_hit_data_item;
        input  cam1_req_valid;
        input  cam1_req_ready;
        input  cam1_req_pa;
        input  cam1_hit;
        input  cam1_hit_tag_item;
        input  cam1_hit_data_item;
        input  fill_en;
        input  fill_pa_base;
        input  fill_pa_up;
        input  fill_eid;
        input  fill_token_id;
        input  fill_s_pfn;
        input  inv_all;
        input  inv_en;
        input  inv_pa;
    endclocking

endinterface
