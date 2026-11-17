`ifndef _SDPWU_ENV_SV_
`define _SDPWU_ENV_SV_

class SdpwuEnv extends uvm_env;

    `uvm_component_utils(SdpwuEnv)

    SdpwuAgt            agt;
    SdpwuScb            scb;
    page_table_model    pt_model;       // 页表 / 内存模型, test 也用它来写表
    logic [PA_WIDTH-1:0] l1_base = 48'h0000_1000_0000;   // 一级表基地址 (16B 对界)

    function new(string name = "SdpwuEnv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt      = SdpwuAgt::type_id::create("agt", this);
        scb      = SdpwuScb::type_id::create("scb", this);
        pt_model = new();
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.imp);

        agt.drv.pt_model    = pt_model;
        agt.drv.l1_base_val = l1_base;
        scb.pt_model        = pt_model;
        scb.l1_base         = l1_base;
    endfunction

endclass

`endif // _SDPWU_ENV_SV_
