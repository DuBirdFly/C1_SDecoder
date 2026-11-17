`ifndef _SDTLB_ENV_SV_
`define _SDTLB_ENV_SV_

class SdtlbEnv extends uvm_env;

    `uvm_component_utils(SdtlbEnv)

    SdtlbAgt agt;
    SdtlbScb scb;

    function new(string name = "SdtlbEnv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = SdtlbAgt::type_id::create("agt", this);
        scb = SdtlbScb::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.imp);
    endfunction

endclass

`endif // _SDTLB_ENV_SV_
