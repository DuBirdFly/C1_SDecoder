`ifndef _SDPWU_TEST_BASE_SV_
`define _SDPWU_TEST_BASE_SV_

// SDPWU_TOP 的基础用例: 先按设计方案把页表写进 page_table_model, 再跑 smoke 序列,
// 期望值与比对全部由 scoreboard 用模型完成
class SdpwuTestBase extends uvm_test;

    `uvm_component_utils(SdpwuTestBase)

    SdpwuEnv sdpwu_env;

    function new(string name = "SdpwuTestBase", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sdpwu_env = SdpwuEnv::type_id::create("sdpwu_env", this);
    endfunction

    // 按设计方案的一级 / 二级表条目布局写表
    function void configure_table();
        SDT_L1_ITEM_t l1;
        SDT_L2_ITEM_t l2;

        // 0 号一级条目: 段式映射, 段覆盖 PA[34:30] = 3~5
        l1 = '{rsvd: '0, l2_base: 45'h2000, eid: 11'h011, token_id: 11'h022,
               token_value: 10'h033, s_pfn: 23'h100, seg_len: 5'd2, seg_base: 5'd3,
               type_bit: 1'b1, valid: 1'b1};
        sdpwu_env.pt_model.write_l1(sdpwu_env.l1_base, 12'd0, l1);

        // 1 号一级条目: 页式, 二级表基地址 0x2000
        l1 = '{rsvd: '0, l2_base: 45'h2000, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd0, seg_base: 5'd0,
               type_bit: 1'b0, valid: 1'b1};
        sdpwu_env.pt_model.write_l1(sdpwu_env.l1_base, 12'd1, l1);

        // 1 号一级条目对应的二级表: index 7 有效
        l2 = '{rsvd: '0, eid: 11'h044, token_id: 11'h055, token_value: 10'h066,
               s_pfn: 23'h200, valid: 1'b1};
        sdpwu_env.pt_model.write_l2({45'h2000}, 5'd7, l2);

        // 2 号一级条目: 段式但 SEG_BASE + SEG_LEN > 31 -> 非法条目
        l1 = '{rsvd: '0, l2_base: 45'h0, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd5, seg_base: 5'd30,
               type_bit: 1'b1, valid: 1'b1};
        sdpwu_env.pt_model.write_l1(sdpwu_env.l1_base, 12'd2, l1);

        // 3 号一级条目: Valid = 0 -> 缺页
        l1 = '{default: '0};
        sdpwu_env.pt_model.write_l1(sdpwu_env.l1_base, 12'd3, l1);

        // 4 号一级条目: 页式, 一级表有效但二级表条目无效 -> 缺页
        l1 = '{rsvd: '0, l2_base: 45'h4000, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd0, seg_base: 5'd0,
               type_bit: 1'b0, valid: 1'b1};
        sdpwu_env.pt_model.write_l1(sdpwu_env.l1_base, 12'd4, l1);
    endfunction

    task run_phase(uvm_phase phase);
        SdpwuSmokeSeq seq;

        phase.raise_objection(this);

        configure_table();

        seq = SdpwuSmokeSeq::type_id::create("seq");
        seq.start(sdpwu_env.agt.sqr);

        `uvm_info("TEST", "Sdpwu 序列跑完", UVM_LOW)

        #1000ns;

        phase.drop_objection(this);
    endtask

endclass

`endif // _SDPWU_TEST_BASE_SV_
