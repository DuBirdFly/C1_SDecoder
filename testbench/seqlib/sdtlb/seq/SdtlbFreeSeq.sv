`ifndef _SDTLB_FREE_SEQ_SV_
`define _SDTLB_FREE_SEQ_SV_

// SDTLB 空闲优先: 表满之后清掉一条低位条目, 下一次装填必须复用这条空闲条目,
// 不能去淘汰轮转指针指向的条目 (那会白白丢掉一条还有用的映射).
//
// 这是 "空闲优先" 与 "纯轮转" 唯一可观测的差别: 表没满时两种策略填的位置一样,
// 只有表满且出现空闲条目时才分叉 —— 纯轮转会淘汰 0 号条目, 空闲优先会填 5 号.
class SdtlbFreeSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbFreeSeq)

    function new(string name = "SdtlbFreeSeq");
        super.new(name);
    endfunction

    // 第 i 条测试条目的段基地址 (PA[47:30]) 与查表地址 (PA[47:0])
    function automatic logic [PA_BASE_WIDTH-1:0] gen_base(input int unsigned i);
        return gen_pa_base(
            .high   (12'h200 + 12'(i / 32)),
            .idx    (5'(i % 32))
        );
    endfunction

    function automatic logic [PA_WIDTH-1:0] gen_test_pa(input int unsigned i);
        return gen_pa(
            .high   (12'h200 + 12'(i / 32)),
            .idx    (5'(i % 32))
        );
    endfunction

    task body();
        // 清空后把表填满: 前 SDTLB_ENTRIES 条都落在空闲条目上 (0 号开始按序)
        inv_all();
        wait_cycles(.n(4));
        for (int unsigned i = 0; i < SDTLB_ENTRIES; i++) begin
            fill(
                .base   (gen_base(.i(i))),
                .up     (5'(i % 32)),
                .eid    (11'(i)),
                .tok    (11'(i + 1)),
                .tokv   (10'(i + 2)),
                .pfn    (18'(i * 3))
            );
            wait_cycles(.n(1));
        end
        wait_cycles(.n(6));

        // 清掉 5 号条目的映射: 满表里出现唯一一条空闲条目.
        // 紧接着下一拍就装填, 压一压 "刷新的下一拍就复用空闲条目" 这条路
        inv_sel(.pa(gen_base(.i(5))));

        // 再装填一条新地址 (高位取在测试地址段之外, 保证不与已填条目重复):
        // 应复用 5 号这条空闲条目
        fill(
            .base   (gen_pa_base(.high(12'h3ff), .idx(5'd0))),
            .up     (5'd0),
            .eid    (11'h7f0),
            .tok    (11'h7f1),
            .tokv   (10'h3f2),
            .pfn    (18'h3ffff)
        );
        wait_cycles(.n(4));

        // 0 号条目必须还在 (纯轮转会被这次装填淘汰掉) -> 命中
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_test_pa(.i(0))));
        wait_cycles(.n(2));

        // 被清掉的 5 号条目地址不再命中
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_test_pa(.i(5))));
        wait_cycles(.n(2));

        // 新地址命中 (说明装填确实落进了表里)
        cam_req(.cam0_en(1'b1), .cam0_pa(gen_pa(.high(12'h3ff), .idx(5'd0))));
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_FREE_SEQ_SV_
