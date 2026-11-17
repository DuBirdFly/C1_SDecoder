`ifndef _SDTLB_MON_SV_
`define _SDTLB_MON_SV_

// SDTLB 的 monitor: 观测 sdtlb_if_probe (bind 到 sdtlb 模块上的探针), 发布事务给 scoreboard
//   探针采的是 DUT 引脚, 所以不关心外面有没有 wrapper; 以后验 SDecoder 时同一个 bind 仍然有效.
//   时序: 命中在请求的下一拍输出, 所以请求拍之后第 1 个时钟块事件才采到响应; 这里用一个待发布
//   队列: 每拍先把上一拍留下的事件配上本拍采到的响应发出去, 再收本拍的输入事件,
//   这样 scoreboard 看到的事件顺序与 DUT 内部的处理顺序一致.
//
//   另外在观测到事务时检查地址合法性: PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间.
//   RTL 里有对应断言 (a_cam0/1_pa47_zero / a_fill_pa47_zero / a_inv_sel_pa47_zero),
//   这里给一条 UVM 侧的告警, 断言关掉时也能看到问题.
class SdtlbMon extends uvm_monitor;

    `uvm_component_utils(SdtlbMon)

    virtual sdtlb_if_probe vif;
    uvm_analysis_port#(SdtlbItem) ap;

    // 上一拍留下、本拍带响应发布的事件
    SdtlbItem pend[$];

    function new(string name = "SdtlbMon", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual sdtlb_if_probe)::get(this, "", "mon_vif", vif)) begin
            `uvm_fatal("NOVIF", "SdtlbMon: no virtual sdtlb_if_probe")
        end
    endfunction

    task run_phase(uvm_phase phase);
        SdtlbItem tr;

        forever begin
            @(vif.mon);

            if (vif.rst_n !== 1'b1) begin
                pend.delete();
            end
            else begin
                // 1) 发布上一拍的那批事件, 回填本拍采到的响应
                foreach (pend[i]) begin
                    fill_rsp(pend[i]);
                    ap.write(pend[i]);
                end
                pend.delete();

                // 2) 采样本拍的输入, 压进队列
                if ((vif.mon.cam0_req_en === 1'b1) || (vif.mon.cam1_req_en === 1'b1)) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.kind        = SDTLB_REQ;
                    tr.cam0_req_en = (vif.mon.cam0_req_en === 1'b1);
                    tr.cam0_req_pa = vif.mon.cam0_req_pa;
                    tr.cam1_req_en = (vif.mon.cam1_req_en === 1'b1);
                    tr.cam1_req_pa = vif.mon.cam1_req_pa;
                    check_space(tr);
                    pend.push_back(tr);
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
                    check_space(tr);
                    pend.push_back(tr);
                end
                if ((vif.mon.inv_all === 1'b1) || (vif.mon.inv_sel === 1'b1)) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.kind       = SDTLB_INV;
                    tr.inv_en     = (vif.mon.inv_en  === 1'b1);
                    tr.inv_all    = (vif.mon.inv_all === 1'b1);
                    tr.inv_sel    = (vif.mon.inv_sel === 1'b1);
                    tr.inv_sel_pa = vif.mon.inv_sel_pa;
                    check_space(tr);
                    pend.push_back(tr);
                end
            end
        end
    endtask

    // 地址合法性: PA[47] = 1 是 IO 空间, 不该进 SDecoder (只处理 Mem 空间)
    function void check_space(SdtlbItem tr);
        if (tr.kind == SDTLB_REQ) begin
            if (tr.cam0_req_en && tr.cam0_req_pa[PA_WIDTH-1]) begin
                `uvm_warning(
                    "PA47",
                    $sformatf("cam0 请求地址在 IO 空间 (PA[47]=1): 0x%0h", tr.cam0_req_pa)
                )
            end
            if (tr.cam1_req_en && tr.cam1_req_pa[PA_WIDTH-1]) begin
                `uvm_warning(
                    "PA47",
                    $sformatf("cam1 请求地址在 IO 空间 (PA[47]=1): 0x%0h", tr.cam1_req_pa)
                )
            end
        end
        else if (tr.kind == SDTLB_FILL) begin
            if (tr.fill_pa_base[PA_BASE_WIDTH-1]) begin
                `uvm_warning(
                    "PA47",
                    $sformatf("装填地址在 IO 空间 (PA[47]=1): 0x%0h", tr.fill_pa_base)
                )
            end
        end
        else if (tr.kind == SDTLB_INV) begin
            if (tr.inv_sel && tr.inv_sel_pa[PA_BASE_WIDTH-1]) begin
                `uvm_warning(
                    "PA47",
                    $sformatf("置无效地址在 IO 空间 (PA[47]=1): 0x%0h", tr.inv_sel_pa)
                )
            end
        end
    endfunction

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
