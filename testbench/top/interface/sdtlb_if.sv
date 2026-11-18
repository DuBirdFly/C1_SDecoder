interface sdtlb_if
import sdecoder_pkg::*;

(
    input  logic clk,
    input  logic rst_n
);

    timeunit 1ps;
    timeprecision 1ps;

    // 查表端口: 下标就是 CAM 号 (共 SDTLB_CAM_NUM 个). 请求地址是整条 PA[47:0].
    // PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间, 因此断言 PA[47] 为 0 (字段保留这一位
    // 只为维持 48 位地址口径, 索引与 Tag 都比较 [47:35], 但装填时该位恒为 0)
    // req_en 是 1 拍使能, 与 fill_en 不同拍 (外界约定), 命中结果在下一拍由 hit / tag / data 给出
    logic                                   cam_req_en        [SDTLB_CAM_NUM];
    logic [PA_WIDTH-1:0]                    cam_req_pa        [SDTLB_CAM_NUM];
    logic                                   cam_hit           [SDTLB_CAM_NUM];  // 命中 (同时充当响应 valid)
    SDTLB_TAG_ITEM_t                        cam_hit_tag_item  [SDTLB_CAM_NUM];  // 命中条目的 Tag 段内容
    SDTLB_DATA_ITEM_t                       cam_hit_data_item [SDTLB_CAM_NUM];  // 命中条目的 Data 段内容

    // 装填请求 (Page Walk 结果)
    logic                               fill_en;
    logic [PA_BASE_WIDTH-1:0]           fill_pa_base;
    logic [PA_UP_WIDTH-1:0]             fill_pa_up;
    logic [EID_WIDTH-1:0]               fill_eid;
    logic [TOKEN_ID_WIDTH-1:0]          fill_token_id;
    logic [TOKEN_VALUE_WIDTH-1:0]       fill_token_value;
    logic [S_PFN_WIDTH-1:0]             fill_s_pfn;

    // 置无效 (刷新) 请求: inv_en 是总使能, inv_all / inv_sel 只在它有效的当拍起作用
    logic                               inv_en;
    logic                               inv_all;
    logic                               inv_sel;
    logic [PA_BASE_WIDTH-1:0]           inv_sel_pa;

    // driver: 驱动 DUT 输入, 回读 DUT 输出
    clocking drv @(posedge clk);
        default input #1 output #1;

        output cam_req_en;
        output cam_req_pa;
        output fill_en;
        output fill_pa_base;
        output fill_pa_up;
        output fill_eid;
        output fill_token_id;
        output fill_token_value;
        output fill_s_pfn;
        output inv_en;
        output inv_all;
        output inv_sel;
        output inv_sel_pa;

        input  cam_hit;
        input  cam_hit_tag_item;
        input  cam_hit_data_item;
    endclocking

    // monitor: 全部采样
    clocking mon @(posedge clk);
        default input #1 output #1;

        input  cam_req_en;
        input  cam_req_pa;
        input  cam_hit;
        input  cam_hit_tag_item;
        input  cam_hit_data_item;
        input  fill_en;
        input  fill_pa_base;
        input  fill_pa_up;
        input  fill_eid;
        input  fill_token_id;
        input  fill_token_value;
        input  fill_s_pfn;
        input  inv_en;
        input  inv_all;
        input  inv_sel;
        input  inv_sel_pa;
    endclocking

endinterface
