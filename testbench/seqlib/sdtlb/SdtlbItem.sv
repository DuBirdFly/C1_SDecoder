`ifndef _SDTLB_ITEM_SV_
`define _SDTLB_ITEM_SV_

// SDTLB 的总线事务: 用各端口的使能描述一拍里同时发生的事 (不再用 kind 区分)
//   cam_req_en[i] / cam_req_pa[i] : 第 i 个 CAM 端口的查表请求, 响应由 monitor 回填 (cam_hit / cam_tag / cam_data)
//   fill_en                       : 装填一个条目 (Page Walk 结果)
//   inv_en                        : 置无效总使能, 与 inv_all / inv_sel 同拍有效
//   wait_cycles_en                : 空等 wait_cycles 拍 (只在 driver 侧有意义)
//
// 外界约定: fill_en 不能与任何 cam_req_en 同拍 (Latch 不支持同拍读写)
class SdtlbItem extends uvm_sequence_item;

    `uvm_object_utils_begin(SdtlbItem)
        `uvm_field_int (cam_req_en,                       UVM_ALL_ON)
        `uvm_field_int (cam_req_pa,                       UVM_ALL_ON)
        `uvm_field_int (fill_en,                          UVM_ALL_ON)
        `uvm_field_int (fill_pa_base,                     UVM_ALL_ON)
        `uvm_field_int (fill_pa_up,                       UVM_ALL_ON)
        `uvm_field_int (fill_eid,                         UVM_ALL_ON)
        `uvm_field_int (fill_token_id,                    UVM_ALL_ON)
        `uvm_field_int (fill_token_value,                 UVM_ALL_ON)
        `uvm_field_int (fill_s_pfn,                       UVM_ALL_ON)
        `uvm_field_int (inv_en,                           UVM_ALL_ON)
        `uvm_field_int (inv_all,                          UVM_ALL_ON)
        `uvm_field_int (inv_sel,                          UVM_ALL_ON)
        `uvm_field_int (inv_sel_pa,                       UVM_ALL_ON)
        `uvm_field_int (wait_cycles_en,                   UVM_ALL_ON)
        `uvm_field_int (wait_cycles,                      UVM_ALL_ON)
        `uvm_field_int (cam_hit,                          UVM_ALL_ON)
        `uvm_field_int (cam_tag,                          UVM_ALL_ON)
        `uvm_field_int (cam_data,                         UVM_ALL_ON)
    `uvm_object_utils_end

    // 端口使能 (每 bit 一个 CAM 端口)
    rand logic                          fill_en;
    rand logic                          inv_en;
    rand logic                          wait_cycles_en;

    // 查表请求
    rand logic [SDTLB_CAM_NUM-1:0]                  cam_req_en;
    rand logic [SDTLB_CAM_NUM-1:0][PA_WIDTH-1:0]    cam_req_pa;

    // 装填
    rand logic [PA_BASE_WIDTH-1:0]      fill_pa_base;
    rand logic [PA_UP_WIDTH-1:0]        fill_pa_up;
    rand logic [EID_WIDTH-1:0]          fill_eid;
    rand logic [TOKEN_ID_WIDTH-1:0]     fill_token_id;
    rand logic [TOKEN_VALUE_WIDTH-1:0]  fill_token_value;
    rand logic [S_PFN_WIDTH-1:0]        fill_s_pfn;

    // 置无效
    rand logic                          inv_all;
    rand logic                          inv_sel;
    rand logic [PA_BASE_WIDTH-1:0]      inv_sel_pa;

    // 等待
    rand int unsigned                   wait_cycles;

    // 响应 (monitor 回填, 每 bit / 每段对应一个 CAM 端口)
    logic [SDTLB_CAM_NUM-1:0]                           cam_hit;
    logic [SDTLB_CAM_NUM-1:0][SDTLB_TAG_ITEM_WIDTH-1:0]  cam_tag;
    logic [SDTLB_CAM_NUM-1:0][SDTLB_DATA_ITEM_WIDTH-1:0] cam_data;

    // 外界约定: 装填与查表不能同拍
    constraint c_fill_cam_excl {
        !(fill_en && (cam_req_en != '0));
    }

    function new(string name = "SdtlbItem");
        super.new(name);
    endfunction

endclass

`endif // _SDTLB_ITEM_SV_
