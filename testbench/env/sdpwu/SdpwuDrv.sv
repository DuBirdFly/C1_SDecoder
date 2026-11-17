`ifndef _SDPWU_DRV_SV_
`define _SDPWU_DRV_SV_

// SDPWU_TOP 的 driver: 只扮演 SDMQ (发 Page Walk 请求) 和"布置页表"的写口
//   存储器本身的读写行为由 tb 里的 sdpwu_mem_model 模块负责, 不再放在 driver 里
class SdpwuDrv extends uvm_driver#(SdpwuItem);

    `uvm_component_utils(SdpwuDrv)

    virtual sdpwu_if        vif;
    logic [PA_WIDTH-1:0]    l1_base_val = 48'h0000_1000_0000;   // 由 env 注入

    function new(string name = "SdpwuDrv", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual sdpwu_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdpwuDrv: no virtual sdpwu_if")
        end
    endfunction

    task signal_reset();
        vif.l1_base        = '0;
        vif.sdmq_pw_valid  = 1'b0;
        vif.sdmq_pw_item   = '0;
        vif.pw_mem_wen     = 1'b0;
        vif.pw_mem_waddr   = '0;
        vif.pw_mem_wdata   = '0;

        do @(vif.drv); while (vif.rst_n !== 1'b1);
        repeat (5) @(vif.drv);
        vif.l1_base = l1_base_val;
    endtask

    task run_phase(uvm_phase phase);
        SdpwuItem rsp;

        signal_reset();

        forever begin
            seq_item_port.try_next_item(req);

            if (req == null) begin
                @(vif.drv);
            end
            else begin
                case (req.kind)
                    SDPWU_PW_START: drive_pw_start(req);
                    SDPWU_MEM_WR:   drive_mem_wr(req);
                    SDPWU_WAIT:     repeat (req.wait_cycles) @(vif.drv);
                    default:        `uvm_error("KIND", "unknown SdpwuItem kind")
                endcase

                rsp = SdpwuItem::type_id::create("rsp");
                rsp.copy(req);
                rsp.set_id_info(req);
                seq_item_port.put_response(rsp);
                seq_item_port.item_done();
            end
        end
    endtask

    // start 握手: valid 保持到 ready
    task drive_pw_start(SdpwuItem tr);
        SDPWU_START_t start_q;
        start_q.pa       = tr.pa;
        start_q.sdmq_idx = tr.sdmq_idx;
        vif.sdmq_pw_valid = 1'b1;
        vif.sdmq_pw_item  = start_q;
        do @(vif.drv); while (vif.drv.sdmq_pw_ready !== 1'b1);
        vif.sdmq_pw_valid = 1'b0;
        @(vif.drv);
    endtask

    // 写一个页表条目 (一拍)
    task drive_mem_wr(SdpwuItem tr);
        vif.pw_mem_wen   = 1'b1;
        vif.pw_mem_waddr = tr.mem_addr;
        vif.pw_mem_wdata = tr.mem_wdata;
        @(vif.drv);
        vif.pw_mem_wen   = 1'b0;
    endtask

endclass

`endif // _SDPWU_DRV_SV_
