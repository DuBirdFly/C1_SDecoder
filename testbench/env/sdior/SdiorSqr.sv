`ifndef _SDIOR_SQR_SV_
`define _SDIOR_SQR_SV_

class SdiorSqr extends uvm_sequencer#(SdiorItem);

    `uvm_component_utils(SdiorSqr)

    function new(string name = "SdiorSqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif // _SDIOR_SQR_SV_
