`ifndef _SDTLB_MON_SV_
`define _SDTLB_MON_SV_

// SDTLB 的 monitor: 观测 sdtlb_if, 发布事务给 scoreboard
//   时序: wrapper_sdtlb 把输入打 1 拍, DUT 的命中再打 1 拍, 所以请求拍之后第 2 个时钟块
//   事件才采到响应; 这里用一个 2 段队列, 把每拍的输入事件延后 2 拍再发布, 发布时回填响应,
//   这样 scoreboard 看到的事件顺序与 DUT 内部的处理顺序一致.
class SdtlbMon extends uvm_monitor;

    `uvm_component_utils(SdtlbMon)

    virtual sdtlb_if vif;
    uvm_analysis_port#(SdtlbItem) ap;

    // 输入事件的两段延迟队列 (p1 是两拍前的, 本拍发布)
    SdtlbItem p0[$];
    SdtlbItem p1[$];

    function new(string name = "SdtlbMon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual sdtlb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdtlbMon: no virtual sdtlb_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        SdtlbItem tr;

        forever begin
            @(vif.mon);

            if (vif.rst_n !== 1'b1) begin
                p0.delete();
                p1.delete();
            end
            else begin
                // 1) 发布两拍前的那批事件, 回填本拍采到的响应
                foreach (p1[i]) begin
                    fill_rsp(p1[i]);
                    ap.write(p1[i]);
                end
                p1.delete();
                p1 = p0;
                p0.delete();

                // 2) 采样本拍的输入, 压进队列
                if ((vif.mon.cam0_req_en === 1'b1) || (vif.mon.cam1_req_en === 1'b1)) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.kind        = SDTLB_REQ;
                    tr.cam0_req_en = (vif.mon.cam0_req_en === 1'b1);
                    tr.cam0_req_pa = vif.mon.cam0_req_pa;
                    tr.cam1_req_en = (vif.mon.cam1_req_en === 1'b1);
                    tr.cam1_req_pa = vif.mon.cam1_req_pa;
                    p0.push_back(tr);
                end
                if (vif.mon.fill_en === 1'b1) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.kind             = SDTLB_FILL;
                    tr.fill_pa_base     = vif.mon.fill_pa_base;
                    tr.fill_pa_up       = vif.mon.fill_pa_up;
                    tr.fill_eid         = vif.mon.fill_eid;
                    tr.fill_token_id    = vif.mon.fill_token_id;
                    tr.fill_token_value = vif.mon.fill_token_value;
                    tr.fill_s_pfn       = vif.mon.fill_s_pfn;
                    p0.push_back(tr);
                end
                if ((vif.mon.inv_all === 1'b1) || (vif.mon.inv_sel === 1'b1)) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.kind       = SDTLB_INV;
                    tr.inv_all    = (vif.mon.inv_all === 1'b1);
                    tr.inv_sel    = (vif.mon.inv_sel === 1'b1);
                    tr.inv_sel_pa = vif.mon.inv_sel_pa;
                    p0.push_back(tr);
                end
            end
        end
    endtask

    // 把当前采样到的响应回填到两拍前的请求上
    function void fill_rsp(SdtlbItem tr);
        if (tr.kind != SDTLB_REQ) begin
            return;
        end
        tr.cam0_hit  = vif.mon.cam0_hit;
        tr.cam0_tag  = vif.mon.cam0_hit_tag_item;
        tr.cam0_data = vif.mon.cam0_hit_data_item;
        tr.cam1_hit  = vif.mon.cam1_hit;
        tr.cam1_tag  = vif.mon.cam1_hit_tag_item;
        tr.cam1_data = vif.mon.cam1_hit_data_item;
    endfunction

endclass

`endif // _SDTLB_MON_SV_
