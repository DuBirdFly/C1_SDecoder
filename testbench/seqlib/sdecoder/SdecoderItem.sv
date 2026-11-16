`ifndef _SDECODER_ITEM_SV_
`define _SDECODER_ITEM_SV_

class SdecoderItem extends uvm_sequence_item;

    `uvm_object_utils(SdecoderItem)

    rand Sdecoder_Item_Kind_e         kind;
    rand logic [SDIOR_ADDR_WIDTH-1:0] cfg_addr;
    rand logic [SDIOR_DATA_WIDTH-1:0] cfg_wdata;
    rand logic [PA_WIDTH-1:0]         pa;
    rand logic [REQ_ID_WIDTH-1:0]     id;
    rand bit                          rsp_ready;
    rand int unsigned                 wait_cycles;

    function new(string name = "SdecoderItem");
        super.new(name);
    endfunction

endclass

`endif // _SDECODER_ITEM_SV_
