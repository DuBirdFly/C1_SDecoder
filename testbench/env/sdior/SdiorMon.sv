`ifndef _SDIOR_MON_SV_
`define _SDIOR_MON_SV_

class SdiorMon extends uvm_monitor;

    `uvm_component_utils(SdiorMon)

    virtual sdior_if vif;

    uvm_analysis_port#(SdiorItem) ap;

    function new(string name = "SdiorMon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual sdior_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdiorMon: no virtual sdior_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        SdiorItem tr;

        forever begin
            @(vif.mon);
            if (vif.mon.rst_n === 1'b1) begin
                if ((vif.mon.ior_en === 1'b1) && (vif.mon.ior_write === 1'b1)) begin
                    tr = SdiorItem::type_id::create("tr");
                    tr.kind  = SDIOR_WR;
                    tr.addr  = vif.mon.ior_waddr;
                    tr.wdata = vif.mon.ior_wdata;
                    ap.write(tr);
                end
                if ((vif.mon.ior_en === 1'b1) && (vif.mon.ior_write === 1'b0)) begin
                    tr = SdiorItem::type_id::create("tr");
                    tr.kind  = SDIOR_RD;
                    tr.addr  = vif.mon.ior_raddr;
                    tr.rdata = vif.mon.ior_rdata;
                    ap.write(tr);
                end
                if ((vif.mon.inv_all === 1'b1) || (vif.mon.inv_sel === 1'b1)) begin
                    tr = SdiorItem::type_id::create("tr");
                    tr.kind    = SDIOR_INV;
                    tr.inv_en  = (vif.mon.inv_en  === 1'b1);
                    tr.inv_all = (vif.mon.inv_all === 1'b1);
                    tr.inv_sel  = (vif.mon.inv_sel  === 1'b1);
                    tr.inv_sel_pa  = vif.mon.inv_sel_pa;
                    ap.write(tr);
                end
            end
        end
    endtask

endclass

`endif // _SDIOR_MON_SV_
