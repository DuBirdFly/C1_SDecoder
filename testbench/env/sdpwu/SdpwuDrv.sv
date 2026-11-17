`ifndef _SDPWU_DRV_SV_
`define _SDPWU_DRV_SV_

// SDPWU_TOP 的 driver: 同时扮演 SDMQ (发 Page Walk 请求) 和外部存储器 (响应读请求)
class SdpwuDrv extends uvm_driver#(SdpwuItem);

    `uvm_component_utils(SdpwuDrv)

    virtual sdpwu_if      vif;
    page_table_model      pt_model;     // 由 env 注入
    logic [PA_WIDTH-1:0]  l1_base_val = '0;     // 由 env 注入
    SDPWU_START_t         start_q;              // start_item 的打包视图

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
        vif.l1_base = '0;
        vif.sdmq_pw_valid = 1'b0;
        vif.sdmq_pw_item = '0;
        vif.pw_mem_raddr_ready = 1'b0;
        vif.pw_mem_rdata = '0;
        vif.pw_mem_rdata_id = '0;
        vif.pw_mem_rdata_valid = 1'b0;
        vif.pw_mem_rdata_err = '0;

        do @(vif.drv); while (vif.rst_n !== 1'b1);
        repeat (5) @(vif.drv);
    endtask

    task run_phase(uvm_phase phase);
        signal_reset();

        // 存储器: 读地址通道的 ready 常高, 收到请求后下一拍回读数据
        fork
            memory_respond();
            pw_start_loop();
        join
    endtask

    // 扮演外部存储器: 读地址通道 ready 常高, 收到请求的下一拍回数据
    task memory_respond();
        forever begin
            @(vif.drv);
            vif.l1_base            = l1_base_val;
            vif.pw_mem_raddr_ready = 1'b1;
            vif.pw_mem_rdata_valid = 1'b0;      // 先撤上一拍的读数据
            if (vif.drv.pw_mem_raddr_valid === 1'b1) begin
                // 请求拍采到, 本拍立刻给数据; 保持到 DUT 在 RD_DATA 采样 (rdata_ready)
                vif.pw_mem_rdata       = pt_model.read_word(vif.drv.pw_mem_raddr);
                vif.pw_mem_rdata_id    = vif.drv.pw_mem_raddr_id;
                vif.pw_mem_rdata_err   = '0;
                vif.pw_mem_rdata_valid = 1'b1;
                do @(vif.drv); while (vif.drv.pw_mem_rdata_ready !== 1'b1);
                vif.pw_mem_rdata_valid = 1'b0;
            end
        end
    endtask

    // 扮演 SDMQ: 按序列发 Page Walk 请求
    task pw_start_loop();
        SdpwuItem rsp;

        forever begin
            seq_item_port.try_next_item(req);

            if (req == null) begin
                @(vif.drv);
            end
            else begin
                if (req.kind == SDPWU_PW_START) begin
                    drive_pw_start(req);
                end
                else begin
                    repeat (req.wait_cycles) @(vif.drv);
                end

                rsp = SdpwuItem::type_id::create("rsp");
                rsp.copy(req);
                rsp.set_id_info(req);
                seq_item_port.put_response(rsp);
                seq_item_port.item_done();
            end
        end
    endtask

    // start 握手: valid 保持到 ready
    // 用阻塞赋值直接驱动接口信号: 时钟块输出的"拉高"和"拉低"若落在同一个时钟块事件上,
    // 后写的会覆盖先写的, valid 永远看不到 1
    task drive_pw_start(SdpwuItem tr);
        vif.sdmq_pw_valid = 1'b1;
        start_q.pa       = tr.pa;
        start_q.sdmq_idx = tr.sdmq_idx;
        vif.sdmq_pw_item = start_q;
        do @(vif.drv); while (vif.drv.sdmq_pw_ready !== 1'b1);
        vif.sdmq_pw_valid = 1'b0;
        @(vif.drv);
    endtask

endclass

`endif // _SDPWU_DRV_SV_
