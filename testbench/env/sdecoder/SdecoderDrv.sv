`ifndef _SDECODER_DRV_SV_
`define _SDECODER_DRV_SV_

class SdecoderDrv extends uvm_driver#(SdecoderItem);

    `uvm_component_utils(SdecoderDrv)

    virtual sdecoder_if vif;

    function new(string name = "SdecoderDrv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdecoder_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdecoderDrv: no virtual sdecoder_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            seq_item_port.item_done();
        end
    endtask

endclass

`endif // _SDECODER_DRV_SV_
