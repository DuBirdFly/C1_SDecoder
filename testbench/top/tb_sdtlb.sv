`timescale 1ns/1ps
module tb_sdtlb;

    import sdecoder_pkg::*;

    logic                                clk;
    logic                                rst_n;

    int                                  errors = 0;
    int                                  checks = 0;

    // 响应 (req_hit 与读出的 Tag / Data) 统一从时钟块采样取: DUT 把命中向量打了 1 拍,
    // 响应只在"请求拍"的下一拍有效, 直接读 `sdtlb_if.req_*` 会和 DUT 输出挤在同一时刻,
    // 打没打拍都"看起来"一样, 起不到验证作用
    logic                                rsp_hit;
    SDTLB_TAG_ITEM_t                     rsp_tag;
    SDTLB_DATA_ITEM_t                    rsp_data;

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
        .req_valid(sdtlb_if.req_valid), .req_pa(sdtlb_if.req_pa),
        .req_hit(sdtlb_if.req_hit),
        .req_hit_tag_item(sdtlb_if.req_hit_tag_item), .req_hit_data_item(sdtlb_if.req_hit_data_item),
        .fill_valid(sdtlb_if.fill_valid), .fill_pa_base(sdtlb_if.fill_pa_base), .fill_pa_up(sdtlb_if.fill_pa_up),
        .fill_eid(sdtlb_if.fill_eid), .fill_token_id(sdtlb_if.fill_token_id),
        .fill_s_pfn(sdtlb_if.fill_s_pfn),
        .inv_all(sdtlb_if.inv_all), .inv_en(sdtlb_if.inv_en), .inv_pa(sdtlb_if.inv_pa)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
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

    // 取当前时钟块采样到的响应; 需在"响应拍"的事件上调用才有意义
    task automatic sample_rsp();
        rsp_hit  = sdtlb_if.drv.req_hit;
        rsp_tag  = sdtlb_if.drv.req_hit_tag_item;
        rsp_data = sdtlb_if.drv.req_hit_data_item;
    endtask

    // 在时钟块事件上给出查表请求: 请求地址是整条 PA[47:0] = {段高位 PA[47:35], 段内页号 PA[34:30],
    // 页内偏移 PA[29:0]}; 默认 offset = 0, 需要查"偏移与命中无关"时再给.
    // 本 tb 只打 PA[47] = 0 的地址, 因为 SDecoder 只处理 Mem 空间.
    // 驱动一拍后 req_valid 就自行拉低. 打 1 拍的口径:
    //   "请求拍" —— DUT 刚在这一沿采到 req_valid / req_pa, 本次请求的响应还没出来;
    //   "响应拍" —— 请求拍的下一拍, 这一拍采到的才是本次请求的响应.
    // 本任务等到响应拍才返回, 返回时 rsp_* 即本次请求的响应 (见 sample_rsp);
    // 所以各测试点都是"驱动 -> 取值 -> 再等若干拍才动下一次激励"的次序.
    task automatic set_req(
        logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0]              high,
        logic [PA_UP_WIDTH-1:0]                            idx,
        logic [PA_WIDTH-PA_BASE_WIDTH-1:0]                 offset = '0
    );
        sdtlb_if.drv.req_valid <= 1'b1;
        sdtlb_if.drv.req_pa  <= {high, idx, offset};
        @(sdtlb_if.drv);                    // 请求拍
        sdtlb_if.drv.req_valid <= 1'b0;
        @(sdtlb_if.drv);                    // 响应拍 (打 1 拍)
        sample_rsp();
    endtask

    // 装填一个条目 (drv 块驱动一拍); base 是 PA[47:30] (只打 PA[47] = 0 的值)
    task automatic fill_one(
        input logic [PA_BASE_WIDTH-1:0]             base,
        input logic [PA_UP_WIDTH-1:0]               up,
        input logic [EID_WIDTH-1:0]                 eid,
        input logic [TOKEN_ID_WIDTH-1:0]            tok,
        input logic [S_PFN_WIDTH-1:0]               pfn
    );
        sdtlb_if.drv.fill_pa_base  <= base;
        sdtlb_if.drv.fill_pa_up    <= up;
        sdtlb_if.drv.fill_eid      <= eid;
        sdtlb_if.drv.fill_token_id <= tok;
        sdtlb_if.drv.fill_s_pfn    <= pfn;
        sdtlb_if.drv.fill_valid      <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_valid      <= 1'b0;
    endtask

    // 按地址置无效, 拉高一拍; pa 是 PA[47:30], 低 30 位补 0
    task automatic inv_addr(input logic [PA_BASE_WIDTH-1:0] pa);
        sdtlb_if.drv.inv_en <= 1'b1;
        sdtlb_if.drv.inv_pa <= {pa, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
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
        sdtlb_if.drv.req_valid     <= 1'b0;
        sdtlb_if.drv.req_pa      <= '0;
        sdtlb_if.drv.fill_valid      <= 1'b0;
        sdtlb_if.drv.fill_pa_base  <= '0;
        sdtlb_if.drv.fill_pa_up    <= '0;
        sdtlb_if.drv.fill_eid      <= '0;
        sdtlb_if.drv.fill_token_id <= '0;
        sdtlb_if.drv.fill_s_pfn    <= '0;
        sdtlb_if.drv.inv_all     <= 1'b0;
        sdtlb_if.drv.inv_en      <= 1'b0;
        sdtlb_if.drv.inv_pa      <= '0;

        // 复位由 crg 产生: 等它释放, 再等两拍让接口输入生效
        wait (rst_n === 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 空表: 查表不命中, 命中读出全 0
        set_req(.high(12'hfff), .idx(5'h1f));
        chk("empty: req_hit = 0", rsp_hit == 1'b0);
        chk("empty: 命中 Tag 读出全 0", rsp_tag == '0);
        chk("empty: 命中 Data 读出全 0", rsp_data == '0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 装填页式条目: base[4:0] == pa_up (闭区间退化成一个 1GB 页), 填到 0 号条目
        fill_one(
            .base({12'hfff, 5'h1f}),
            .up(5'h1f),
            .eid('1),
            .tok('1),
            .pfn(18'h33333)
        );
        repeat (10) @(sdtlb_if.drv);

        // 命中: Tag 与 Data 两个 struct 内容都要对得上
        set_req(.high(12'hfff), .idx(5'h1f));
        chk("page: req_hit = 1", rsp_hit == 1'b1);
        chk("page: Tag struct (base/up/valid)",
            (rsp_tag.pa_base == {12'hfff, 5'h1f}) &&
            (rsp_tag.pa_up == 5'h1f) &&
            (rsp_tag.valid == 1'b1));
        chk("page: Data struct (eid/token_id)",
            (rsp_data.eid == '1) && (rsp_data.token_id == '1));
        chk("page: Data struct (s_pfn)",
            (rsp_data.s_pfn == 18'h33333));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 打 1 拍: 命中向量的比较链在请求拍末才被采到, 请求拍看不到本次请求的响应,
        // 响应要到下一拍才有效 (两次采样分别落在请求拍与响应拍)
        sdtlb_if.drv.req_valid <= 1'b1;
        sdtlb_if.drv.req_pa  <= {12'hfff, 5'h1f, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        @(sdtlb_if.drv);                                // 请求拍
        sample_rsp();
        chk("latency: 请求当拍无命中", rsp_hit == 1'b0);
        chk("latency: 请求当拍读出全 0", (rsp_tag == '0) && (rsp_data == '0));
        sdtlb_if.drv.req_valid <= 1'b0;
        @(sdtlb_if.drv);                                // 响应拍
        sample_rsp();
        chk("latency: 下一拍才命中", rsp_hit == 1'b1);
        chk("latency: 下一拍读出正确",
            (rsp_tag.pa_base == {12'hfff, 5'h1f}) && (rsp_data.s_pfn == 18'h33333));
        repeat (10) @(sdtlb_if.drv);

        // 同段高位、相邻页号: 页式条目只覆盖一页, 应该不命中
        set_req(.high(12'hfff), .idx(5'h1e));
        chk("page: 相邻页不命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 第二个条目: 轮转指针走一格, 该填到 1 号条目 (覆盖"非 0 条目也能被写"
        // 与"按地址选中正确的条目, 数据不串扰")
        fill_one(
            .base({12'h001, 5'd0}),
            .up(5'd0),
            .eid(11'h055),
            .tok(10'h0aa),
            .pfn(18'h0cccc)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h001), .idx(5'd0));
        chk("fill#2: 命中且落在 1 号条目",
            (rsp_hit == 1'b1) && (rsp_tag.pa_base == {12'h001, 5'd0}));
        chk("fill#2: Data 内容 (不串扰)",
            (rsp_data.eid == 11'h055) &&
            (rsp_data.token_id == 10'h0aa) &&
            (rsp_data.s_pfn == 18'h0cccc));
        repeat (10) @(sdtlb_if.drv);

        // 回到 0 号条目的地址: 仍然命中, 且读回的是它自己的数据
        set_req(.high(12'hfff), .idx(5'h1f));
        chk("fill#1 仍在 (两个条目各自独立)",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'h33333));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 段式条目: pa_up > pa_base[4:0], 一个条目覆盖 4~8 共 5 个 1GB 页
        fill_one(
            .base({12'h002, 5'd4}),
            .up(5'd8),
            .eid(11'h123),
            .tok(10'h2aa),
            .pfn(18'h15555)
        );
        repeat (10) @(sdtlb_if.drv);

        // 闭区间内: 左端 / 中间 / 右端 都命中
        set_req(.high(12'h002), .idx(5'd4));
        chk("seg: 左端命中 (闭区间)",
            (rsp_hit == 1'b1) &&
            (rsp_tag.pa_base == {12'h002, 5'd4}) &&
            (rsp_tag.pa_up == 5'd8));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd6));
        chk("seg: 中间命中",
            (rsp_hit == 1'b1) &&
            (rsp_data.s_pfn == 18'h15555));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd8));
        chk("seg: 右端命中 (闭区间)", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 闭区间外 / 段高位不同: 都不命中
        set_req(.high(12'h002), .idx(5'd3));
        chk("seg: 左端外不命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h002), .idx(5'd9));
        chk("seg: 右端外不命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h003), .idx(5'd6));
        chk("seg: 段高位不同不命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // 端口收的是整条 PA[47:0]: 页内偏移 PA[29:0] 与命中无关, 只有 PA[47:35] 与 PA[34:30] 参与判定
        set_req(.high(12'h002), .idx(5'd6), .offset(48'h0000_0000_00a5));
        chk("seg: 段内带页内偏移仍命中 (偏移不参与判定)", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 段区间是 [4, 8]: 请求 PA[34:30] = 9 (段外) 时, 就算页内偏移的低 5 位是 5 (落在段内)
        // 也必须不命中 —— 若实现把范围判定切成了整条 PA 的低 5 位 (PA[4:0]), 这里就会误命中
        set_req(.high(12'h002), .idx(5'd9), .offset(48'h0000_0000_0005));
        chk("seg: 段外不命中 (范围判定看 PA[34:30], 不是 PA[4:0])", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 流水线: req_valid 可以拍拍有效 (本拍给地址, 下一拍换新地址且 req_valid 保持),
        // 响应逐拍滞后 1 拍出现, 且不会串到别的地址上
        sdtlb_if.drv.req_valid <= 1'b1;
        sdtlb_if.drv.req_pa  <= {12'hfff, 5'h1f, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};   // A: 命中
        @(sdtlb_if.drv);                                // 请求拍 A
        sdtlb_if.drv.req_pa  <= {12'h001, 5'd0, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};    // B: 命中
        @(sdtlb_if.drv);                                // 请求拍 B; 响应拍 A
        sample_rsp();
        chk("pipeline: 第 2 拍出 A 的响应",
            (rsp_hit == 1'b1) && (rsp_tag.pa_base == {12'hfff, 5'h1f}) &&
            (rsp_data.s_pfn == 18'h33333));
        sdtlb_if.drv.req_pa  <= {12'h002, 5'd9, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};    // C: 未命中
        @(sdtlb_if.drv);                                // 请求拍 C; 响应拍 B
        sample_rsp();
        chk("pipeline: 第 3 拍出 B 的响应",
            (rsp_hit == 1'b1) && (rsp_tag.pa_base == {12'h001, 5'd0}) &&
            (rsp_data.s_pfn == 18'h0cccc));
        sdtlb_if.drv.req_valid <= 1'b0;
        @(sdtlb_if.drv);                                // 响应拍 C
        sample_rsp();
        chk("pipeline: 第 4 拍出 C 的响应 (未命中)",
            (rsp_hit == 1'b0) && (rsp_tag == '0) && (rsp_data == '0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // req_valid 门控: 地址仍落在段内, 但请求只拍了一拍; 响应只在该请求的下一拍有效,
        // 再往后 req_hit 与读出数据都要归 0
        set_req(.high(12'h002), .idx(5'd6));
        chk("req_valid: 请求拍有效 -> 下一拍命中", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);
        sample_rsp();
        chk("req_valid: 请求已撤 -> 命中与读出数据都归 0",
            (rsp_hit == 1'b0) &&
            (rsp_tag == '0) &&
            (rsp_data == '0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 按地址置无效: 只清掉被地址覆盖到的条目
        // 另填一个页式条目, 用来验证"没被覆盖的条目不受影响"
        fill_one(
            .base({12'h010, 5'd20}),
            .up(5'd20),
            .eid(11'h0f0),
            .tok(10'h0f0),
            .pfn(18'h0f0f0)
        );
        repeat (10) @(sdtlb_if.drv);

        // 段高位相同、但落在条目范围外: 不能清掉它
        inv_addr({12'h010, 5'd19});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 同段高位但范围外, 条目不被动", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 段内任意一个地址都应清掉整个段条目
        inv_addr({12'h002, 5'd7});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h002), .idx(5'd7));
        chk("inv: 段内任一地址清掉整个段条目", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // 段高位不同的条目不受影响
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 只作用于被覆盖的条目", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // 精确命中页式条目时清掉它; 未命中时命中读出全 0
        inv_addr({12'h010, 5'd20});
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 页式条目被清掉", rsp_hit == 1'b0);
        chk("inv: 未命中时 Tag / Data 读出全 0",
            (rsp_tag == '0) && (rsp_data == '0));
        repeat (10) @(sdtlb_if.drv);

        // 置无效只清有效位: 重新装填即可恢复, 且读回的是新数据
        fill_one(
            .base({12'h010, 5'd20}),
            .up(5'd20),
            .eid(11'h0e0),
            .tok(10'h0e0),
            .pfn(18'h0e0e0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h010), .idx(5'd20));
        chk("inv: 重新装填后恢复命中, 数据是新的",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'h0e0e0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 置无效全部
        fill_one(
            .base({12'h030, 5'd1}),
            .up(5'd1),
            .eid(11'h0b0),
            .tok(10'h0b0),
            .pfn(18'h0b0b0)
        );
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all 前置: 条目命中", rsp_hit == 1'b1);
        repeat (10) @(sdtlb_if.drv);

        inv_everything();
        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all: 该条目不再命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h010), .idx(5'd20));
        chk("inv_all: 先前填的其它条目也不再命中", rsp_hit == 1'b0);
        repeat (10) @(sdtlb_if.drv);

        // 全部置无效后重新装填仍能命中 (写通路没被破坏)
        fill_one(
            .base({12'h030, 5'd1}),
            .up(5'd1),
            .eid(11'h0a0),
            .tok(10'h0a0),
            .pfn(18'h0a0a0)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h030), .idx(5'd1));
        chk("inv_all 后重新装填可命中",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'h0a0a0));
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 同拍: 全置无效优先于装填 (inv_all 对每个条目都成立, 与轮转指针当前指到谁无关)
        sdtlb_if.drv.fill_pa_base  <= {12'h020, 5'd3};
        sdtlb_if.drv.fill_pa_up    <= 5'd3;
        sdtlb_if.drv.fill_eid      <= 11'h0c0;
        sdtlb_if.drv.fill_token_id <= 10'h0c0;
        sdtlb_if.drv.fill_s_pfn    <= 18'h0c0c0;
        sdtlb_if.drv.fill_valid      <= 1'b1;
        sdtlb_if.drv.inv_all       <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_valid <= 1'b0;
        sdtlb_if.drv.inv_all  <= 1'b0;
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h020), .idx(5'd3));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍: 全置无效赢, 该次装填地址未命中", rsp_hit == 1'b0);

        set_req(.high(12'h030), .idx(5'd1));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍: 全置无效把原有条目也清掉了", rsp_hit == 1'b0);

        // ====================================================================
        // 轮转替换指针, 以及"无效条目同拍被刷新"的竞态
        // 连填 128 次指针正好绕一圈回到起点条目; 起点条目这时仍持有这一圈第一次装填的地址,
        // 于是可以让"指针指到它"与"按它自己的地址置无效 + 装填"发生在同一拍
        fill_one(
            .base({12'h100, 5'd0}),
            .up(5'd0),
            .eid(11'h001),
            .tok(10'h001),
            .pfn(18'h00001)
        );
        for (int i = 1; i < 128; i++) begin
            fill_one(
                .base({12'h100 + 12'(i / 32), 5'(i % 32)}),
                .up(5'(i % 32)),
                .eid(11'(i)),
                .tok(10'(i)),
                .pfn(18'(i))
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
        sdtlb_if.drv.fill_valid      <= 1'b1;
        sdtlb_if.drv.inv_en        <= 1'b1;
        sdtlb_if.drv.inv_pa        <= {12'h100, 5'd0, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_valid <= 1'b0;
        sdtlb_if.drv.inv_en   <= 1'b0;
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h100), .idx(5'd0));
        repeat (10) @(sdtlb_if.drv);
        chk("同拍(无效条目): 置无效赢, 该次装填地址未命中", rsp_hit == 1'b0);

        // 再单独装填一次: 指针已随上一次装填步进, 这里验证轮转与写通路都正常
        fill_one(
            .base({12'h100, 5'd0}),
            .up(5'd0),
            .eid(11'h7fe),
            .tok(10'h3fe),
            .pfn(18'h3fffe)
        );
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h100), .idx(5'd0));
        chk("轮转: 绕圈后重新装填可命中, 数据正确",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'h3fffe));
        repeat (10) @(sdtlb_if.drv);

        // 绕圈时填进去的占位条目各自还在 (抽查第 3 个与最后一个)
        set_req(.high(12'h100), .idx(5'd2));
        chk("轮转: 绕圈里的占位条目仍在 (第 3 个)",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'd2));
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(12'h103), .idx(5'd31));
        chk("轮转: 绕圈里的占位条目仍在 (第 128 个)",
            (rsp_hit == 1'b1) && (rsp_data.s_pfn == 18'd127));
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
