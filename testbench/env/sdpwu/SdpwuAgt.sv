`ifndef _SDPWU_AGT_SV_
`define _SDPWU_AGT_SV_

class SdpwuAgt extends uvm_agent;

    `uvm_component_utils(SdpwuAgt)

    SdpwuSqr sqr;
    SdpwuDrv drv;
    SdpwuMon mon;

    function new(string name = "SdpwuAgt", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = SdpwuSqr::type_id::create("sqr", this);
        drv = SdpwuDrv::type_id::create("drv", this);
        mon = SdpwuMon::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

`endif // _SDPWU_AGT_SV_
