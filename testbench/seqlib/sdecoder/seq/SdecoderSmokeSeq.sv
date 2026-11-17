`ifndef _SDECODER_SMOKE_SEQ_SV_
`define _SDECODER_SMOKE_SEQ_SV_

class SdecoderSmokeSeq extends uvm_sequence#(SdecoderItem);

    `uvm_object_utils(SdecoderSmokeSeq)

    function new(string name = "SdecoderSmokeSeq");
        super.new(name);
    endfunction

    task body();
        // TODO: 目前仅留骨架
    endtask

endclass

`endif // _SDECODER_SMOKE_SEQ_SV_
