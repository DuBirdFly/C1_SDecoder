`ifndef _SDTLB_DUAL_SEQ_SV_
`define _SDTLB_DUAL_SEQ_SV_

// SDTLB 双端口: cam0 / cam1 同拍请求各自的条目, 命中互不影响; 地址对调后仍各自正确
class SdtlbDualSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbDualSeq)

    function new(string name = "SdtlbDualSeq");
        super.new(name);
    endfunction

    task body();
        SdtlbItem item;

        fill(
            .base   (gen_pa_base(.high(12'h030), .idx(5'd0))),
            .up     (5'd0),
            .eid    (11'h011),
            .tok    (11'h012),
            .tokv   (10'h013),
            .pfn    (18'h30303)
        );
        wait_cycles(.n(2));
        fill(
            .base   (gen_pa_base(.high(12'h031), .idx(5'd0))),
            .up     (5'd0),
            .eid    (11'h021),
            .tok    (11'h022),
            .tokv   (10'h023),
            .pfn    (18'h04040)
        );
        wait_cycles(.n(4));

        // 两端口同拍命中各自的条目
        item = new_item();
        set_cam(item, 0, gen_pa(.high(12'h030), .idx(5'd0)));
        set_cam(item, 1, gen_pa(.high(12'h031), .idx(5'd0)));
        send(item);
        wait_cycles(.n(4));

        // 地址对调, 仍应各自命中
        item = new_item();
        set_cam(item, 0, gen_pa(.high(12'h031), .idx(5'd0)));
        set_cam(item, 1, gen_pa(.high(12'h030), .idx(5'd0)));
        send(item);
        wait_cycles(.n(4));

        // 一端命中一端未命中
        item = new_item();
        set_cam(item, 0, gen_pa(.high(12'h030), .idx(5'd0)));
        set_cam(item, 1, gen_pa(.high(12'h032), .idx(5'd0)));
        send(item);
        wait_cycles(.n(4));

        // 只有 cam1 发请求: 命中
        cam_req(.cam(1), .pa(gen_pa(.high(12'h031), .idx(5'd0))));
        wait_cycles(.n(4));

        // 只有 cam1 发请求: 未命中 (cam0 没请求, 响应必须是全 0)
        cam_req(.cam(1), .pa(gen_pa(.high(12'h033), .idx(5'd0))));
        wait_cycles(.n(4));
    endtask

endclass

`endif // _SDTLB_DUAL_SEQ_SV_
