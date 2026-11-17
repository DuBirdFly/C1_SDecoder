`ifndef _SDTLB_TEST_BASE_SV_
`define _SDTLB_TEST_BASE_SV_

// SDTLB 的基础用例: 依次跑 smoke / 段式 / 置无效 / 双端口 / 轮转序列,
// 期望值与比对全部由 scoreboard 的参考模型负责 (这里的任务只给激励)
class SdtlbTestBase extends uvm_test;

    `uvm_component_utils(SdtlbTestBase)

    SdtlbEnv sdtlb_env;

    function new(string name = "SdtlbTestBase", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sdtlb_env = SdtlbEnv::type_id::create("sdtlb_env", this);
    endfunction

    task run_phase(uvm_phase phase);
        SdtlbSmokeSeq  smoke;
        SdtlbSegSeq    seg;
        SdtlbInvSeq    inv;
        SdtlbDualSeq   dual;
        SdtlbRotateSeq rotate;

        phase.raise_objection(this);

        smoke  = SdtlbSmokeSeq::type_id::create("smoke");
        smoke.start(sdtlb_env.agt.sqr);

        seg    = SdtlbSegSeq::type_id::create("seg");
        seg.start(sdtlb_env.agt.sqr);

        inv    = SdtlbInvSeq::type_id::create("inv");
        inv.start(sdtlb_env.agt.sqr);

        dual   = SdtlbDualSeq::type_id::create("dual");
        dual.start(sdtlb_env.agt.sqr);

        rotate = SdtlbRotateSeq::type_id::create("rotate");
        rotate.start(sdtlb_env.agt.sqr);

        `uvm_info("TEST", "Sdtlb 序列跑完", UVM_LOW)

        // 等 monitor 把最后几拍的响应发布完
        #1000ns;

        phase.drop_objection(this);
    endtask

endclass

`endif // _SDTLB_TEST_BASE_SV_
