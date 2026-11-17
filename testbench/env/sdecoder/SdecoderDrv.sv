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

    task signal_reset();
        // TODO: sdecoder_if 定稿后在这里设初始电平, 并等复位释放
    endtask

    task run_phase(uvm_phase phase);
        signal_reset();

        forever begin
            seq_item_port.try_next_item(req);

            if (req == null) begin
                @(vif.drv);
            end
            else begin
                // TODO: 接口定稿后按 req.kind 驱动 cam0 / cam1 / ior / sdmq_rsp 等

                seq_item_port.item_done();
            end
        end
    endtask

endclass

`endif // _SDECODER_DRV_SV_
