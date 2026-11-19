// SDTLB 的探针接口 (只读): 用 bind 挂到 sdtlb 模块上, 采到的是 DUT 引脚上的真实信号
//
// 用途: monitor 只依赖这个接口, 不依赖 tb 顶层的 sdtlb_if.
//   - tb_sdtlb 里 sdtlb 在 wrapper_sdtlb 内部 (wrapper 对输入打 1 拍), 探针看到的是打拍之后的信号
//   - 以后验 SDecoder 时, sdtlb 作为子模块实例化, 同一个 bind 仍然生效, monitor 可以原样复用
//
// 注意: 探针路径是 <sdtlb 实例>.u_sdtlb_if_probe_bind, tb 顶层要把这个路径上的接口实例灌给 monitor.
interface sdtlb_if_probe
import sdecoder_pkg::*;

(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    cam0_req_en,
    input  logic [PA_WIDTH-1:0]     cam0_req_pa,
    input  logic                    cam0_hit,
    input  SDTLB_TAG_ITEM_t         cam0_hit_tag_item,     // 不含 Valid (见 cam0_hit)
    input  SDTLB_DATA_ITEM_t        cam0_hit_data_item,

    input  logic                    cam1_req_en,
    input  logic [PA_WIDTH-1:0]     cam1_req_pa,
    input  logic                    cam1_hit,
    input  SDTLB_TAG_ITEM_t         cam1_hit_tag_item,
    input  SDTLB_DATA_ITEM_t        cam1_hit_data_item,

    input  logic                    fill_en,
    input  logic [PA_BASE_WIDTH-1:0]      fill_pa_base,
    input  logic [PA_UP_WIDTH-1:0]        fill_pa_up,
    input  logic [EID_WIDTH-1:0]          fill_eid,
    input  logic [TOKEN_ID_WIDTH-1:0]     fill_token_id,
    input  logic [TOKEN_VALUE_WIDTH-1:0]  fill_token_value,
    input  logic [S_PFN_WIDTH-1:0]        fill_s_pfn,

    input  logic                    inv_en,
    input  logic                    inv_all,
    input  logic                    inv_sel,
    input  logic [PA_BASE_WIDTH-1:0] inv_sel_pa
);

    timeunit      1ps;
    timeprecision 1ps;

    // 采样 DUT 引脚: 与 sdtlb_if 的 mon 块口径一致 (1step 采样)
    clocking mon @(posedge clk);
        default input #1;

        input cam0_req_en;
        input cam0_req_pa;
        input cam0_hit;
        input cam0_hit_tag_item;
        input cam0_hit_data_item;

        input cam1_req_en;
        input cam1_req_pa;
        input cam1_hit;
        input cam1_hit_tag_item;
        input cam1_hit_data_item;

        input fill_en;
        input fill_pa_base;
        input fill_pa_up;
        input fill_eid;
        input fill_token_id;
        input fill_token_value;
        input fill_s_pfn;

        input inv_en;
        input inv_all;
        input inv_sel;
        input inv_sel_pa;
    endclocking

endinterface

