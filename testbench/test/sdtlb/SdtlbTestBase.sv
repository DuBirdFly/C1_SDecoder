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
        SdtlbSmokeSeq  smokeSeq;
        SdtlbSegSeq    segSeq;
        SdtlbInvSeq    invSeq;
        SdtlbDualSeq   dualSeq;
        SdtlbRotateSeq rotateSeq;

        phase.raise_objection(this);

        smokeSeq = SdtlbSmokeSeq::type_id::create("smokeSeq");
        smokeSeq.start(sdtlb_env.agt.sqr);

        segSeq = SdtlbSegSeq::type_id::create("segSeq");
        segSeq.start(sdtlb_env.agt.sqr);

        invSeq = SdtlbInvSeq::type_id::create("invSeq");
        invSeq.start(sdtlb_env.agt.sqr);

        dualSeq = SdtlbDualSeq::type_id::create("dualSeq");
        dualSeq.start(sdtlb_env.agt.sqr);

        rotateSeq = SdtlbRotateSeq::type_id::create("rotateSeq");
        rotateSeq.start(sdtlb_env.agt.sqr);

        `uvm_info("TEST", "Sdtlb 序列跑完", UVM_LOW)

        // 等 monitor 把最后几拍的响应发布完
        #1000ns;

        phase.drop_objection(this);
    endtask

endclass

`endif // _SDTLB_TEST_BASE_SV_
