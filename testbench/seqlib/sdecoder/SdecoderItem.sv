`ifndef _SDECODER_ITEM_SV_
`define _SDECODER_ITEM_SV_

class SdecoderItem extends uvm_sequence_item;

    `uvm_object_utils_begin(SdecoderItem)
        `uvm_field_enum(Sdecoder_Item_Kind_e, kind,        UVM_ALL_ON)
        `uvm_field_int (ior_waddr,                         UVM_ALL_ON)
        `uvm_field_int (ior_wdata,                         UVM_ALL_ON)
        `uvm_field_int (ior_raddr,                         UVM_ALL_ON)
        `uvm_field_int (ior_rdata,                         UVM_ALL_ON)
        `uvm_field_int (cam_req_pa,                        UVM_ALL_ON)
        `uvm_field_int (cam_req_id,                        UVM_ALL_ON)
        `uvm_field_int (wait_cycles,                       UVM_ALL_ON)
    `uvm_object_utils_end

    rand Sdecoder_Item_Kind_e         kind;

    // 寄存器写接口
    rand logic [SDIOR_ADDR_WIDTH-1:0] ior_waddr;
    rand logic [SDIOR_DATA_WIDTH-1:0] ior_wdata;

    // 寄存器读接口
    rand logic [SDIOR_ADDR_WIDTH-1:0] ior_raddr;
    rand logic [SDIOR_DATA_WIDTH-1:0] ior_rdata;

    // CAM 接口
    rand logic [PA_WIDTH-1:0]         cam_req_pa;
    rand logic [REQ_ID_WIDTH-1:0]     cam_req_id;

    // 等待周期数
    rand int unsigned                 wait_cycles;

    function new(string name = "SdecoderItem");
        super.new(name);
    endfunction

endclass

`endif // _SDECODER_ITEM_SV_
