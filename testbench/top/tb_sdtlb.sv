// =============================================================================
// tb_sdtlb: sdtlb (SDTLB 顶层: Tag 阵列 + Data 阵列 + SLA 计算) 的单元自检
//
// 跑法 (在仓库根目录):
//   make -C simulation all TB_TOP=tb_sdtlb
//
// 结构: 时钟与复位由 crg 生成 (本 tb 内不出现任何 #NUM 延时); 通过 sdtlb_if 接口连 DUT ——
//       clk / rst_n 接进接口, DUT 各端口按名字连到接口信号; 同步一律等接口的 drv 时钟块
//       事件 @(sdtlb_vif.drv), 不再直接 @(posedge clk); DUT 输入用 drv 时钟块驱动
//       (posedge + 1ps 输出偏斜), 组合结果直接读裸接口信号 (命中/数据/SLA 都是同拍组合量,
//       不适合走时钟块采样) —— 驱动与读出之间隔一个时钟块事件, 组合逻辑早已稳定.
//       接口的 mon 时钟块留给后续的 monitor / scoreboard 组件.
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

    logic                                clk;
    logic                                rst_n;

    int                                  errors = 0;
    int                                  checks = 0;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  idx_obs;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  prev_idx;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  dup_first;
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  dup_second;
    logic                                rot_ok;
    logic [29:0]                         pa_low;

    // 时钟与复位由 crg 生成 (SDecoder 是单时钟域时序模块, tb 内不再自己写 #NUM 延时)
    crg #(
        .APB_FREQ ( 20  ),
        .AXI_FREQ ( 100 )
    ) u_crg (
        .pclk    (         ),
        .presetn (         ),
        .aclk    (clk      ),
        .aresetn (rst_n    )
    );

    // 接口: clk / rst_n 接进接口, DUT 各端口连接口信号
    sdtlb_if sdtlb_vif (.clk(clk), .rst_n(rst_n));

    // DUT 按名字连到接口信号
    sdtlb dut (
        .clk(clk), .rst_n(rst_n),
        .req_vld(sdtlb_vif.req_vld), .req_pa(sdtlb_vif.req_pa),
        .req_hit_vld(sdtlb_vif.req_hit_vld), .req_hit_idx(sdtlb_vif.req_hit_idx),
        .rd_eid(sdtlb_vif.rd_eid), .rd_token_id(sdtlb_vif.rd_token_id),
        .rd_s_pfn(sdtlb_vif.rd_s_pfn), .rd_grn(sdtlb_vif.rd_grn),
        .rd_pa_base(sdtlb_vif.rd_pa_base), .rd_pa_up(sdtlb_vif.rd_pa_up),
        .rd_sla(sdtlb_vif.rd_sla), .rd_sla_ovf(sdtlb_vif.rd_sla_ovf),
        .wr_vld(sdtlb_vif.wr_vld), .wr_pa_base(sdtlb_vif.wr_pa_base), .wr_pa_up(sdtlb_vif.wr_pa_up),
        .wr_eid(sdtlb_vif.wr_eid), .wr_token_id(sdtlb_vif.wr_token_id),
        .wr_s_pfn(sdtlb_vif.wr_s_pfn), .wr_grn(sdtlb_vif.wr_grn),
        .inv_all(sdtlb_vif.inv_all), .inv_en(sdtlb_vif.inv_en), .inv_pa(sdtlb_vif.inv_pa)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb, "+mda");
        $display("===============================================");
    end
