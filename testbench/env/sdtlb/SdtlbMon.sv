`ifndef _SDTLB_MON_SV_
`define _SDTLB_MON_SV_

class SdtlbMon extends uvm_monitor;

    `uvm_component_utils(SdtlbMon)

    virtual sdtlb_if_probe vif;
    uvm_analysis_port#(SdtlbItem) ap;

    // 上一拍留下、本拍带响应发布的事件
    SdtlbItem pend[$];

    // 上一拍是否有装填请求 (本拍就是写阵列拍)
    bit fill_en_d;

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

                // 2) 采样本拍的输入, 压进队列 (一个 item 描述这一拍)
                //    每一拍都发: scoreboard 的参考模型按拍推进 (装填是 2 拍流水)
                begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.cam0_req_en = (vif.mon.cam0_req_en === 1'b1);
                    tr.cam0_req_pa = vif.mon.cam0_req_pa;
                    tr.cam1_req_en = (vif.mon.cam1_req_en === 1'b1);
                    tr.cam1_req_pa = vif.mon.cam1_req_pa;
                    tr.fill_en          = (vif.mon.fill_en === 1'b1);
                    tr.fill_pa_base     = vif.mon.fill_pa_base;
                    tr.fill_pa_up       = vif.mon.fill_pa_up;
                    tr.fill_eid         = vif.mon.fill_eid;
                    tr.fill_token_id    = vif.mon.fill_token_id;
                    tr.fill_token_value = vif.mon.fill_token_value;
                    tr.fill_s_pfn       = vif.mon.fill_s_pfn;
                    tr.inv_en     = (vif.mon.inv_en === 1'b1);
                    tr.inv_all    = (vif.mon.inv_all === 1'b1);
                    tr.inv_sel    = (vif.mon.inv_sel === 1'b1);
                    tr.inv_sel_pa = vif.mon.inv_sel_pa;
                    check_item(tr);
                    pend.push_back(tr);
                end

                fill_en_d = (vif.mon.fill_en === 1'b1);
            end
        end
    endtask

    // 事务合法性检查 (地址空间 + 端口冲突)
    function void check_item(SdtlbItem tr);
        // 写阵列那一拍不能查表 (Latch 不支持同拍读写, 见 sdtlb 的 a_camN_req_fill_exclusive);
        // 装填请求是上一拍发的, 这一拍才写阵列
        if (fill_en_d && (tr.cam0_req_en || tr.cam1_req_en)) begin
            `uvm_warning(
                "FILL_CAM",
                $sformatf("写阵列拍与查表同拍: cam0_req_en=%0b, cam1_req_en=%0b",
                          tr.cam0_req_en, tr.cam1_req_en)
            )
        end

        // PA[47] = 1 是 IO 空间, 不该进 SDecoder (只处理 Mem 空间)
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
        if (tr.fill_en && tr.fill_pa_base[PA_BASE_WIDTH-1]) begin
            `uvm_warning(
                "PA47",
                $sformatf("装填地址在 IO 空间 (PA[47]=1): 0x%0h", tr.fill_pa_base)
            )
        end
        if (tr.inv_sel && tr.inv_sel_pa[PA_BASE_WIDTH-1]) begin
            `uvm_warning(
                "PA47",
                $sformatf("置无效地址在 IO 空间 (PA[47]=1): 0x%0h", tr.inv_sel_pa)
            )
        end
    endfunction

    // 把当前采样到的响应回填到上一拍的请求上
    function void fill_rsp(SdtlbItem tr);
        tr.cam0_hit  = vif.mon.cam0_hit;
        tr.cam0_tag  = vif.mon.cam0_hit_tag_item;
        tr.cam0_data = vif.mon.cam0_hit_data_item;
        tr.cam1_hit  = vif.mon.cam1_hit;
        tr.cam1_tag  = vif.mon.cam1_hit_tag_item;
        tr.cam1_data = vif.mon.cam1_hit_data_item;
    endfunction

endclass

`endif // _SDTLB_MON_SV_
