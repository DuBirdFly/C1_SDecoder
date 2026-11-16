`ifndef _SDECODER_PAGE_TABLE_MODEL_SV_
`define _SDECODER_PAGE_TABLE_MODEL_SV_

class SdecoderPageTableModel extends uvm_component;

    `uvm_component_utils(SdecoderPageTableModel)

    virtual sdecoder_if vif;

    function new(string name = "SdecoderPageTableModel", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdecoder_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdecoderPageTableModel: no virtual sdecoder_if")
        end
    endfunction

endclass

`endif // _SDECODER_PAGE_TABLE_MODEL_SV_
