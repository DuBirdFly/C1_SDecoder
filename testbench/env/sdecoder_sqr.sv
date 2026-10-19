`ifndef _SDECODER_SQR_SV_
`define _SDECODER_SQR_SV_

class SdecoderSqr extends uvm_sequencer#(sdecoder_item);

    `uvm_component_utils(SdecoderSqr)

    function new(string name = "SdecoderSqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif // _SDECODER_SQR_SV_
