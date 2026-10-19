`ifndef _SDECODER_AGT_SV_
`define _SDECODER_AGT_SV_

import uvm_pkg::*;

class SdecoderAgt extends uvm_agent;

    `uvm_component_utils(SdecoderAgt)

    SdecoderSqr sqr;
    SdecoderDrv drv;
    SdecoderMon mon;

    function new(string name = "SdecoderAgt", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = SdecoderSqr::type_id::create("sqr", this);
            drv = SdecoderDrv::type_id::create("drv", this);
        end
        mon = SdecoderMon::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction

endclass

`endif // _SDECODER_AGT_SV_
