`ifndef _SDPWU_SQR_SV_
`define _SDPWU_SQR_SV_

class SdpwuSqr extends uvm_sequencer#(SdpwuItem);

    `uvm_component_utils(SdpwuSqr)

    function new(string name = "SdpwuSqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif // _SDPWU_SQR_SV_
