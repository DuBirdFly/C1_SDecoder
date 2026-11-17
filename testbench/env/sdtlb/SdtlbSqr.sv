`ifndef _SDTLB_SQR_SV_
`define _SDTLB_SQR_SV_

class SdtlbSqr extends uvm_sequencer#(SdtlbItem);

    `uvm_component_utils(SdtlbSqr)

    function new(string name = "SdtlbSqr", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif // _SDTLB_SQR_SV_
