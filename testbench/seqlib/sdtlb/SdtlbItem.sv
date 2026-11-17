`ifndef _SDTLB_ITEM_SV_
`define _SDTLB_ITEM_SV_

// SDTLB 的总线事务 (事务类型 Sdtlb_Item_Kind_e 定义在 sdtlb_seq_pkg.svh)
//   SDTLB_REQ : 查表请求 (cam0 / cam1 可同拍), 响应由 monitor 回填 (hit / tag / data)
//   SDTLB_FILL: 装填一个条目 (Page Walk 结果)
//   SDTLB_INV : 置无效 (inv_all 或按地址 inv_sel)
//   SDTLB_WAIT: 空等 wait_cycles 拍
class SdtlbItem extends uvm_sequence_item;

    `uvm_object_utils_begin(SdtlbItem)
        `uvm_field_enum(Sdtlb_Item_Kind_e, kind,          UVM_ALL_ON)
        `uvm_field_int (cam0_req_en,                      UVM_ALL_ON)
        `uvm_field_int (cam0_req_pa,                      UVM_ALL_ON)
        `uvm_field_int (cam1_req_en,                      UVM_ALL_ON)
        `uvm_field_int (cam1_req_pa,                      UVM_ALL_ON)
        `uvm_field_int (fill_pa_base,                     UVM_ALL_ON)
        `uvm_field_int (fill_pa_up,                       UVM_ALL_ON)
        `uvm_field_int (fill_eid,                         UVM_ALL_ON)
        `uvm_field_int (fill_token_id,                    UVM_ALL_ON)
        `uvm_field_int (fill_token_value,                 UVM_ALL_ON)
        `uvm_field_int (fill_s_pfn,                       UVM_ALL_ON)
        `uvm_field_int (inv_all,                          UVM_ALL_ON)
        `uvm_field_int (inv_sel,                          UVM_ALL_ON)
        `uvm_field_int (inv_sel_pa,                       UVM_ALL_ON)
        `uvm_field_int (wait_cycles,                      UVM_ALL_ON)
        `uvm_field_int (cam0_hit,                         UVM_ALL_ON)
        `uvm_field_int (cam0_tag,                         UVM_ALL_ON)
        `uvm_field_int (cam0_data,                        UVM_ALL_ON)
        `uvm_field_int (cam1_hit,                         UVM_ALL_ON)
        `uvm_field_int (cam1_tag,                         UVM_ALL_ON)
        `uvm_field_int (cam1_data,                        UVM_ALL_ON)
    `uvm_object_utils_end

    rand Sdtlb_Item_Kind_e              kind;

    // 查表请求 (两个端口可以同拍)
    rand logic                          cam0_req_en;
    rand logic [PA_WIDTH-1:0]           cam0_req_pa;
    rand logic                          cam1_req_en;
    rand logic [PA_WIDTH-1:0]           cam1_req_pa;

    // 装填
    rand logic                          fill_en;
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

    // 响应 (monitor 回填)
    logic                               cam0_hit;
    SDTLB_TAG_ITEM_t                    cam0_tag;
    SDTLB_DATA_ITEM_t                   cam0_data;
    logic                               cam1_hit;
    SDTLB_TAG_ITEM_t                    cam1_tag;
    SDTLB_DATA_ITEM_t                   cam1_data;

    function new(string name = "SdtlbItem");
        super.new(name);
    endfunction

endclass

`endif // _SDTLB_ITEM_SV_
