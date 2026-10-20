`ifndef _SDECODER_MON_SV_
`define _SDECODER_MON_SV_

class SdecoderMon extends uvm_monitor;

    `uvm_component_utils(SdecoderMon)

    virtual sdecoder_if vif;

    int rsp_count;
    int err_count;
    bit [255:0] seen;

    function new(string name = "SdecoderMon", uvm_component parent = null);
        super.new(name, parent);
        rsp_count = 0;
        err_count = 0;
        seen      = '0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdecoder_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdecoderMon: no virtual sdecoder_if")
        end
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(vif.mon);

            if (vif.mon.rsp_valid && vif.mon.rsp_ready) begin
                check_rsp();
            end

            // 响应 pending 且下游不取时, 顶层不应再收新请求
            if (vif.mon.rsp_valid && !vif.mon.rsp_ready && vif.mon.req_ready) begin
                err_count++;
                `uvm_error("BACKPRESSURE", "req_ready high while rsp_valid && !rsp_ready")
            end
        end
    endtask

    function void check_rsp();
        if (seen[vif.mon.rsp_id]) begin
            err_count++;
            `uvm_error("RSP_DUP", $sformatf("duplicate response id=0x%0h", vif.mon.rsp_id))
        end
        else begin
            seen[vif.mon.rsp_id] = 1'b1;
        end

        if (vif.mon.rsp_fcode !== 3'b000) begin
            err_count++;
            `uvm_error("RSP_FCODE",
                       $sformatf("id=0x%0h fcode=%0b", vif.mon.rsp_id, vif.mon.rsp_fcode))
        end

        case (vif.mon.rsp_id)
            8'h11, 8'h12, 8'h31, 8'h41, 8'h51, 8'h52,
            8'hA1, 8'hA2, 8'hA3, 8'hA4, 8'hA5: begin
                if (vif.mon.rsp_eid !== 11'h100) begin
                    err_count++;
                    `uvm_error("RSP_EID", $sformatf("A id=0x%0h eid=0x%0h", vif.mon.rsp_id, vif.mon.rsp_eid))
                end
                if (vif.mon.rsp_token_id !== 10'h200) begin
                    err_count++;
                    `uvm_error("RSP_TOKEN", $sformatf("A id=0x%0h token=0x%0h", vif.mon.rsp_id, vif.mon.rsp_token_id))
                end
                if (vif.mon.rsp_sla !== 48'h0000_4000_1234) begin
                    err_count++;
                    `uvm_error("RSP_SLA", $sformatf("A id=0x%0h sla=0x%0h", vif.mon.rsp_id, vif.mon.rsp_sla))
                end
            end
            8'h21, 8'h22, 8'h32: begin
                if (vif.mon.rsp_eid !== 11'h101) begin
                    err_count++;
                    `uvm_error("RSP_EID", $sformatf("B id=0x%0h eid=0x%0h", vif.mon.rsp_id, vif.mon.rsp_eid))
                end
                if (vif.mon.rsp_token_id !== 10'h201) begin
                    err_count++;
                    `uvm_error("RSP_TOKEN", $sformatf("B id=0x%0h token=0x%0h", vif.mon.rsp_id, vif.mon.rsp_token_id))
                end
                if (vif.mon.rsp_sla !== 48'h0000_8000_5678) begin
                    err_count++;
                    `uvm_error("RSP_SLA", $sformatf("B id=0x%0h sla=0x%0h", vif.mon.rsp_id, vif.mon.rsp_sla))
                end
            end
            8'h61, 8'h62: begin
                if (vif.mon.rsp_eid !== 11'h300) begin
                    err_count++;
                    `uvm_error("RSP_EID", $sformatf("S id=0x%0h eid=0x%0h", vif.mon.rsp_id, vif.mon.rsp_eid))
                end
                if (vif.mon.rsp_token_id !== 10'h300) begin
                    err_count++;
                    `uvm_error("RSP_TOKEN", $sformatf("S id=0x%0h token=0x%0h", vif.mon.rsp_id, vif.mon.rsp_token_id))
                end
                if (vif.mon.rsp_sla !== 48'h4000_8000_0111) begin
                    err_count++;
                    `uvm_error("RSP_SLA", $sformatf("S id=0x%0h sla=0x%0h", vif.mon.rsp_id, vif.mon.rsp_sla))
                end
            end
            default: begin
                err_count++;
                `uvm_error("RSP_ID", $sformatf("unknown response id=0x%0h", vif.mon.rsp_id))
            end
        endcase

        rsp_count++;
    endfunction

endclass

`endif // _SDECODER_MON_SV_
