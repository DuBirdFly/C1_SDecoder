`ifndef _SDECODER_MON_SV_
`define _SDECODER_MON_SV_

class SdecoderMon extends uvm_monitor;

    `uvm_component_utils(SdecoderMon)

    virtual sdecoder_if vif;

    function new(string name = "SdecoderMon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdecoder_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdecoderMon: no virtual sdecoder_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
        end
    endtask

endclass

`endif // _SDECODER_MON_SV_
