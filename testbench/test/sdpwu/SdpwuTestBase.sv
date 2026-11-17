`ifndef _SDPWU_TEST_BASE_SV_
`define _SDPWU_TEST_BASE_SV_

// SDPWU_TOP 的基础用例: 先按设计方案的条目布局把页表写进存储器模型, 再跑 smoke 序列,
// 期望值与比对全部由 scoreboard 完成 (scb 从写口重建同一张表)
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

    // 记一条要写进存储器模型的页表条目 (scoreboard 也从写口重建这张表)
    function void add_word(
        SdpwuTableSeq                    tbl,
        input logic [PA_WIDTH-1:0]       addr,
        input logic [127:0]              word
    );
        tbl.addrs.push_back(addr);
        tbl.words.push_back(word);
    endfunction

    // 按设计方案的一级 / 二级表条目布局写表
    function void configure_table(SdpwuTableSeq tbl);
        SDT_L1_ITEM_t l1;
        SDT_L2_ITEM_t l2;

        // 0 号一级条目: 段式映射, 段覆盖 PA[34:30] = 3~5
        l1 = '{rsvd: '0, l2_base: 45'h2000, eid: 11'h011, token_id: 11'h022,
               token_value: 10'h033, s_pfn: 23'h100, seg_len: 5'd2, seg_base: 5'd3,
               type_bit: 1'b1, valid: 1'b1};
        add_word(tbl, {sdpwu_env.l1_base[PA_WIDTH-1:4], 4'h0} + (12'd0 << 4), 128'(l1));

        // 1 号一级条目: 页式, 二级表基地址 0x2000
        l1 = '{rsvd: '0, l2_base: 45'h2000, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd0, seg_base: 5'd0,
               type_bit: 1'b0, valid: 1'b1};
        add_word(tbl, {sdpwu_env.l1_base[PA_WIDTH-1:4], 4'h0} + (12'd1 << 4), 128'(l1));

        // 1 号一级条目对应的二级表: index 7 有效
        l2 = '{rsvd: '0, eid: 11'h044, token_id: 11'h055, token_value: 10'h066,
               s_pfn: 23'h200, valid: 1'b1};
        add_word(tbl, 48'h2000 + (5'd7 << 3), 128'(l2));

        // 2 号一级条目: 段式但 SEG_BASE + SEG_LEN > 31 -> 非法条目
        l1 = '{rsvd: '0, l2_base: 45'h0, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd5, seg_base: 5'd30,
               type_bit: 1'b1, valid: 1'b1};
        add_word(tbl, {sdpwu_env.l1_base[PA_WIDTH-1:4], 4'h0} + (12'd2 << 4), 128'(l1));

        // 3 号一级条目: Valid = 0 -> 缺页
        l1 = '{default: '0};
        add_word(tbl, {sdpwu_env.l1_base[PA_WIDTH-1:4], 4'h0} + (12'd3 << 4), 128'(l1));

        // 4 号一级条目: 页式, 一级表有效但二级表条目无效 -> 缺页
        l1 = '{rsvd: '0, l2_base: 45'h4000, eid: 11'h0, token_id: 11'h0,
               token_value: 10'h0, s_pfn: 23'h0, seg_len: 5'd0, seg_base: 5'd0,
               type_bit: 1'b0, valid: 1'b1};
        add_word(tbl, {sdpwu_env.l1_base[PA_WIDTH-1:4], 4'h0} + (12'd4 << 4), 128'(l1));
    endfunction

    task run_phase(uvm_phase phase);
        SdpwuTableSeq tbl;
        SdpwuSmokeSeq seq;

        phase.raise_objection(this);

        tbl = SdpwuTableSeq::type_id::create("tbl");
        configure_table(tbl);
        tbl.start(sdpwu_env.agt.sqr);

        seq = SdpwuSmokeSeq::type_id::create("seq");
        seq.start(sdpwu_env.agt.sqr);

        `uvm_info("TEST", "Sdpwu 序列跑完", UVM_LOW)

        #1000ns;

        phase.drop_objection(this);
    endtask

endclass

`endif // _SDPWU_TEST_BASE_SV_
