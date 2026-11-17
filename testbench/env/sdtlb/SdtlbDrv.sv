`ifndef _SDTLB_DRV_SV_
`define _SDTLB_DRV_SV_

// SDTLB 的 driver: 把 SdtlbItem 变成 sdtlb_if 上的激励
//   约定: 每个 item 占 1 拍 (req_en / fill_en / inv_* 都只打 1 拍), 响应由 monitor 采集
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
        vif.drv.cam0_req_en      <= 1'b0;
        vif.drv.cam0_req_pa      <= '0;
        vif.drv.cam1_req_en      <= 1'b0;
        vif.drv.cam1_req_pa      <= '0;
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
                case (req.kind)
                    SDTLB_REQ:  drive_req(req);
                    SDTLB_FILL: drive_fill(req);
                    SDTLB_INV:  drive_inv(req);
                    SDTLB_WAIT: drive_wait(req);
                    default:    `uvm_error("KIND", "unknown SdtlbItem kind")
                endcase

                rsp = SdtlbItem::type_id::create("rsp");
                rsp.copy(req);
                rsp.set_id_info(req);
                seq_item_port.put_response(rsp);
                seq_item_port.item_done();
            end
        end
    endtask

    // 查表: 两端口可以同拍, 使能只打 1 拍
    // 同拍 inv_all / inv_sel 与查表一起打: 请求看到的是置无效之前的状态 (hit 由旧 valid 决定)
    task drive_req(SdtlbItem tr);
        vif.drv.inv_en           <= tr.inv_all | tr.inv_sel;
        vif.drv.inv_all          <= tr.inv_all;
        vif.drv.inv_sel          <= tr.inv_sel;
        vif.drv.inv_sel_pa       <= tr.inv_sel_pa;
        vif.drv.cam0_req_en <= tr.cam0_req_en;
        vif.drv.cam0_req_pa <= tr.cam0_req_pa;
        vif.drv.cam1_req_en <= tr.cam1_req_en;
        vif.drv.cam1_req_pa <= tr.cam1_req_pa;
        @(vif.drv);
        vif.drv.cam0_req_en <= 1'b0;
        vif.drv.cam1_req_en <= 1'b0;
        vif.drv.inv_en      <= 1'b0;
        vif.drv.inv_all     <= 1'b0;
        vif.drv.inv_sel     <= 1'b0;
    endtask

    // 同拍 inv_all / inv_sel 与 fill 一起打, 用来验证"置无效优先"
    task drive_fill(SdtlbItem tr);
        vif.drv.inv_en           <= tr.inv_all | tr.inv_sel;
        vif.drv.inv_all          <= tr.inv_all;
        vif.drv.inv_sel          <= tr.inv_sel;
        vif.drv.inv_sel_pa       <= tr.inv_sel_pa;
        vif.drv.fill_pa_base     <= tr.fill_pa_base;
        vif.drv.fill_pa_up       <= tr.fill_pa_up;
        vif.drv.fill_eid         <= tr.fill_eid;
        vif.drv.fill_token_id    <= tr.fill_token_id;
        vif.drv.fill_token_value <= tr.fill_token_value;
        vif.drv.fill_s_pfn       <= tr.fill_s_pfn;
        vif.drv.fill_en          <= 1'b1;
        @(vif.drv);
        vif.drv.fill_en          <= 1'b0;
        vif.drv.inv_en           <= 1'b0;
        vif.drv.inv_all          <= 1'b0;
        vif.drv.inv_sel          <= 1'b0;
    endtask

    task drive_inv(SdtlbItem tr);
        vif.drv.inv_en     <= 1'b1;
        vif.drv.inv_all    <= tr.inv_all;
        vif.drv.inv_sel    <= tr.inv_sel;
        vif.drv.inv_sel_pa <= tr.inv_sel_pa;
        @(vif.drv);
        vif.drv.inv_en     <= 1'b0;
        vif.drv.inv_all    <= 1'b0;
        vif.drv.inv_sel    <= 1'b0;
    endtask

    task drive_wait(SdtlbItem tr);
        repeat (tr.wait_cycles) @(vif.drv);
    endtask

endclass

`endif // _SDTLB_DRV_SV_
