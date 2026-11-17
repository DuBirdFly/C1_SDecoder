`ifndef _SDIOR_DRV_SV_
`define _SDIOR_DRV_SV_

class SdiorDrv extends uvm_driver#(SdiorItem);

    `uvm_component_utils(SdiorDrv)

    virtual sdior_if vif;

    function new(string name = "SdiorDrv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdior_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdiorDrv: no virtual sdior_if")
        end
    endfunction

    task signal_reset();
        @(vif.drv);
        vif.drv.ior_en    <= 1'b0;
        vif.drv.ior_write <= 1'b0;
        vif.drv.ior_waddr <= '0;
        vif.drv.ior_wdata <= '0;
        vif.drv.ior_raddr <= '0;

        do @(vif.mon); while (vif.mon.rst_n !== 1'b1);
        repeat (5) @(vif.mon);
    endtask

    task run_phase(uvm_phase phase);
        signal_reset();

        forever begin
            seq_item_port.try_next_item(req);

            if (req == null) begin
                @(vif.drv);
            end
            else begin
                case (req.kind)
                    SDIOR_WR:   drive_wr(req);
                    SDIOR_RD:   drive_rd(req);
                    SDIOR_WAIT: drive_wait(req);
                    default:    `uvm_error("KIND", "unknown SdiorItem kind")
                endcase

                rsp = SdiorItem::type_id::create("rsp");
                rsp.copy(req);
                rsp.set_id_info(req);
                seq_item_port.put_response(rsp);
                seq_item_port.item_done();
            end
        end
    endtask

    task drive_wr(SdiorItem tr);
        vif.drv.ior_en    <= 1'b1;
        vif.drv.ior_write <= 1'b1;
        vif.drv.ior_waddr <= tr.addr;
        vif.drv.ior_wdata <= tr.wdata;
        @(vif.drv);
        vif.drv.ior_en    <= 1'b0;
        vif.drv.ior_write <= 1'b0;
    endtask

    task drive_rd(SdiorItem tr);
        vif.drv.ior_en    <= 1'b1;
        vif.drv.ior_write <= 1'b0;
        vif.drv.ior_raddr <= tr.addr;
        @(vif.drv);
        tr.rdata = vif.drv.ior_rdata;
        vif.drv.ior_en    <= 1'b0;
        vif.drv.ior_write <= 1'b0;
    endtask

    task drive_wait(SdiorItem tr);
        repeat (tr.wait_cycles) @(vif.drv);
    endtask

endclass

`endif // _SDIOR_DRV_SV_
