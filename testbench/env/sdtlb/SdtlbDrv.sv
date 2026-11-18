`ifndef _SDTLB_DRV_SV_
`define _SDTLB_DRV_SV_

class SdtlbDrv extends uvm_driver#(SdtlbItem);

    `uvm_component_utils(SdtlbDrv)

    virtual sdtlb_if vif;

    function new(string name = "SdtlbDrv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdtlb_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdtlbDrv: no virtual sdtlb_if")
        end
    endfunction

    // 复位期间把接口输入拉低, 等复位释放
    task signal_reset();
        vif.drv.cam_req_en      <= '{default: 1'b0};
        vif.drv.cam_req_pa      <= '{default: '0};
        vif.drv.fill_en          <= 1'b0;
        vif.drv.fill_pa_base     <= '0;
        vif.drv.fill_pa_up       <= '0;
        vif.drv.fill_eid         <= '0;
        vif.drv.fill_token_id    <= '0;
        vif.drv.fill_token_value <= '0;
        vif.drv.fill_s_pfn       <= '0;
        vif.drv.inv_en           <= 1'b0;
        vif.drv.inv_all          <= 1'b0;
        vif.drv.inv_sel          <= 1'b0;
        vif.drv.inv_sel_pa       <= '0;

        do @(vif.drv); while (vif.rst_n !== 1'b1);
        repeat (5) @(vif.drv);
    endtask

    task run_phase(uvm_phase phase);
        SdtlbItem rsp;

        signal_reset();

        forever begin
            seq_item_port.try_next_item(req);

            if (req == null) begin
                @(vif.drv);
            end
            else begin
                fork
                    cam_req_drive(req);
                    fill_drive(req);
                    inv_drive(req);
                    wait_drive(req);
                join

                rsp = SdtlbItem::type_id::create("rsp");
                rsp.copy(req);
                rsp.set_id_info(req);
                seq_item_port.put_response(rsp);
                seq_item_port.item_done();
            end
        end
    endtask

    // 所有 CAM 端口的请求在同拍一起发, 保持一拍后统一撤
    task cam_req_drive(SdtlbItem tr);
        bit any_req;
        any_req = 1'b0;
        foreach (tr.cam_req_en[i]) begin
            any_req |= tr.cam_req_en[i];
        end
        if (any_req) begin
            vif.drv.cam_req_en <= tr.cam_req_en;
            vif.drv.cam_req_pa <= tr.cam_req_pa;
            @(vif.drv);
            vif.drv.cam_req_en <= '{default: 1'b0};
        end
    endtask

    task fill_drive(SdtlbItem tr);
        if (tr.fill_en) begin
            vif.drv.fill_pa_base     <= tr.fill_pa_base;
            vif.drv.fill_pa_up       <= tr.fill_pa_up;
            vif.drv.fill_eid         <= tr.fill_eid;
            vif.drv.fill_token_id    <= tr.fill_token_id;
            vif.drv.fill_token_value <= tr.fill_token_value;
            vif.drv.fill_s_pfn       <= tr.fill_s_pfn;
            vif.drv.fill_en          <= 1'b1;
            @(vif.drv);
            vif.drv.fill_en          <= 1'b0;
        end
    endtask

    task inv_drive(SdtlbItem tr);
        if (tr.inv_all || tr.inv_sel) begin
            vif.drv.inv_en     <= 1'b1;
            vif.drv.inv_all    <= tr.inv_all;
            vif.drv.inv_sel    <= tr.inv_sel;
            vif.drv.inv_sel_pa <= tr.inv_sel_pa;
            @(vif.drv);
            vif.drv.inv_en     <= 1'b0;
            vif.drv.inv_all    <= 1'b0;
            vif.drv.inv_sel    <= 1'b0;
        end
    endtask

    task wait_drive(SdtlbItem tr);
        if (tr.wait_cycles_en) begin
            repeat (tr.wait_cycles) @(vif.drv);
        end
    endtask

endclass

`endif // _SDTLB_DRV_SV_
