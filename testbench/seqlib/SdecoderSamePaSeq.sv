`ifndef _SDECODER_SAME_PA_SEQ_SV_
`define _SDECODER_SAME_PA_SEQ_SV_

// 同 PA 连续请求: TLB 空时先连发 4 个相同 PA, 再发第 5 个.
// 用于验证 fill 去重: 前 4 个 miss 结果只能留下一个有效条目, 第 5 个应命中.
class SdecoderSamePaSeq extends uvm_sequence#(SdecoderItem);

    `uvm_object_utils(SdecoderSamePaSeq)

    localparam logic [PA_WIDTH-1:0] PA_A = 48'h0000_0000_1234;

    function new(string name = "SdecoderSamePaSeq");
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

    task send_wait(input int unsigned cycles);
        SdecoderItem tr;
        tr = SdecoderItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDEC_WAIT;
        tr.wait_cycles = cycles;
        finish_item(tr);
    endtask

    task body();
        // 一级表基地址; 不配的话 SDT_L1_BASE 复位值是 0, walk 会读到错误的表
        send_cfg(ADDR_SDT_L1_BASE, 64'h0000_0000_0000_1000);

        // TLB 空: 4 个同 PA 请求背靠背, 4 次 walk 都应在 fill 去重后落到同一条目
        send_req(PA_A, 8'hA1);
        send_req(PA_A, 8'hA2);
        send_req(PA_A, 8'hA3);
        send_req(PA_A, 8'hA4);

        // 等 4 个响应和 fill 完成, 再发第 5 个; 这时应命中唯一表项
        send_wait(2000);
        send_req(PA_A, 8'hA5);
        send_wait(500);
    endtask

endclass

`endif // _SDECODER_SAME_PA_SEQ_SV_
