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
        .AXI_FREQ ( 100 ),
        .CLK_FREQ ( 100 )
    ) u_crg (
        .pclk    (         ),
        .presetn (         ),
        .aclk    (         ),
        .aresetn (         ),
        .clk     (clk      ),
        .rst_n   (rst_n    )
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
    // 本次驱动之后 req_vld 就自行拉低; 因为 req_hit 受 req_vld 限定, 检查必须紧接在驱动之后做,
    // 所以各测试点都是"驱动 -> 检查 -> 再等若干拍才动下一次激励"的次序.
    task automatic set_req(logic [11:0] high, logic [4:0] idx);
        sdtlb_if.drv.req_vld <= 1'b1;
        sdtlb_if.drv.req_pa  <= {high, idx};
        @(sdtlb_if.drv);
        sdtlb_if.drv.req_vld <= 1'b0;
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
        sdtlb_if.drv.inv_en <= 1'b1;
        sdtlb_if.drv.inv_pa <= pa;
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_en <= 1'b0;
    endtask

    // 置无效全部条目, 拉高一拍
    task automatic inv_everything();
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
        chk("empty: req_hit = 0", sdtlb_if.req_hit == 1'b0);
        chk("empty: 命中 Tag 读出全 0", sdtlb_if.req_hit_tag_item == '0);
        chk("empty: 命中 Data 读出全 0", sdtlb_if.req_hit_data_item == '0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 装填页式条目: base[4:0] == pa_up (闭区间退化成一个 1GB 页), 填到 0 号条目
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
        chk("page: req_hit = 1", sdtlb_if.req_hit == 1'b1);
        chk("page: Tag struct (base/up/valid)",
            (sdtlb_if.req_hit_tag_item.pa_base == {12'hfff, 5'h1f}) &&
            (sdtlb_if.req_hit_tag_item.pa_up == 5'h1f) &&
            (sdtlb_if.req_hit_tag_item.valid == 1'b1));
        chk("page: Data struct (eid/token_id)",
            (sdtlb_if.req_hit_data_item.eid == '1) && (sdtlb_if.req_hit_data_item.token_id == '1));
        chk("page: Data struct (s_pfn/grn)",
            (sdtlb_if.req_hit_data_item.s_pfn == 18'h33333) && (sdtlb_if.req_hit_data_item.grn == 1'b0));
        repeat (10) @(sdtlb_if.drv);

        // 同段高位、相邻页号: 页式条目只覆盖一页, 应该不命中
        set_req(.high(12'hfff), .idx(5'h1e));
        chk("page: 相邻页不命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 第二个条目: 轮转指针走一格, 该填到 1 号条目 (覆盖"非 0 条目也能被写"
        // 与"按地址选中正确的条目, 数据不串扰")
        fill_one(
            .base({12'h001, 5'd0}),
            .up(5'd0),
            .eid(11'h055),
            .tok(10'h0aa),
            .pfn(18'h0cccc),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h001), .idx(5'd0));
        chk("fill#2: 命中且落在 1 号条目",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_tag_item.pa_base == {12'h001, 5'd0}));
        chk("fill#2: Data 内容 (不串扰)",
            (sdtlb_if.req_hit_data_item.eid == 11'h055) &&
            (sdtlb_if.req_hit_data_item.token_id == 10'h0aa) &&
            (sdtlb_if.req_hit_data_item.s_pfn == 18'h0cccc));
        repeat (10) @(sdtlb_if.drv);

        // 回到 0 号条目的地址: 仍然命中, 且读回的是它自己的数据
        set_req(.high(12'hfff), .idx(5'h1f));
        chk("fill#1 仍在 (两个条目各自独立)",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'h33333));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 段式条目 (Grn = 1): pa_up > pa_base[4:0], 一个条目覆盖 4~8 共 5 个 1GB 页
        fill_one(
            .base({12'h002, 5'd4}),
            .up(5'd8),
            .eid(11'h123),
            .tok(10'h2aa),
            .pfn(18'h15555),
            .grn(1'b1)
        );
        repeat (10) @(sdtlb_if.drv);

        // 闭区间内: 左端 / 中间 / 右端 都命中
        set_req(.high(12'h002), .idx(5'd4));
        chk("seg: 左端命中 (闭区间)",
            (sdtlb_if.req_hit == 1'b1) &&
            (sdtlb_if.req_hit_tag_item.pa_base == {12'h002, 5'd4}) &&
            (sdtlb_if.req_hit_tag_item.pa_up == 5'd8));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd6));
        chk("seg: 中间命中且 Grn = 1",
            (sdtlb_if.req_hit == 1'b1) &&
            (sdtlb_if.req_hit_data_item.s_pfn == 18'h15555) &&
            (sdtlb_if.req_hit_data_item.grn == 1'b1));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd8));
        chk("seg: 右端命中 (闭区间)", sdtlb_if.req_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 闭区间外 / 段高位不同: 都不命中
        set_req(.high(12'h002), .idx(5'd3));
        chk("seg: 左端外不命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd9));
        chk("seg: 右端外不命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h003), .idx(5'd6));
        chk("seg: 段高位不同不命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // req_vld 门控: 地址仍落在段内, set_req 之后 req_vld 已拉低, 命中与读出都要归 0
        set_req(.high(12'h002), .idx(5'd6));
        chk("req_vld = 1: 命中 (门控前置)", sdtlb_if.req_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);
        chk("req_vld = 0: 命中与读出数据都归 0",
            (sdtlb_if.req_hit == 1'b0) &&
            (sdtlb_if.req_hit_tag_item == '0) &&
            (sdtlb_if.req_hit_data_item == '0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 按地址置无效: 只清掉被地址覆盖到的条目
        // 另填一个页式条目, 用来验证"没被覆盖的条目不受影响"
        fill_one(
            .base({12'h010, 5'd20}),
            .up(5'd20),
            .eid(11'h0f0),
            .tok(10'h0f0),
            .pfn(18'h0f0f0),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        // 段高位相同、但落在条目范围外: 不能清掉它
        inv_addr({12'h010, 5'd19});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 同段高位但范围外, 条目不被动", sdtlb_if.req_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 段内任意一个地址都应清掉整个段条目
        inv_addr({12'h002, 5'd7});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h002), .idx(5'd7));
        chk("inv: 段内任一地址清掉整个段条目", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // 段高位不同的条目不受影响
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 只作用于被覆盖的条目", sdtlb_if.req_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 精确命中页式条目时清掉它; 未命中时命中读出全 0
        inv_addr({12'h010, 5'd20});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 页式条目被清掉", sdtlb_if.req_hit == 1'b0);
        chk("inv: 未命中时 Tag / Data 读出全 0",
            (sdtlb_if.req_hit_tag_item == '0) && (sdtlb_if.req_hit_data_item == '0));
        repeat (10) @(sdtlb_if.drv);

        // 置无效只清有效位: 重新装填即可恢复, 且读回的是新数据
        fill_one(
            .base({12'h010, 5'd20}),
            .up(5'd20),
            .eid(11'h0e0),
            .tok(10'h0e0),
            .pfn(18'h0e0e0),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 重新装填后恢复命中, 数据是新的",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'h0e0e0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 置无效全部
        fill_one(
            .base({12'h030, 5'd1}),
            .up(5'd1),
            .eid(11'h0b0),
            .tok(10'h0b0),
            .pfn(18'h0b0b0),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all 前置: 条目命中", sdtlb_if.req_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        inv_everything();
        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all: 该条目不再命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h010), .idx(5'd20));
        chk("inv_all: 先前填的其它条目也不再命中", sdtlb_if.req_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // 全部置无效后重新装填仍能命中 (写通路没被破坏)
        fill_one(
            .base({12'h030, 5'd1}),
            .up(5'd1),
            .eid(11'h0a0),
            .tok(10'h0a0),
            .pfn(18'h0a0a0),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all 后重新装填可命中",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'h0a0a0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 同拍: 全置无效优先于装填 (inv_all 对每个条目都成立, 与轮转指针当前指到谁无关)
        sdtlb_if.drv.fill_pa_base  <= {12'h020, 5'd3};
        sdtlb_if.drv.fill_pa_up    <= 5'd3;
        sdtlb_if.drv.fill_eid      <= 11'h0c0;
        sdtlb_if.drv.fill_token_id <= 10'h0c0;
        sdtlb_if.drv.fill_s_pfn    <= 18'h0c0c0;
        sdtlb_if.drv.fill_grn      <= 1'b0;
        sdtlb_if.drv.fill_vld      <= 1'b1;
        sdtlb_if.drv.inv_all       <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_vld <= 1'b0;
        sdtlb_if.drv.inv_all  <= 1'b0;
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h020), .idx(5'd3));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍: 全置无效赢, 该次装填地址未命中", sdtlb_if.req_hit == 1'b0);

        set_req(.high(12'h030), .idx(5'd1));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍: 全置无效把原有条目也清掉了", sdtlb_if.req_hit == 1'b0);

        // ====================================================================
        // 轮转替换指针, 以及"无效条目同拍被刷新"的竞态
        // 连填 128 次指针正好绕一圈回到起点条目; 起点条目这时仍持有这一圈第一次装填的地址,
        // 于是可以让"指针指到它"与"按它自己的地址置无效 + 装填"发生在同一拍
        fill_one(
            .base({12'h100, 5'd0}),
            .up(5'd0),
            .eid(11'h001),
            .tok(10'h001),
            .pfn(18'h00001),
            .grn(1'b0)
        );
        for (int i = 1; i < 128; i++) begin
            fill_one(
                .base({12'h100 + 12'(i / 32), 5'(i % 32)}),
                .up(5'(i % 32)),
                .eid(11'(i)),
                .tok(10'(i)),
                .pfn(18'(i)),
                .grn(1'b0)
            );
        end
        repeat (10) @(sdtlb_if.drv);

        // 先单独按 ADDR0 置无效: 条目变为无效, 但 pa_base / pa_up 仍是 ADDR0 的值
        inv_addr({12'h100, 5'd0});
        repeat (10) @(sdtlb_if.drv);

        // 同拍: 按 ADDR0 装填且按 ADDR0 置无效. 置无效必须先赢 —— 否则条目会被填回成有效,
        // 查 ADDR0 就会命中 (这正是"有效位不能并进 inv_match"要防的情况)
        sdtlb_if.drv.fill_pa_base  <= {12'h100, 5'd0};
        sdtlb_if.drv.fill_pa_up    <= 5'd0;
        sdtlb_if.drv.fill_eid      <= 11'h7ff;
        sdtlb_if.drv.fill_token_id <= 10'h3ff;
        sdtlb_if.drv.fill_s_pfn    <= 18'h3ffff;
        sdtlb_if.drv.fill_grn      <= 1'b0;
        sdtlb_if.drv.fill_vld      <= 1'b1;
        sdtlb_if.drv.inv_en        <= 1'b1;
        sdtlb_if.drv.inv_pa        <= {12'h100, 5'd0};
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_vld <= 1'b0;
        sdtlb_if.drv.inv_en   <= 1'b0;
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h100), .idx(5'd0));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍(无效条目): 置无效赢, 该次装填地址未命中", sdtlb_if.req_hit == 1'b0);

        // 再单独装填一次: 指针已随上一次装填步进, 这里验证轮转与写通路都正常
        fill_one(
            .base({12'h100, 5'd0}),
            .up(5'd0),
            .eid(11'h7fe),
            .tok(10'h3fe),
            .pfn(18'h3fffe),
            .grn(1'b0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h100), .idx(5'd0));
        chk("轮转: 绕圈后重新装填可命中, 数据正确",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'h3fffe));
        repeat (10) @(sdtlb_if.drv);

        // 绕圈时填进去的占位条目各自还在 (抽查第 3 个与最后一个)
        set_req(.high(12'h100), .idx(5'd2));
        chk("轮转: 绕圈里的占位条目仍在 (第 3 个)",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'd2));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h103), .idx(5'd31));
        chk("轮转: 绕圈里的占位条目仍在 (第 128 个)",
            (sdtlb_if.req_hit == 1'b1) && (sdtlb_if.req_hit_data_item.s_pfn == 18'd127));
        repeat (10) @(sdtlb_if.drv);

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
