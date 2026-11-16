`ifndef _SDECODER_SCB_SV_
`define _SDECODER_SCB_SV_

// SDecoder 记分板 (骨架)
//
//   TODO: SDecoder 顶层与 monitor 定稿后补:
//     1. 用 analysis port / analysis fifo 接收 monitor 采到的响应
//     2. 按 id 匹配期望与实际 (响应乱序, 只能按 id 配, 见设计方案 "接口分组")
//     3. 比对 SLMD 字段 (EID / TokenID / TokenValue / SLA) 与 err / flushed
//     4. 在 check_phase 里报出未匹配的期望与比对错误
class SdecoderScb extends uvm_scoreboard;

    `uvm_component_utils(SdecoderScb)

    int exp_count;      // 期望响应数
    int act_count;      // 实际响应数
    int err_count;      // 比对错误数

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
