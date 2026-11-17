`ifndef _SDTLB_SEG_SEQ_SV_
`define _SDTLB_SEG_SEQ_SV_

// SDTLB 段式条目: 覆盖 [pa_base[4:0], pa_up] 的闭区间命中, 区间外不命中
class SdtlbSegSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbSegSeq)

    function new(string name = "SdtlbSegSeq");
        super.new(name);
    endfunction

    task body();
        // 段: 高位 12'h002, 页号 4 到 8
        fill(
            .base   (gen_pa_base(.high(12'h002), .idx(5'd4))),
            .up     (5'd8),
            .eid    (11'h0aa),
            .tok    (11'h155),
            .tokv   (10'h2aa),
            .pfn    (18'h15555)
        );
        wait_cycles(.n(4));

        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd4))));     // 左端
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd6))));     // 中间
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd8))));     // 右端
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd3))));     // 左端外
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd9))));     // 右端外
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h003), .idx(5'd6))));     // 段高位不同
        wait_cycles(.n(2));
        cam_req_single(.cam_num(1'b0), .pa(gen_pa(.high(12'h002), .idx(5'd6), .offset(30'h10))));  // 段内带页内偏移
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_SEG_SEQ_SV_
