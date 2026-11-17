`ifndef _SDECODER_SCB_SV_
`define _SDECODER_SCB_SV_

class SdecoderScb extends uvm_scoreboard;

    `uvm_component_utils(SdecoderScb)

    int exp_count;
    int act_count;
    int err_count;

    function new(string name = "SdecoderScb", uvm_component parent = null);
        super.new(name, parent);
        exp_count = 0;
        act_count = 0;
        err_count = 0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // TODO: 例化 analysis fifo / 注册 analysis imp
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (err_count != 0) begin
            `uvm_error("SCB", $sformatf("%0d 条比对错误", err_count))
        end
    endfunction

endclass

`endif // _SDECODER_SCB_SV_
