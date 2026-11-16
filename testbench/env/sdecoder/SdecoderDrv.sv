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
        // 初始电平: 不请求, 不写寄存器, 默认能收响应
        vif.drv.req_valid <= 1'b0;
        vif.drv.req_pa    <= '0;
        vif.drv.req_id    <= '0;
        vif.drv.rsp_ready <= 1'b1;
        vif.drv.cfg_wr    <= 1'b0;
        vif.drv.cfg_rd    <= 1'b0;
        vif.drv.cfg_addr  <= '0;
        vif.drv.cfg_wdata <= '0;

        wait (vif.rst_n === 1'b1);
        repeat (5) @(vif.drv);

        forever begin
            seq_item_port.try_next_item(req);
            if (req != null) begin
                case (req.kind)
                    SDEC_CFG_WR:    drive_cfg(req);
                    SDEC_REQ:       drive_req(req);
                    SDEC_RSP_READY: drive_rsp_ready(req);
                    SDEC_WAIT:      drive_wait(req);
                    default:        `uvm_error("KIND", "unknown SdecoderItem kind")
                endcase
                seq_item_port.item_done();
            end
            else begin
                @(vif.drv);
            end
        end
    endtask

    task drive_cfg(SdecoderItem tr);
        @(vif.drv);
        vif.drv.cfg_wr    <= 1'b1;
        vif.drv.cfg_addr  <= tr.cfg_addr;
        vif.drv.cfg_wdata <= tr.cfg_wdata;
        @(vif.drv);
        vif.drv.cfg_wr    <= 1'b0;
        @(vif.drv);
    endtask

    task drive_req(SdecoderItem tr);
        @(vif.drv);
        vif.drv.req_valid <= 1'b1;
        vif.drv.req_pa    <= tr.pa;
        vif.drv.req_id    <= tr.id;
        do @(vif.drv); while (!vif.drv.req_ready);
        vif.drv.req_valid <= 1'b0;
        @(vif.drv);
    endtask

    task drive_rsp_ready(SdecoderItem tr);
        @(vif.drv);
        vif.drv.rsp_ready <= tr.rsp_ready;
        @(vif.drv);
    endtask

    task drive_wait(SdecoderItem tr);
        repeat (tr.wait_cycles) @(vif.drv);
    endtask

endclass

`endif // _SDECODER_DRV_SV_
