`ifndef _SDIOR_AGT_SV_
`define _SDIOR_AGT_SV_

class SdiorAgt extends uvm_agent;

    `uvm_component_utils(SdiorAgt)

    SdiorSqr sqr;
    SdiorDrv drv;
    SdiorMon mon;

    function new(string name = "SdiorAgt", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            sqr = SdiorSqr::type_id::create("sqr", this);
            drv = SdiorDrv::type_id::create("drv", this);
        end
        mon = SdiorMon::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE) begin
            drv.seq_item_port.connect(sqr.seq_item_export);
        end
    endfunction

endclass

`endif // _SDIOR_AGT_SV_
