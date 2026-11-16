`ifndef _SDECODER_SMOKE_SEQ_SV_
`define _SDECODER_SMOKE_SEQ_SV_

class SdecoderSmokeSeq extends uvm_sequence#(SdecoderItem);

    `uvm_object_utils(SdecoderSmokeSeq)

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
        // TODO: 目前仅留骨架
    endtask

endclass

`endif // _SDECODER_SMOKE_SEQ_SV_
