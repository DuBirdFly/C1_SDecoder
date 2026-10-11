// =============================================================================
// tb_sdtlb: sdtlb (SDTLB 顶层: Tag 阵列 + Data 阵列) 的单元自检
// 注: SLA 计算已从 DUT 删除 (后续再处理), 相关检查随之删除;
//     请求地址与命中读出按新接口: req_pa 只到 PA[46:30] (17 bit),
//     命中输出是 req_hit + req_hit_tag_item / req_hit_data_item 两个 struct.
//
// 跑法 (在仓库根目录):
//   make -C simulation_agent all TB_TOP=tb_sdtlb
//
// 结构: 时钟与复位由 crg 生成 (本 tb 内不出现任何 #NUM 延时); 通过 sdtlb_if 接口连 DUT ——
//       clk / rst_n 接进接口, DUT 各端口按名字连到接口信号; 同步一律等接口的 drv 时钟块
//       事件 @(sdtlb_if.drv), 不再直接 @(posedge clk); DUT 输入用 drv 时钟块驱动
//       (posedge + 1ps 输出偏斜), 组合结果直接读裸接口信号 (命中与两个 struct 都是同拍
//       组合量, 不适合走时钟块采样) —— 驱动与读出之间隔一个时钟块事件, 组合逻辑早已稳定.
//       接口的 mon 时钟块留给后续的 monitor / scoreboard 组件.
//
// 说明: 只例化 sdtlb, 不依赖 UVM, 也不参与 tb_top 的冒烟流程. 覆盖
//   空表 / 装填 (Tag 与 Data 同条目) / 按地址区间命中与不命中 / 命中读出的
//   Tag 与 Data 两个 struct 内容,
//   末尾打印 "<N> checks, <M> errors" 与 "RESULT: PASS|FAIL", 失败时再 $fatal 提前结束.
//   注意: VCS 在 $fatal 时退出码仍是 0, 因此判定要看 log/simv.log 里的 RESULT 行.
// =============================================================================
`timescale 1ns/1ps
module tb_sdtlb;

    import sdecoder_pkg::*;

    logic                                clk;
    logic                                rst_n;

    int                                  errors = 0;
    int                                  checks = 0;

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
    // 实体接口实例, 名字不带 _vif 后缀 (_vif 只给 virtual interface 用)
    sdtlb_if sdtlb_if (.clk(clk), .rst_n(rst_n));

    // DUT 按名字连到接口信号
    sdtlb dut (
        .clk(clk), .rst_n(rst_n),
        .req_vld(sdtlb_if.req_vld), .req_pa(sdtlb_if.req_pa),
        .req_hit(sdtlb_if.req_hit),
        .req_hit_tag_item(sdtlb_if.req_hit_tag_item), .req_hit_data_item(sdtlb_if.req_hit_data_item),
        .fill_vld(sdtlb_if.fill_vld), .fill_pa_base(sdtlb_if.fill_pa_base), .fill_pa_up(sdtlb_if.fill_pa_up),
        .fill_eid(sdtlb_if.fill_eid), .fill_token_id(sdtlb_if.fill_token_id),
        .fill_s_pfn(sdtlb_if.fill_s_pfn), .fill_grn(sdtlb_if.fill_grn),
        .inv_all(sdtlb_if.inv_all), .inv_en(sdtlb_if.inv_en), .inv_pa(sdtlb_if.inv_pa)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb, "+all");
        $display("===============================================");
    end
`endif

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

    // 在时钟块事件上给出查表请求: 请求地址 = {段高位 12b, 段内页号 5b} (17 bit, 即 PA[46:30]).
    // req_vld 拉高后保持 (DUT 的 req_hit 由 req_vld 限定, 拉低就读不到命中了), 换地址时再改 req_pa.
    task automatic set_req(logic [11:0] high, logic [4:0] idx);
        sdtlb_if.drv.req_vld <= 1'b1;
        sdtlb_if.drv.req_pa  <= {high, idx};
        @(sdtlb_if.drv);
    endtask

    // 装填一个条目 (drv 块驱动一拍)
    task automatic fill_one(
        input logic [16:0] base,
        input logic [ 4:0] up,
        input logic [10:0] eid,
        input logic [ 9:0] tok,
        input logic [17:0] pfn,
        input logic        grn
    );
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_pa_base  <= base;
        sdtlb_if.drv.fill_pa_up    <= up;
        sdtlb_if.drv.fill_eid      <= eid;
        sdtlb_if.drv.fill_token_id <= tok;
        sdtlb_if.drv.fill_s_pfn    <= pfn;
        sdtlb_if.drv.fill_grn      <= grn;
        sdtlb_if.drv.fill_vld      <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_vld      <= 1'b0;
    endtask

    // 按地址置无效, 拉高一拍
    task automatic inv_addr(input logic [PA_BASE_WIDTH-1:0] pa);
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_en <= 1'b1;
        sdtlb_if.drv.inv_pa <= pa;
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_en <= 1'b0;
    endtask

    // 置无效全部条目, 拉高一拍
    task automatic inv_everything();
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_all <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_all <= 1'b0;
    endtask

    initial begin
        sdtlb_if.drv.req_vld     <= 1'b0;
        sdtlb_if.drv.req_pa      <= '0;
        sdtlb_if.drv.fill_vld      <= 1'b0;
        sdtlb_if.drv.fill_pa_base  <= '0;
        sdtlb_if.drv.fill_pa_up    <= '0;
        sdtlb_if.drv.fill_eid      <= '0;
        sdtlb_if.drv.fill_token_id <= '0;
        sdtlb_if.drv.fill_s_pfn    <= '0;
        sdtlb_if.drv.fill_grn      <= 1'b0;
        sdtlb_if.drv.inv_all     <= 1'b0;
        sdtlb_if.drv.inv_en      <= 1'b0;
        sdtlb_if.drv.inv_pa      <= '0;

        // 复位由 crg 产生: 等它释放, 再等两拍让接口输入生效
        wait (rst_n === 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 空表: 查表不命中, 命中读出全 0
        set_req(.high(12'hfff), .idx(5'h1f));
        repeat (10) @(sdtlb_if.drv);
        chk("empty: req_hit = 0", sdtlb_if.req_hit == 1'b0);
        chk("empty: 命中 Tag 读出全 0", sdtlb_if.req_hit_tag_item == '0);
        chk("empty: 命中 Data 读出全 0", sdtlb_if.req_hit_data_item == '0);

        // ====================================================================
        // 页式条目: base[4:0] == pa_up (闭区间退化成一个 1GB 页), 填到 0 号条目
        fill_one(
            .base({12'hfff, 5'h1f}),
            .up(5'h1f),
            .eid('1),
            .tok('1),
            .pfn(18'h33333),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        // 命中: Tag 与 Data 两个 struct 内容都要对得上
        set_req(.high(12'hfff), .idx(5'h1f));
        repeat (10) @(sdtlb_if.drv);
        chk("page: req_hit = 1", sdtlb_if.req_hit == 1'b1);
        chk("page: Tag struct (base/up/valid)",
            (sdtlb_if.req_hit_tag_item.pa_base == {12'hfff, 5'h1f}) &&
            (sdtlb_if.req_hit_tag_item.pa_up == 5'h1f) &&
            (sdtlb_if.req_hit_tag_item.valid == 1'b1));
        chk("page: Data struct (eid/token_id)",
            (sdtlb_if.req_hit_data_item.eid == '1) && (sdtlb_if.req_hit_data_item.token_id == '1));
        chk("page: Data struct (s_pfn/grn)",
            (sdtlb_if.req_hit_data_item.s_pfn == 18'h33333) && (sdtlb_if.req_hit_data_item.grn == 1'b0));

        // 同段高位、相邻页号: 页式条目只覆盖一页, 应该不命中
        set_req(.high(12'hfff), .idx(5'h1e));
        repeat (10) @(sdtlb_if.drv);
        chk("page: 相邻页不命中", sdtlb_if.req_hit == 1'b0);

        // [TODO] 以下测试是以前留的, 不再使用 (接口已改: 命中读出是 struct, 只能作参考)
        /*
        // ================= 段式条目: 段内偏移加进 SLA[47:30] =================
        fill_one({12'h200, 5'd4}, 5'd9, 11'h001, 10'h001, 18'h00010, 1'b1);
        chk("fill#2 lands on idx 1", idx_obs == 1);
        chk("fill#2: own data (不串扰)", (sdtlb_if.hit_eid == 11'h001) && (sdtlb_if.hit_grn == 1'b1));
        set_req(mk_pa(12'h200, 5'd6, pa_low));
        chk("seg: 偏移 2 加进 SLA[47:30]", sdtlb_if.hit_sla == {18'h00012, pa_low});
        chk("seg: 无溢出", sdtlb_if.hit_sla_ovf == 1'b0);
        set_req(mk_pa(12'h200, 5'd4, pa_low));
        chk("seg: 段基址处偏移 0", sdtlb_if.hit_sla == {18'h00010, pa_low});

        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("re-query #1: idx 0 + own data", (sdtlb_if.req_hit_idx == 0) &&
                                            (sdtlb_if.hit_eid == 11'h123) && (sdtlb_if.hit_s_pfn == 18'h3ffff));

        // ================= 按地址置无效: 只清覆盖该地址的条目 =================
        inv_addr(mk_pa(12'h100, 5'd7, 30'h0));
        set_req(mk_pa(12'h100, 5'd7, pa_low));
        chk("inv_addr: miss", sdtlb_if.req_hit_vld == 1'b0);
        chk("inv_addr: hit_* 与 sla 置 0", (sdtlb_if.hit_eid == 0) && (sdtlb_if.hit_s_pfn == 0) &&
                                         (sdtlb_if.hit_sla == '0) && (sdtlb_if.hit_sla_ovf == 1'b0));
        set_req(mk_pa(12'h200, 5'd7, pa_low));
        chk("inv_addr: #2 kept", (sdtlb_if.req_hit_vld == 1'b1) && (sdtlb_if.hit_eid == 11'h001));

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
        chk("inv_all: miss", sdtlb_if.req_hit_vld == 1'b0);
        chk("inv_all: rd_* / sla 置 0", (sdtlb_if.hit_eid == 0) && (sdtlb_if.hit_grn == 1'b0) && (sdtlb_if.hit_sla == '0));

        // ================= SLA 溢出: S_PFN 全 1 再加偏移 =================
        fill_one({12'h400, 5'd0}, 5'd31, 11'h002, 10'h002, 18'h3ffff, 1'b1);
        set_req(mk_pa(12'h400, 5'd1, pa_low));
        chk("ovf: hit", sdtlb_if.req_hit_vld == 1'b1);
        chk("ovf: 偏移 1 时报溢出", sdtlb_if.hit_sla_ovf == 1'b1);
        set_req(mk_pa(12'h400, 5'd0, pa_low));
        chk("ovf: 偏移 0 时不报", sdtlb_if.hit_sla_ovf == 1'b0);

        // ================= 故意多命中: 优先级取最小 + 断言报出 (见文件头注) =================
        $display("[TB] 下面故意把同一 tag 装填两次, a_req_hit_onehot0 会报出来, 属预期");
        fill_one({12'h500, 5'd3}, 5'd3, 11'h111, 10'h111, 18'h00111, 1'b0);
        dup_first = idx_obs;
        fill_one({12'h500, 5'd3}, 5'd3, 11'h222, 10'h222, 18'h00222, 1'b0);
        dup_second = idx_obs;
        @(sdtlb_if.drv);      // 再等一拍, 让 $onehot0 断言在时钟块事件上采样到重命中
        chk("dup tag: hit_vld", sdtlb_if.req_hit_vld == 1'b1);
        chk("dup tag: idx = min", sdtlb_if.req_hit_idx == ((dup_first < dup_second) ? dup_first : dup_second));
        chk("dup tag: 读出最小下标那条的数据", sdtlb_if.hit_eid == 11'h111);
        */

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
