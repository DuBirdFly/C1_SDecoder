`ifndef _SDECODER_SMOKE_SEQ_SV_
`define _SDECODER_SMOKE_SEQ_SV_

class SdecoderSmokeSeq extends uvm_sequence#(SdecoderItem);

    `uvm_object_utils(SdecoderSmokeSeq)

    localparam logic [PA_WIDTH-1:0] PA_A = 48'h0000_0000_1234;
    localparam logic [PA_WIDTH-1:0] PA_B = 48'h0000_4000_5678;
    localparam logic [PA_WIDTH-1:0] PA_S = 48'h0009_8000_0111;

    function new(string name = "SdecoderSmokeSeq");
        super.new(name);
    endfunction

    task send_cfg(
        input logic [SDIOR_ADDR_WIDTH-1:0] addr,
        input logic [SDIOR_DATA_WIDTH-1:0] data
    );
        SdecoderItem tr;
        tr = SdecoderItem::type_id::create("tr");
        start_item(tr);
        tr.kind      = SDEC_CFG_WR;
        tr.cfg_addr  = addr;
        tr.cfg_wdata = data;
        finish_item(tr);
    endtask

    task send_req(
        input logic [PA_WIDTH-1:0]      pa,
        input logic [REQ_ID_WIDTH-1:0]  id
    );
        SdecoderItem tr;
        tr = SdecoderItem::type_id::create("tr");
        start_item(tr);
        tr.kind = SDEC_REQ;
        tr.pa   = pa;
        tr.id   = id;
        finish_item(tr);
    endtask

    task send_rsp_ready(input bit value);
        SdecoderItem tr;
        tr = SdecoderItem::type_id::create("tr");
        start_item(tr);
        tr.kind      = SDEC_RSP_READY;
        tr.rsp_ready = value;
        finish_item(tr);
    endtask

    task send_wait(input int unsigned cycles);
        SdecoderItem tr;
        tr = SdecoderItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDEC_WAIT;
        tr.wait_cycles = cycles;
        finish_item(tr);
    endtask

    task body();
        // 一级表基地址
        send_cfg(ADDR_SDT_L1_BASE, 64'h0000_0000_0000_1000);

        // A miss / hit
        send_req(PA_A, 8'h11);
        send_wait(500);
        send_req(PA_A, 8'h12);

        // B miss / hit
        send_req(PA_B, 8'h21);
        send_wait(500);
        send_req(PA_B, 8'h22);

        // 段 miss / hit (PA_S 落在段 [4,8] 内)
        send_req(PA_S, 8'h61);
        send_wait(500);
        send_req(PA_S, 8'h62);

        // 置无效 A (1GB 对界, PA_A 的页基址为 0), 然后 A miss + B hit
        send_cfg(ADDR_SDECODER_IS, 64'h8000_0000_0000_0000);
        send_req(PA_A, 8'h31);
        send_req(PA_B, 8'h32);

        // 先让前面几个响应被取走, 避免反压阶段 A41 请求被卡住
        send_wait(2000);

        // 反压: 不取响应, 发一个 A hit
        send_rsp_ready(1'b0);
        send_req(PA_A, 8'h41);
        send_wait(100);
        send_rsp_ready(1'b1);

        // 全部置无效, A 重新 miss / hit
        send_cfg(ADDR_SDECODER_IA, 64'h1);
        send_req(PA_A, 8'h51);
        send_wait(500);
        send_req(PA_A, 8'h52);
    endtask

endclass

`endif // _SDECODER_SMOKE_SEQ_SV_
