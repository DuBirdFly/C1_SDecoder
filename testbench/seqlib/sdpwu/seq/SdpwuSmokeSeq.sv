`ifndef _SDPWU_SMOKE_SEQ_SV_
`define _SDPWU_SMOKE_SEQ_SV_

// SDPWU smoke: 覆盖段式命中 / 页式命中 / 缺页 / 非法条目 / 两个请求并行
//   页表内容由 test 在跑序列前通过 SdpwuTableSeq 写进存储器模型 (见 SdpwuTestBase)
class SdpwuSmokeSeq extends SdpwuBaseSeq;

    `uvm_object_utils(SdpwuSmokeSeq)

    function new(string name = "SdpwuSmokeSeq");
        super.new(name);
    endfunction

    task body();
        // 段式命中: PA[46:35]=0, 段内页号 4 (段覆盖 3~5)
        pw_start(gen_pa(.l1_idx(12'd0), .up(5'd4)), .sdmq_idx(4'd0));
        wait_cycles(.n(20));

        // 页式命中: PA[46:35]=1, 二级表 index 7 有效
        pw_start(gen_pa(.l1_idx(12'd1), .up(5'd7)), .sdmq_idx(4'd1));
        wait_cycles(.n(20));

        // 缺页: PA[46:35]=3, 一级表条目 Valid=0
        pw_start(gen_pa(.l1_idx(12'd3), .up(5'd2)), .sdmq_idx(4'd2));
        wait_cycles(.n(20));

        // 一级表条目非法: PA[46:35]=2, SEG_BASE + SEG_LEN > 31
        pw_start(gen_pa(.l1_idx(12'd2), .up(5'd2)), .sdmq_idx(4'd3));
        wait_cycles(.n(20));

        // 二级表缺页: PA[46:35]=4, 一级表 Type=0, 二级表条目无��
        pw_start(gen_pa(.l1_idx(12'd4), .up(5'd1)), .sdmq_idx(4'd4));
        wait_cycles(.n(20));

        // 两个请求并行: 段式命中 + 页式命中
        pw_start(gen_pa(.l1_idx(12'd0), .up(5'd5)), .sdmq_idx(4'd5));
        pw_start(gen_pa(.l1_idx(12'd1), .up(5'd7)), .sdmq_idx(4'd6));
        wait_cycles(.n(40));
    endtask

endclass

`endif // _SDPWU_SMOKE_SEQ_SV_
