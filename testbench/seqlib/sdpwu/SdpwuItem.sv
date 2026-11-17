`ifndef _SDPWU_ITEM_SV_
`define _SDPWU_ITEM_SV_

// SDPWU_TOP 的事务 (事务类型 Sdpwu_Item_Kind_e 定义在 sdpwu_seq_pkg.svh)
class SdpwuItem extends uvm_sequence_item;

    `uvm_object_utils_begin(SdpwuItem)
        `uvm_field_enum(Sdpwu_Item_Kind_e, kind,          UVM_ALL_ON)
        `uvm_field_int (pa,                               UVM_ALL_ON)
        `uvm_field_int (sdmq_idx,                         UVM_ALL_ON)
        `uvm_field_int (wait_cycles,                      UVM_ALL_ON)
        `uvm_field_int (mem_addr,                         UVM_ALL_ON)
        `uvm_field_int (mem_id,                           UVM_ALL_ON)
        // finish_item 是 packed struct, 不加 field 宏 (VCS 对 struct 的 field 宏不稳)
        `uvm_field_int (finish_item_pack,                 UVM_ALL_ON)
    `uvm_object_utils_end

    rand Sdpwu_Item_Kind_e          kind;

    // SDPWU_PW_START
    rand logic [PA_WIDTH-1:0]       pa;
    rand logic [SDMQ_IDX_WIDTH-1:0] sdmq_idx;

    // SDPWU_WAIT
    rand int unsigned               wait_cycles;

    // SDPWU_MEM_RD
    logic [PA_WIDTH-1:0]            mem_addr;
    logic [PW_ID_WIDTH-1:0]         mem_id;

    // SDPWU_FINISH
    SDPWU_FINISH_t                  finish_item;
    logic [$bits(SDPWU_FINISH_t)-1:0] finish_item_pack;

    function new(string name = "SdpwuItem");
        super.new(name);
    endfunction

endclass

`endif // _SDPWU_ITEM_SV_
