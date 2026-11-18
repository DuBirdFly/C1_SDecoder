`ifndef _SDTLB_MON_SV_
`define _SDTLB_MON_SV_

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

    // 本拍是否有任何一个 CAM 端口在发请求
    function automatic bit any_cam_req();
        bit any = 1'b0;
        for (int unsigned cam = 0; cam < SDTLB_CAM_NUM; cam++) begin
            any |= (vif.mon.cam_req_en[cam] === 1'b1);
        end
        return any;
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
                if (any_cam_req() ||
                    (vif.mon.fill_en === 1'b1) ||
                    (vif.mon.inv_all === 1'b1) || (vif.mon.inv_sel === 1'b1)) begin
                    tr = SdtlbItem::type_id::create("tr");
                    tr.cam_req_en       = vif.mon.cam_req_en;
                    tr.cam_req_pa       = vif.mon.cam_req_pa;
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
            end
        end
    endtask

    // 这个 item 里是否有任何一个 CAM 端口在发请求
    function automatic bit item_any_cam_req(SdtlbItem tr);
        bit any = 1'b0;
        foreach (tr.cam_req_en[i]) begin
            any |= tr.cam_req_en[i];
        end
        return any;
    endfunction

    // 事务合法性检查 (地址空间 + 端口冲突)
    function void check_item(SdtlbItem tr);
        // 装填与查表不能同拍 (Latch 不支持同拍读写, 见 sdtlb 的 a_cam_req_fill_exclusive)
        if (tr.fill_en) begin
            for (int unsigned cam = 0; cam < SDTLB_CAM_NUM; cam++) begin
                if (tr.cam_req_en[cam]) begin
                    `uvm_warning(
                        "FILL_CAM",
                        $sformatf("装填与查表同拍: fill_pa_base=0x%0h, cam%0d 同时在查表",
                                  tr.fill_pa_base, cam)
                    )
                end
            end
        end

        // PA[47] = 1 是 IO 空间, 不该进 SDecoder (只处理 Mem 空间)
        for (int unsigned cam = 0; cam < SDTLB_CAM_NUM; cam++) begin
            if (tr.cam_req_en[cam] && tr.cam_req_pa[cam][PA_WIDTH-1]) begin
                `uvm_warning(
                    "PA47",
                    $sformatf("cam%0d 请求地址在 IO 空间 (PA[47]=1): 0x%0h",
                              cam, tr.cam_req_pa[cam])
                )
            end
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
        tr.cam_hit = vif.mon.cam_hit;
        for (int unsigned cam = 0; cam < SDTLB_CAM_NUM; cam++) begin
            tr.cam_tag[cam]  = vif.mon.cam_hit_tag_item[cam];
            tr.cam_data[cam] = vif.mon.cam_hit_data_item[cam];
        end
    endfunction

endclass

`endif // _SDTLB_MON_SV_
