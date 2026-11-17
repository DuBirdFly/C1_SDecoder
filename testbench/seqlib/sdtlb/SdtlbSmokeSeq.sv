`ifndef _SDTLB_SMOKE_SEQ_SV_
`define _SDTLB_SMOKE_SEQ_SV_

// SDTLB smoke: 空表不命中 -> 装填页式条目 -> 命中且数据正确 -> 相邻页不命中
class SdtlbSmokeSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbSmokeSeq)

    function new(string name = "SdtlbSmokeSeq");
        super.new(name);
    endfunction

    task body();
        // 空表: 不命中
        req0(pa_of(12'hfff, 5'h1f));
        wait_cycles(4);

        // 装填 0xffff_ffe0 这一页 (段基地址 = {12'hfff, 5'h1f}, 只覆盖一页)
        fill(base_of(12'hfff, 5'h1f), 5'h1f, 11'h7ff, 11'h7ff, 10'h155, 18'h33333);
        wait_cycles(4);

        // 命中: Tag / Data 都应为装填进去的内容
        req0(pa_of(12'hfff, 5'h1f));
        wait_cycles(4);

        // 相邻页 (页号不同) 不命中
        req0(pa_of(12'hfff, 5'h1e));
        wait_cycles(4);

        // 页内偏移不影响命中
        req0(pa_of(12'hfff, 5'h1f, 30'h3f0));
        wait_cycles(4);
    endtask

endclass

`endif // _SDTLB_SMOKE_SEQ_SV_
