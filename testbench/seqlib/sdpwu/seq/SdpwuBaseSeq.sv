`ifndef _SDPWU_BASE_SEQ_SV_
`define _SDPWU_BASE_SEQ_SV_

class SdpwuBaseSeq extends uvm_sequence#(SdpwuItem);

    `uvm_object_utils(SdpwuBaseSeq)

    function new(string name = "SdpwuBaseSeq");
        super.new(name);
    endfunction

    // 拼地址 {一级表索引 PA[46:35], 二级表索引 PA[34:30], 页内偏移 PA[29:0]}
    function automatic logic [PA_WIDTH-1:0] gen_pa(
        input logic [11:0]                          l1_idx,
        input logic [PA_UP_WIDTH-1:0]               up,
        input logic [PA_WIDTH-PA_BASE_WIDTH-1:0]    offset = '0
    );
        return {l1_idx, up, offset};
    endfunction

    // 发一次 Page Walk 请求
    task pw_start(input logic [PA_WIDTH-1:0] pa, input logic [SDMQ_IDX_WIDTH-1:0] sdmq_idx);
        SdpwuItem tr;
        tr = SdpwuItem::type_id::create("tr");
        start_item(tr);
        tr.kind     = SDPWU_PW_START;
        tr.pa       = pa;
        tr.sdmq_idx = sdmq_idx;
        finish_item(tr);
    endtask

    // 往存储器模型写一个 16B 条目 (布置页表)
    task mem_write(input logic [PA_WIDTH-1:0] addr, input logic [127:0] data);
        SdpwuItem tr;
        tr = SdpwuItem::type_id::create("tr");
        start_item(tr);
        tr.kind      = SDPWU_MEM_WR;
        tr.mem_addr  = addr;
        tr.mem_wdata = data;
        finish_item(tr);
    endtask

    task wait_cycles(input int unsigned n);
        SdpwuItem tr;
        tr = SdpwuItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDPWU_WAIT;
        tr.wait_cycles = n;
        finish_item(tr);
    endtask

endclass

`endif // _SDPWU_BASE_SEQ_SV_
