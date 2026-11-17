`ifndef _SDPWU_TABLE_SEQ_SV_
`define _SDPWU_TABLE_SEQ_SV_

// 布置页表: 把 test 准备好的 (地址, 条目字) 列表逐个写进存储器模型
class SdpwuTableSeq extends SdpwuBaseSeq;

    `uvm_object_utils(SdpwuTableSeq)

    logic [PA_WIDTH-1:0]    addrs[$];
    logic [127:0]           words[$];

    function new(string name = "SdpwuTableSeq");
        super.new(name);
    endfunction

    task body();
        foreach (addrs[i]) begin
            mem_write(.addr(addrs[i]), .data(words[i]));
        end
    endtask

endclass

`endif // _SDPWU_TABLE_SEQ_SV_
