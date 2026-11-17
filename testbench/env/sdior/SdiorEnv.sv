`ifndef _SDIOR_ENV_SV_
`define _SDIOR_ENV_SV_

class SdiorEnv extends uvm_env;

    `uvm_component_utils(SdiorEnv)

    SdiorAgt agt;
    SdiorScb scb;

    // RAL: 寄存器模型 + 总线适配器 + 用 monitor 事务自动更新 mirror
    sdior_reg_block                 reg_model;
    sdior_reg_adapter               reg_adapter;
    uvm_reg_predictor#(SdiorItem)   predictor;

    function new(string name = "SdiorEnv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = SdiorAgt::type_id::create("agt", this);
        scb = SdiorScb::type_id::create("scb", this);

        reg_model = sdior_reg_block::type_id::create("reg_model");
        reg_model.build();
        reg_model.lock_model();
        reg_adapter = sdior_reg_adapter::type_id::create("reg_adapter");
        predictor = uvm_reg_predictor#(SdiorItem)::type_id::create("predictor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(scb.imp);

        // RAL 的 frontdoor: 寄存器访问经 reg_adapter 变成 SdiorItem, 在 sqr 上执行
        reg_model.default_map.set_sequencer(agt.sqr, reg_adapter);

        // 用 monitor 的事务更新 mirror (auto predict 关闭, 由 predictor 负责)
        predictor.map     = reg_model.default_map;
        predictor.adapter = reg_adapter;
        agt.mon.ap.connect(predictor.bus_in);

        scb.reg_model = reg_model;
    endfunction

endclass

`endif // _SDIOR_ENV_SV_
