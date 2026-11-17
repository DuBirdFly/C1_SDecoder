`ifndef _SDTLB_INV_SEQ_SV_
`define _SDTLB_INV_SEQ_SV_

// SDTLB 置无效: 按地址只清被覆盖的条目, inv_all 清所有条目, 清完可重新装填
class SdtlbInvSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbInvSeq)

    function new(string name = "SdtlbInvSeq");
        super.new(name);
    endfunction

    task body();
        // 一条页式 (高位 12'h010 页号 20) + 一条段式 (高位 12'h020 页号 4..8)
        fill(base_of(12'h010, 5'd20), 5'd20, 11'h001, 11'h002, 10'h003, 18'h0e0e0);
        wait_cycles(2);
        fill(base_of(12'h020, 5'd4), 5'd8, 11'h004, 11'h005, 10'h006, 18'h0f0f0);
        wait_cycles(4);

        // 段内中间地址置无效: 段条目被清, 页式条目不受影响
        inv_sel(base_of(12'h020, 5'd6));
        wait_cycles(4);
        req0(pa_of(12'h020, 5'd6));
        wait_cycles(2);
        req0(pa_of(12'h010, 5'd20));
        wait_cycles(4);

        // 重新装填后可命中, 数据是新的
        fill(base_of(12'h020, 5'd4), 5'd8, 11'h007, 11'h008, 10'h009, 18'h0a0a0);
        wait_cycles(4);
        req0(pa_of(12'h020, 5'd6));
        wait_cycles(4);

        // inv_all: 全部条目不再命中
        inv_all();
        wait_cycles(4);
        req0(pa_of(12'h020, 5'd6));
        wait_cycles(2);
        req0(pa_of(12'h010, 5'd20));
        wait_cycles(4);

        // inv_all 后重新装填可命中
        fill(base_of(12'h010, 5'd20), 5'd20, 11'h00a, 11'h00b, 10'h00c, 18'h0b0b0);
        wait_cycles(4);
        req0(pa_of(12'h010, 5'd20));
        wait_cycles(4);

        // 同拍 fill + inv_all: 置无效优先, 这次装填的地址不应命中
        fill_and_inv_all(base_of(12'h040, 5'd7), 5'd7, 11'h0d0, 11'h0d1, 10'h0d2, 18'h0d0d0);
        wait_cycles(4);
        req0(pa_of(12'h040, 5'd7));
        wait_cycles(2);
        req0(pa_of(12'h010, 5'd20));
        wait_cycles(4);
    endtask

endclass

`endif // _SDTLB_INV_SEQ_SV_