`endif

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

    // 在时钟块事件上给出查表请求; 再等一个事件后由调用方读裸信号 —— 此间输入已生效、
    // 组合逻辑早已稳定, 所以不需要任何延时
    task automatic set_req(input logic [PA_WIDTH-1:0] pa);
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.req_vld <= 1'b1;
        sdtlb_vif.drv.req_pa  <= pa;
        @(sdtlb_vif.drv);
    endtask

    // 装填一个条目 (drv 块驱动一拍), 随后用它的基址回查: idx_obs = 落在哪一条
    task automatic fill_one(
        input logic [16:0] base,
        input logic [ 4:0] up,
        input logic [10:0] eid,
        input logic [ 9:0] tok,
        input logic [17:0] pfn,
        input logic        grn
    );
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.wr_pa_base  <= base;
        sdtlb_vif.drv.wr_pa_up    <= up;
        sdtlb_vif.drv.wr_eid      <= eid;
        sdtlb_vif.drv.wr_token_id <= tok;
        sdtlb_vif.drv.wr_s_pfn    <= pfn;
        sdtlb_vif.drv.wr_grn      <= grn;
        sdtlb_vif.drv.wr_vld      <= 1'b1;
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.wr_vld      <= 1'b0;
        set_req({1'b0, base, 30'h0});
        idx_obs = sdtlb_vif.req_hit_idx;
    endtask

    // 按地址置无效, 拉高一拍
    task automatic inv_addr(input logic [PA_WIDTH-1:0] pa);
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.inv_en <= 1'b1;
        sdtlb_vif.drv.inv_pa <= pa;
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.inv_en <= 1'b0;
    endtask

    // 置无效全部条目, 拉高一拍
    task automatic inv_everything();
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.inv_all <= 1'b1;
        @(sdtlb_vif.drv);
        sdtlb_vif.drv.inv_all <= 1'b0;
    endtask

    initial begin
        // 初值: DUT 输入全部由 drv 时钟块驱动 (时钟块内部变量初值为 X, 必须先给值)
        sdtlb_vif.drv.req_vld     <= 1'b0;
        sdtlb_vif.drv.req_pa      <= '0;
        sdtlb_vif.drv.wr_vld      <= 1'b0;
        sdtlb_vif.drv.wr_pa_base  <= '0;
        sdtlb_vif.drv.wr_pa_up    <= '0;
        sdtlb_vif.drv.wr_eid      <= '0;
        sdtlb_vif.drv.wr_token_id <= '0;
        sdtlb_vif.drv.wr_s_pfn    <= '0;
        sdtlb_vif.drv.wr_grn      <= 1'b0;
        sdtlb_vif.drv.inv_all     <= 1'b0;
        sdtlb_vif.drv.inv_en      <= 1'b0;
        sdtlb_vif.drv.inv_pa      <= '0;

        pa_low = 30'h1234_5678;

        // 复位由 crg 产生: 等它释放, 再等两拍让接口输入生效
        wait (rst_n === 1'b1);
        repeat (2) @(sdtlb_vif.drv);

        // ================= 空表 =================
        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("empty: hit_vld = 0", sdtlb_vif.req_hit_vld == 1'b0);
        chk("empty: rd_* = 0", (sdtlb_vif.rd_eid == 0) && (sdtlb_vif.rd_token_id == 0) &&
                              (sdtlb_vif.rd_s_pfn == 0) && (sdtlb_vif.rd_grn == 1'b0));
        chk("empty: sla / ovf = 0", (sdtlb_vif.rd_sla == '0) && (sdtlb_vif.rd_sla_ovf == 1'b0));

        // ================= 页式条目: Tag 与 Data 同下标, 偏移恒 0 =================
        fill_one({12'h100, 5'd7}, 5'd7, 11'h123, 10'h2a5, 18'h3ffff, 1'b0);
        chk("fill#1 lands on idx 0", idx_obs == 0);
        chk("fill#1: hit", sdtlb_vif.req_hit_vld == 1'b1);
        chk("fill#1: eid / token_id", (sdtlb_vif.rd_eid == 11'h123) && (sdtlb_vif.rd_token_id == 10'h2a5));
        chk("fill#1: s_pfn / grn", (sdtlb_vif.rd_s_pfn == 18'h3ffff) && (sdtlb_vif.rd_grn == 1'b0));
        chk("fill#1: rd_pa_base / rd_pa_up", (sdtlb_vif.rd_pa_base == {12'h100, 5'd7}) && (sdtlb_vif.rd_pa_up == 5'd7));
        // 带上页内偏移再查一次, 验 SLA 低 30 位原样透传 req_pa[29:0]
        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("page: SLA = {s_pfn, pa[29:0]}", sdtlb_vif.rd_sla == {18'h3ffff, pa_low});
        chk("page: 无溢出", sdtlb_vif.rd_sla_ovf == 1'b0);

        // ================= 段式条目: 段内偏移加进 SLA[47:30] =================
        fill_one({12'h200, 5'd4}, 5'd9, 11'h001, 10'h001, 18'h00010, 1'b1);
        chk("fill#2 lands on idx 1", idx_obs == 1);
        chk("fill#2: own data (不串扰)", (sdtlb_vif.rd_eid == 11'h001) && (sdtlb_vif.rd_grn == 1'b1));
        set_req(mk_pa(12'h200, 5'd6, pa_low));
        chk("seg: 偏移 2 加进 SLA[47:30]", sdtlb_vif.rd_sla == {18'h00012, pa_low});
        chk("seg: 无溢出", sdtlb_vif.rd_sla_ovf == 1'b0);
        set_req(mk_pa(12'h200, 5'd4, pa_low));
        chk("seg: 段基址处偏移 0", sdtlb_vif.rd_sla == {18'h00010, pa_low});

        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("re-query #1: idx 0 + own data", (sdtlb_vif.req_hit_idx == 0) &&
                                            (sdtlb_vif.rd_eid == 11'h123) && (sdtlb_vif.rd_s_pfn == 18'h3ffff));

        // ================= 按地址置无效: 只清覆盖该地址的条目 =================
        inv_addr(mk_pa(12'h100, 5'd7, 30'h0));
        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("inv_addr: miss", sdtlb_vif.req_hit_vld == 1'b0);
        chk("inv_addr: rd_* 与 sla 置 0", (sdtlb_vif.rd_eid == 0) && (sdtlb_vif.rd_s_pfn == 0) &&
                                         (sdtlb_vif.rd_sla == '0) && (sdtlb_vif.rd_sla_ovf == 1'b0));
        set_req(mk_pa(12'h200, 5'd7, pa_low));
        chk("inv_addr: #2 kept", (sdtlb_vif.req_hit_vld == 1'b1) && (sdtlb_vif.rd_eid == 11'h001));

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
        inv_everything();
        set_req(mk_pa(12'h300, 5'd0, pa_low));
        chk("inv_all: miss", sdtlb_vif.req_hit_vld == 1'b0);
        chk("inv_all: rd_* / sla 置 0", (sdtlb_vif.rd_eid == 0) && (sdtlb_vif.rd_grn == 1'b0) && (sdtlb_vif.rd_sla == '0));

        // ================= SLA 溢出: S_PFN 全 1 再加偏移 =================
        fill_one({12'h400, 5'd0}, 5'd31, 11'h002, 10'h002, 18'h3ffff, 1'b1);
        set_req(mk_pa(12'h400, 5'd1, pa_low));
        chk("ovf: hit", sdtlb_vif.req_hit_vld == 1'b1);
        chk("ovf: 偏移 1 时报溢出", sdtlb_vif.rd_sla_ovf == 1'b1);
        set_req(mk_pa(12'h400, 5'd0, pa_low));
        chk("ovf: 偏移 0 时不报", sdtlb_vif.rd_sla_ovf == 1'b0);

        // ================= 故意多命中: 优先级取最小 + 断言报出 (见文件头注) =================
        $display("[TB] 下面故意把同一 tag 装填两次, a_req_hit_onehot0 会报出来, 属预期");
        fill_one({12'h500, 5'd3}, 5'd3, 11'h111, 10'h111, 18'h00111, 1'b0);
        dup_first = idx_obs;
        fill_one({12'h500, 5'd3}, 5'd3, 11'h222, 10'h222, 18'h00222, 1'b0);
        dup_second = idx_obs;
        @(sdtlb_vif.drv);      // 再等一拍, 让 $onehot0 断言在时钟块事件上采样到重命中
        chk("dup tag: hit_vld", sdtlb_vif.req_hit_vld == 1'b1);
        chk("dup tag: idx = min", sdtlb_vif.req_hit_idx == ((dup_first < dup_second) ? dup_first : dup_second));
        chk("dup tag: 读出最小下标那条的数据", sdtlb_vif.rd_eid == 11'h111);

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
