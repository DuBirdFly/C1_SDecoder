`ifndef _SDPWU_MON_SV_
`define _SDPWU_MON_SV_

// SDPWU_TOP 的 monitor: 观测 start 握手 / 访存读请求 / Page Walk 结束
class SdpwuMon extends uvm_monitor;

    `uvm_component_utils(SdpwuMon)

    virtual sdpwu_if vif;
    uvm_analysis_port#(SdpwuItem) ap;

    // 时钟块里的 struct 成员直接用容易让 VCS 崩, 先整体取回局部变量
    SDPWU_FINISH_t fin_q;
    SDPWU_START_t  start_q;

    function new(string name = "SdpwuMon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual sdpwu_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdpwuMon: no virtual sdpwu_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        SdpwuItem tr;

        forever begin
            @(vif.mon);
            if (vif.rst_n !== 1'b1) begin
                continue;
            end


            // start 握手
            if ((vif.mon.sdmq_pw_valid === 1'b1) && (vif.mon.sdmq_pw_ready === 1'b1)) begin
                tr = SdpwuItem::type_id::create("tr");
                tr.kind     = SDPWU_START_SEEN;
                start_q     = SDPWU_START_t'(vif.mon.sdmq_pw_item);
                tr.pa       = start_q.pa;
                tr.sdmq_idx = start_q.sdmq_idx;
                ap.write(tr);
            end

            // 页表写口 (tb 布置页表)
            if (vif.mon.pw_mem_wen === 1'b1) begin
                tr = SdpwuItem::type_id::create("tr");
                tr.kind      = SDPWU_MEM_WR;
                tr.mem_addr  = vif.mon.pw_mem_waddr;
                tr.mem_wdata = vif.mon.pw_mem_wdata;
                ap.write(tr);
            end

            // 访存读请求
            if ((vif.mon.pw_mem_raddr_valid === 1'b1) && (vif.mon.pw_mem_raddr_ready === 1'b1)) begin
                tr = SdpwuItem::type_id::create("tr");
                tr.kind     = SDPWU_MEM_RD;
                tr.mem_addr = vif.mon.pw_mem_raddr;
                tr.mem_id   = vif.mon.pw_mem_raddr_id;
                ap.write(tr);
            end

            // Page Walk 结束
            if (vif.mon.pwu_finish_valid === 1'b1) begin
                fin_q = SDPWU_FINISH_t'(vif.mon.pwu_finish_item);
                tr = SdpwuItem::type_id::create("tr");
                tr.kind        = SDPWU_FINISH;
                tr.sdmq_idx    = fin_q.sdmq_idx;
                tr.finish_item = fin_q;
                ap.write(tr);
            end
        end
    endtask

endclass

`endif // _SDPWU_MON_SV_
