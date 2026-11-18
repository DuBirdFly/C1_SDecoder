`ifndef _SDTLB_ROTATE_SEQ_SV_
`define _SDTLB_ROTATE_SEQ_SV_

// SDTLB 替换指针轮转: 连续装填超过 SDTLB_ENTRIES 条, 指针绕圈覆盖最老的条目
class SdtlbRotateSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbRotateSeq)

    function new(string name = "SdtlbRotateSeq");
        super.new(name);
    endfunction

    task body();
        // 清空后连续装填 SDTLB_ENTRIES + 2 条, 地址互不相同
        inv_all();
        wait_cycles(.n(4));

        for (int unsigned i = 0; i < SDTLB_ENTRIES + 2; i++) begin
            fill(
                .base   (gen_pa_base(.high(12'h100 + 12'(i / 32)), .idx(5'(i % 32)))),
                .up     (5'(i % 32)),
                .eid    (11'(i)),
                .tok    (11'(i + 1)),
                .tokv   (10'(i + 2)),
                .pfn    (18'(i * 3))
            );
            wait_cycles(.n(1));
        end
        wait_cycles(.n(6));

        // 最后装填的两条仍在 (落在 0 号与 1 号条目)
        cam_req(
            .cam(0),
            .pa(gen_pa(.high(12'h100 + 12'(SDTLB_ENTRIES / 32)), .idx(5'(SDTLB_ENTRIES % 32))))
        );
        wait_cycles(.n(2));
        cam_req(
            .cam(0),
            .pa(gen_pa(.high(12'h100 + 12'((SDTLB_ENTRIES + 1) / 32)), .idx(5'(SDTLB_ENTRIES % 32 + 1))))
        );
        wait_cycles(.n(4));

        // 第 1 条 (已被绕圈覆盖) 不再命中
        cam_req(.cam(0), .pa(gen_pa(.high(12'h100), .idx(5'd0))));
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_ROTATE_SEQ_SV_
