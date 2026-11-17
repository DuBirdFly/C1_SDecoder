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
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'hfff), .idx(5'h1f))));
        wait_cycles(.n(4));

        // 装填 0xffff_ffe0 这一页 (段基地址 = {12'hfff, 5'h1f}, 只覆盖一页)
        fill(
            .base   (gen_pa_base(.high(12'hfff), .idx(5'h1f))),
            .up     (5'h1f),
            .eid    (11'h7ff),
            .tok    (11'h7ff),
            .tokv   (10'h155),
            .pfn    (18'h33333)
        );
        wait_cycles(.n(4));

        // 命中: Tag / Data 都应为装填进去的内容
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'hfff), .idx(5'h1f))));
        wait_cycles(.n(4));

        // 相邻页 (页号不同) 不命中
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'hfff), .idx(5'h1e))));
        wait_cycles(.n(4));

        // 页内偏移不影响命中
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'hfff), .idx(5'h1f), .offset(30'h3f0))));
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_SMOKE_SEQ_SV_
