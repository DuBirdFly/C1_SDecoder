`ifndef _SDTLB_AGT_SV_
`define _SDTLB_AGT_SV_

class SdtlbAgt extends uvm_agent;

    `uvm_component_utils(SdtlbAgt)

    SdtlbSqr sqr;
    SdtlbDrv drv;
    SdtlbMon mon;

    function new(string name = "SdtlbAgt", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = SdtlbSqr::type_id::create("sqr", this);
        drv = SdtlbDrv::type_id::create("drv", this);
        mon = SdtlbMon::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

`endif // _SDTLB_AGT_SV_
