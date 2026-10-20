`ifndef _SDECODER_ENV_SV_
`define _SDECODER_ENV_SV_

class SdecoderEnv extends uvm_env;

    `uvm_component_utils(SdecoderEnv)

    SdecoderAgt agt;
    SdecoderPageTableModel page_table_model;

    function new(string name = "SdecoderEnv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = SdecoderAgt::type_id::create("agt", this);
        page_table_model = SdecoderPageTableModel::type_id::create("page_table_model", this);
    endfunction

endclass

`endif // _SDECODER_ENV_SV_
