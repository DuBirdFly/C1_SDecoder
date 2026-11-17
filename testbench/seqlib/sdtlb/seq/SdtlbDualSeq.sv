`ifndef _SDTLB_DUAL_SEQ_SV_
`define _SDTLB_DUAL_SEQ_SV_

// SDTLB 双端口: cam0 / cam1 同拍请求各自的条目, 命中互不影响; 地址对调后仍各自正确
class SdtlbDualSeq extends SdtlbBaseSeq;

    `uvm_object_utils(SdtlbDualSeq)

    function new(string name = "SdtlbDualSeq");
        super.new(name);
    endfunction

    task body();
        fill(base_of(12'h030, 5'd0), 5'd0, 11'h011, 11'h012, 10'h013, 18'h30303);
        wait_cycles(2);
        fill(base_of(12'h031, 5'd0), 5'd0, 11'h021, 11'h022, 10'h023, 18'h04040);
        wait_cycles(4);

        // 两端口同拍命中各自的条目
        req2(pa_of(12'h030, 5'd0), pa_of(12'h031, 5'd0));
        wait_cycles(4);

        // 地址对调, 仍应各自命中
        req2(pa_of(12'h031, 5'd0), pa_of(12'h030, 5'd0));
        wait_cycles(4);

        // 一端命中一端未命中
        req2(pa_of(12'h030, 5'd0), pa_of(12'h032, 5'd0));
        wait_cycles(4);
    endtask

endclass

`endif // _SDTLB_DUAL_SEQ_SV_
