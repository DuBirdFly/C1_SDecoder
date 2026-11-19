`ifndef _SDTLB_INV_SEQ_SV_
`define _SDTLB_INV_SEQ_SV_

// SDTLB 置无效: 按地址只清被覆盖的条目, inv_all 清所有条目, 清完可重新装填
class SdtlbInvSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbInvSeq)

    function new(string name = "SdtlbInvSeq");
        super.new(name);
    endfunction

    task body();
        SdtlbItem item;

        // 一条页式 (高位 12'h010 页号 20) + 一条段式 (高位 12'h020 页号 4..8)
        fill(
            .base   (gen_pa_base(.high(12'h010), .idx(5'd20))),
            .up     (5'd20),
            .eid    (11'h001),
            .tok    (11'h002),
            .tokv   (10'h003),
            .pfn    (18'h0e0e0)
        );
        wait_cycles(.n(2));
        fill(
            .base   (gen_pa_base(.high(12'h020), .idx(5'd4))),
            .up     (5'd8),
            .eid    (11'h004),
            .tok    (11'h005),
            .tokv   (10'h006),
            .pfn    (18'h0f0f0)
        );
        wait_cycles(.n(4));

        // 段内中间地址置无效: 段条目被清, 页式条目不受影响
        inv_sel(.pa(gen_pa_base(.high(12'h020), .idx(5'd6))));
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h020), .idx(5'd6))));
        wait_cycles(.n(2));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h010), .idx(5'd20))));
        wait_cycles(.n(4));

        // 重新装填后可命中, 数据是新的
        fill(
            .base   (gen_pa_base(.high(12'h020), .idx(5'd4))),
            .up     (5'd8),
            .eid    (11'h007),
            .tok    (11'h008),
            .tokv   (10'h009),
            .pfn    (18'h0a0a0)
        );
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h020), .idx(5'd6))));
        wait_cycles(.n(4));

        // inv_all: 全部条目不再命中
        inv_all();
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h020), .idx(5'd6))));
        wait_cycles(.n(2));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h010), .idx(5'd20))));
        wait_cycles(.n(4));

        // inv_all 后重新装填可命中
        fill(
            .base   (gen_pa_base(.high(12'h010), .idx(5'd20))),
            .up     (5'd20),
            .eid    (11'h00a),
            .tok    (11'h00b),
            .tokv   (10'h00c),
            .pfn    (18'h0b0b0)
        );
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h010), .idx(5'd20))));
        wait_cycles(.n(4));

        // 同拍 查表 + inv_sel: 请求按置无效之前的状态算 (命中), 之后同一地址不再命中
        item = new_item();
        set_cam0(item, gen_pa(.high(12'h020), .idx(5'd6)));
        set_inv_sel(item, gen_pa_base(.high(12'h020), .idx(5'd6)));
        send(item);
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h020), .idx(5'd6))));
        wait_cycles(.n(4));

        // 同拍 查表 + inv_all: 请求同样看到置无效之前的状态
        item = new_item();
        set_cam0(item, gen_pa(.high(12'h010), .idx(5'd20)));
        set_inv_all(item);
        send(item);
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h010), .idx(5'd20))));
        wait_cycles(.n(4));

        // 同拍 fill + inv_sel: 置无效优先, 这次装填的地址不应命中, 别的条目不受影响
        //   先填一条 0x050 的条目 (落在最低位空闲条目), 再用同拍 fill + inv_sel 去填/清 0x051
        fill(
            .base   (gen_pa_base(.high(12'h050), .idx(5'd4))),
            .up     (5'd4),
            .eid    (11'h0e0),
            .tok    (11'h0e1),
            .tokv   (10'h0e2),
            .pfn    (18'h0e0e0)
        );
        wait_cycles(.n(2));
        item = new_item();
        set_fill(item, gen_pa_base(.high(12'h051), .idx(5'd4)), 5'd4,
                 11'h0f0, 11'h0f1, 10'h0f2, 18'h0f0f0);
        set_inv_sel(item, gen_pa_base(.high(12'h051), .idx(5'd4)));
        send(item);
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h051), .idx(5'd4))));
        wait_cycles(.n(2));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h050), .idx(5'd4))));
        wait_cycles(.n(4));

        // 同拍 fill + inv_all: 置无效优先, 这次装填的地址不应命中
        item = new_item();
        set_fill(item, gen_pa_base(.high(12'h040), .idx(5'd7)), 5'd7,
                 11'h0d0, 11'h0d1, 10'h0d2, 18'h0d0d0);
        set_inv_all(item);
        send(item);
        wait_cycles(.n(4));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h040), .idx(5'd7))));
        wait_cycles(.n(2));
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h010), .idx(5'd20))));
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_INV_SEQ_SV_
