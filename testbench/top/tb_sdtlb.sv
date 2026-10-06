// =============================================================================
// tb_sdtlb: sdtlb (SDTLB 顶层: Tag 阵列 + Data 阵列 + SLA 计算) 的单元自检
//
// 跑法 (在仓库根目录):
//   make -C simulation all TB_TOP=tb_sdtlb
//   日志与产物在 simulation/run_single_testcase/tb_sdtlb.TestBase/
//
// 说明: 只例化 sdtlb, 不依赖 UVM, 也不参与 tb_top 的冒烟流程. 覆盖
//   装填 (Tag/Data 同下标) / 查表与命中下标 / 数据读出 / SLA 计算与溢出 /
//   按地址与全部置无效 / 轮转替换指针 / 多命中取最小 七类行为,
//   末尾打印 "<N> checks, <M> errors" 与 "RESULT: PASS|FAIL", 失败时再 $fatal 提前结束.
//   注意: VCS 在 $fatal 时退出码仍是 0, 因此判定要看 log/simv.log 里的 RESULT 行.
//
// 注: 最后一段"多命中"是**故意**制造的重命中, 用来验优先级编码与 $onehot0 断言,
//     运行日志里会出现 Assertion 'a_req_hit_onehot0' failed, 属预期.
// =============================================================================
`timescale 1ns/1ps
module tb_sdtlb;

    import sdecoder_pkg::*;

    logic                                clk = 0;
    logic                                rst_n = 0;
    logic                                req_vld;
    logic [PA_WIDTH-1:0]                 req_pa;
    logic                                req_hit_vld;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  req_hit_idx;
    logic [10:0]                         rd_eid;
    logic [ 9:0]                         rd_token_id;
    logic [17:0]                         rd_s_pfn;
    logic                                rd_grn;
    logic [16:0]                         rd_pa_base;
    logic [ 4:0]                         rd_pa_up;
    logic [SLA_WIDTH-1:0]                rd_sla;
    logic                                rd_sla_ovf;
    logic                                wr_vld;
    logic [16:0]                         wr_pa_base;
    logic [ 4:0]                         wr_pa_up;
    logic [10:0]                         wr_eid;
    logic [ 9:0]                         wr_token_id;
    logic [17:0]                         wr_s_pfn;
    logic                                wr_grn;
    logic                                inv_all;
    logic                                inv_en;
    logic [PA_WIDTH-1:0]                 inv_pa;

    int                                  errors = 0;
    int                                  checks = 0;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  idx_obs;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  prev_idx;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  dup_first;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  dup_second;
    logic                                rot_ok;
    logic [29:0]                         pa_low;

    always #5 clk = ~clk;

    sdtlb dut (
        .clk(clk), .rst_n(rst_n),
        .req_vld(req_vld), .req_pa(req_pa),
        .req_hit_vld(req_hit_vld), .req_hit_idx(req_hit_idx),
        .rd_eid(rd_eid), .rd_token_id(rd_token_id), .rd_s_pfn(rd_s_pfn), .rd_grn(rd_grn),
        .rd_pa_base(rd_pa_base), .rd_pa_up(rd_pa_up),
        .rd_sla(rd_sla), .rd_sla_ovf(rd_sla_ovf),
        .wr_vld(wr_vld), .wr_pa_base(wr_pa_base), .wr_pa_up(wr_pa_up),
        .wr_eid(wr_eid), .wr_token_id(wr_token_id), .wr_s_pfn(wr_s_pfn), .wr_grn(wr_grn),
        .inv_all(inv_all), .inv_en(inv_en), .inv_pa(inv_pa)
    );

    // PA = {1'b0, 段高位 12b, 段内下标 5b, 页内偏移 30b}
    function automatic logic [PA_WIDTH-1:0] mk_pa(
        input logic [11:0] high,
        input logic [ 4:0] idx,
        input logic [29:0] low
    );
        mk_pa = {1'b0, high, idx, low};
    endfunction

    task automatic chk(input string name, input logic cond);
        checks++;
        if (!cond) begin
            errors++;
            $display("FAIL %-46s", name);
        end
        else begin
            $display("ok   %-46s", name);
        end
    endtask

    // 装填一个条目 (wr_pa_vld 有效一拍), 随后用它的基址回查: idx_obs = 落在哪一条
    task automatic fill_one(
        input logic [16:0] base,
        input logic [ 4:0] up,
        input logic [10:0] eid,
        input logic [ 9:0] tok,
        input logic [17:0] pfn,
        input logic        grn
    );
        @(negedge clk);
        wr_pa_base = base; wr_pa_up = up;
        wr_eid = eid; wr_token_id = tok; wr_s_pfn = pfn; wr_grn = grn;
        wr_vld = 1'b1;
        @(negedge clk);
        wr_vld = 1'b0;
        req_pa = {1'b0, base, 30'h0}; #1;
        idx_obs = req_hit_idx;
    endtask

    initial begin
        req_vld = 1'b1; req_pa = '0; pa_low = 30'h1234_5678;
        wr_vld = 1'b0; wr_pa_base = '0; wr_pa_up = '0;
        wr_eid = '0; wr_token_id = '0; wr_s_pfn = '0; wr_grn = 1'b0;
        inv_all = 1'b0; inv_en = 1'b0; inv_pa = '0;
        @(negedge clk); rst_n = 1'b1;

        // ================= 空表 =================
        req_pa = mk_pa(12'h100, 5'd7, pa_low); #1;
        chk("empty: hit_vld = 0", req_hit_vld == 1'b0);
        chk("empty: rd_* = 0", (rd_eid == 0) && (rd_token_id == 0) && (rd_s_pfn == 0) && (rd_grn == 1'b0));
        chk("empty: sla / ovf = 0", (rd_sla == '0) && (rd_sla_ovf == 1'b0));

        // ================= 页式条目: Tag 与 Data 同下标, 偏移恒 0 =================
        fill_one({12'h100, 5'd7}, 5'd7, 11'h123, 10'h2a5, 18'h3ffff, 1'b0);
        chk("fill#1 lands on idx 0", idx_obs == 0);
        chk("fill#1: hit", req_hit_vld == 1'b1);
        chk("fill#1: eid / token_id", (rd_eid == 11'h123) && (rd_token_id == 10'h2a5));
        chk("fill#1: s_pfn / grn", (rd_s_pfn == 18'h3ffff) && (rd_grn == 1'b0));
        chk("fill#1: rd_pa_base / rd_pa_up", (rd_pa_base == {12'h100, 5'd7}) && (rd_pa_up == 5'd7));
        // 带上页内偏移再查一次, 验 SLA 低 30 位原样透传 req_pa[29:0]
        req_pa = mk_pa(12'h100, 5'd7, pa_low); #1;
        chk("page: SLA = {s_pfn, pa[29:0]}", rd_sla == {18'h3ffff, pa_low});
        chk("page: 无溢出", rd_sla_ovf == 1'b0);

        // ================= 段式条目: 段内偏移加进 SLA[47:30] =================
        fill_one({12'h200, 5'd4}, 5'd9, 11'h001, 10'h001, 18'h00010, 1'b1);
        chk("fill#2 lands on idx 1", idx_obs == 1);
        chk("fill#2: own data (不串扰)", (rd_eid == 11'h001) && (rd_grn == 1'b1));
        req_pa = mk_pa(12'h200, 5'd6, pa_low); #1;
        chk("seg: 偏移 2 加进 SLA[47:30]", rd_sla == {18'h00012, pa_low});
        chk("seg: 无溢出", rd_sla_ovf == 1'b0);
        req_pa = mk_pa(12'h200, 5'd4, pa_low); #1;
        chk("seg: 段基址处偏移 0", rd_sla == {18'h00010, pa_low});

        req_pa = mk_pa(12'h100, 5'd7, pa_low); #1;
        chk("re-query #1: idx 0 + own data", (req_hit_idx == 0) && (rd_eid == 11'h123) && (rd_s_pfn == 18'h3ffff));

        // ================= 按地址置无效: 只清覆盖该地址的条目 =================
        @(negedge clk); inv_en = 1'b1; inv_pa = mk_pa(12'h100, 5'd7, 30'h0);
        @(negedge clk); inv_en = 1'b0;
        req_pa = mk_pa(12'h100, 5'd7, pa_low); #1;
        chk("inv_addr: miss", req_hit_vld == 1'b0);
        chk("inv_addr: rd_* 与 sla 置 0", (rd_eid == 0) && (rd_s_pfn == 0) && (rd_sla == '0) && (rd_sla_ovf == 1'b0));
        req_pa = mk_pa(12'h200, 5'd7, pa_low); #1;
        chk("inv_addr: #2 kept", (req_hit_vld == 1'b1) && (rd_eid == 11'h001));

        // ================= 轮转替换指针: 连续装填下标逐个 +1 =================
        fill_one({12'h300, 5'd0}, 5'd0, 11'h0aa, 10'h0aa, 18'h000aa, 1'b0);
        prev_idx = idx_obs;
        rot_ok = 1'b1;
        for (int i = 1; i < 4; i++) begin
            fill_one({(12'h300 + i[11:0]), 5'd0}, 5'd0, 11'h0aa, 10'h0aa, 18'h000aa, 1'b0);
            if (idx_obs !== (prev_idx + 1'b1)) begin
                rot_ok = 1'b0;
                $display("FAIL rotation at i=%0d: idx=%0d prev=%0d", i, idx_obs, prev_idx);
            end
            prev_idx = idx_obs;
        end
        chk("rotation advances by 1 (4 fills)", rot_ok == 1'b1);

        // ================= 全部置无效 =================
        @(negedge clk); inv_all = 1'b1;
        @(negedge clk); inv_all = 1'b0;
        req_pa = mk_pa(12'h300, 5'd0, pa_low); #1;
        chk("inv_all: miss", req_hit_vld == 1'b0);
        chk("inv_all: rd_* / sla 置 0", (rd_eid == 0) && (rd_grn == 1'b0) && (rd_sla == '0));

        // ================= SLA 溢出: S_PFN 全 1 再加偏移 =================
        fill_one({12'h400, 5'd0}, 5'd31, 11'h002, 10'h002, 18'h3ffff, 1'b1);
        req_pa = mk_pa(12'h400, 5'd1, pa_low); #1;
        chk("ovf: hit", req_hit_vld == 1'b1);
        chk("ovf: 偏移 1 时报溢出", rd_sla_ovf == 1'b1);
        req_pa = mk_pa(12'h400, 5'd0, pa_low); #1;
        chk("ovf: 偏移 0 时不报", rd_sla_ovf == 1'b0);

        // ================= 故意多命中: 优先级取最小 + 断言报出 (见文件头注) =================
        $display("[TB] 下面故意把同一 tag 装填两次, a_req_hit_onehot0 会报出来, 属预期");
        fill_one({12'h500, 5'd3}, 5'd3, 11'h111, 10'h111, 18'h00111, 1'b0);
        dup_first = idx_obs;
        fill_one({12'h500, 5'd3}, 5'd3, 11'h222, 10'h222, 18'h00222, 1'b0);
        dup_second = idx_obs;
        @(negedge clk); #1;
        chk("dup tag: hit_vld", req_hit_vld == 1'b1);
        chk("dup tag: idx = min", req_hit_idx == ((dup_first < dup_second) ? dup_first : dup_second));
        chk("dup tag: 读出最小下标那条的数据", rd_eid == 11'h111);

        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdtlb 单元自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
