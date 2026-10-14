`timescale 1ns/1ps
module tb_sdptw;

    import sdecoder_pkg::*;

    // 表基地址: 软件约定一级表 16B 对界, 二级表 8B 对界.
    // 每个一级条目自己有 32 个二级条目 (256B), 所以二级表基址按 region 分摊
    localparam logic [PA_WIDTH-1:0] L1_BASE = 48'h0001_0000;
    localparam logic [PA_WIDTH-1:0] L2_BASE = 48'h0002_0000;
    localparam int unsigned TIMEOUT = 100;      // 单个握手的等待上限 (拍), 防 tb 挂死

    logic                       clk;
    logic                       rst_n;

    int                         errors = 0;
    int                         checks = 0;
    int unsigned                rd_before;      // 读次数快照

    // ---- DUT 端口 ----
    logic [PA_WIDTH-1:0]        sdt_l1_base;

    logic                       req_valid;
    logic [PA_BASE_WIDTH-1:0]   req_pa;
    logic                       req_ready;
    logic                       rsp_valid;
    logic                       rsp_ready;
    SDT_L1_ITEM_t               rsp_sdt_l1_item;
    SDT_L2_ITEM_t               rsp_sdt_l2_item;
    logic                       rsp_sdt_l2_read;

    logic [PA_WIDTH-1:0]        tw_araddr;
    logic                       tw_arvalid;
    logic                       tw_arready;
    logic [127:0]               tw_rdata;
    logic                       tw_rvalid;
    logic                       tw_rready;

    // 最近一次结果 (在 rsp_valid 那一拍采下来)
    SDT_L1_ITEM_t               rsp_l1;
    SDT_L2_ITEM_t               rsp_l2;
    logic                       rsp_l2_read;

    // 时钟与复位由 crg 生成 (单时钟域, tb 内不出现 #NUM 延时)
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

    sdptw dut (
        .clk                (clk                ),
        .rst_n              (rst_n              ),

        .sdt_l1_base        (sdt_l1_base        ),

        .req_valid          (req_valid          ),
        .req_pa             (req_pa             ),
        .req_ready          (req_ready          ),
        .rsp_valid          (rsp_valid          ),
        .rsp_ready          (rsp_ready          ),
        .rsp_sdt_l1_item    (rsp_sdt_l1_item    ),
        .rsp_sdt_l2_item    (rsp_sdt_l2_item    ),
        .rsp_sdt_l2_read    (rsp_sdt_l2_read    ),

        .tw_araddr          (tw_araddr          ),
        .tw_arvalid         (tw_arvalid         ),
        .tw_arready         (tw_arready         ),

        .tw_rdata           (tw_rdata           ),
        .tw_rvalid          (tw_rvalid          ),
        .tw_rready          (tw_rready          )
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdptw, "+all");
        $display("===============================================");
    end
`endif

    // ========================================================================
    // 本地存储模型: AXI4-Lite 读从端 (暂时没有读错误入口), 按字节地址存 16B/8B 条目.
    // AR 被接收后隔 rsp_delay 拍回一拍 R, rvalid 保持到被 rready 取走;
    // 记录读次数, 最近两次读的地址 (一次 walk 最多两次读)
    // ========================================================================
    logic [127:0]               mem [logic [PA_WIDTH-1:0]];
    int unsigned                rd_cnt;
    logic [PA_WIDTH-1:0]        last_rd_addr;
    logic [PA_WIDTH-1:0]        prev_rd_addr;
    int unsigned                rsp_delay;      // AR 到 R 之间多等几拍 (0 = 下一拍回)

    logic                       r_pend;         // 已收 AR, 还没给出 R
    int unsigned                r_wait;

    function automatic logic [127:0] mem_read(input logic [PA_WIDTH-1:0] addr);
        if (mem.exists(addr)) begin
            return mem[addr];
        end
        else begin
            return '0;                          // 没写过的条目按全 0 读 (有效位为 0)
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tw_rvalid    <= 1'b0;
            tw_rdata     <= '0;
            r_pend       <= 1'b0;
            r_wait       <= 0;
            rd_cnt       <= 0;
            last_rd_addr <= '0;
            prev_rd_addr <= '0;
        end
        else if (tw_rvalid && tw_rready) begin
            tw_rvalid <= 1'b0;                  // R 被取走
        end
        else if (!tw_rvalid) begin
            if (r_pend) begin
                if (r_wait == 0) begin
                    tw_rvalid <= 1'b1;
                    tw_rdata  <= mem_read(last_rd_addr);
                    r_pend    <= 1'b0;
                end
                else begin
                    r_wait <= r_wait - 1;
                end
            end
            else if (tw_arvalid && tw_arready) begin
                rd_cnt       <= rd_cnt + 1;
                prev_rd_addr <= last_rd_addr;
                last_rd_addr <= tw_araddr;
                r_wait       <= rsp_delay;
                r_pend       <= 1'b1;
            end
        end
    end

    // ========================================================================
    // 表项与请求地址的构造
    // ========================================================================
    // 一级表索引: PA[47:35] (本 tb 只打 PA[47] = 0 的地址: SDecoder 只处理 Mem 空间)
    function automatic logic [PA_WIDTH-1:0] l1_addr(input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH] region);
        return {L1_BASE[PA_WIDTH-1:4], 4'h0} +
               {{(PA_WIDTH - (PA_BASE_WIDTH - PA_UP_WIDTH) - 4){1'b0}}, region, 4'h0};
    endfunction

    // 每个一级条目自己的二级表 (32 个 8B 条目 = 256B)
    function automatic logic [PA_WIDTH-1:0] l2_base_of(input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH] region);
        return L2_BASE + {{(PA_WIDTH - (PA_BASE_WIDTH - PA_UP_WIDTH)){1'b0}}, region, 8'h0};
    endfunction

    // 二级表索引: PA[34:30]
    function automatic logic [PA_WIDTH-1:0] l2_addr(
        input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH]   region,
        input logic [PA_UP_WIDTH-1:0]               page
    );
        return l2_base_of(region) +
               {{(PA_WIDTH - PA_UP_WIDTH - 3){1'b0}}, page, 3'h0};
    endfunction

    // walk 请求地址: {PA[47:35], PA[34:30]}
    function automatic logic [PA_BASE_WIDTH-1:0] mk_req_pa(
        input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH]   region,
        input logic [PA_UP_WIDTH-1:0]               page
    );
        return {region, page};
    endfunction

    task automatic set_l1_item(
        input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH]   region,
        input logic                                 valid,
        input logic                                 type_bit,
        input logic [PA_UP_WIDTH-1:0]               seg_base,
        input logic [PA_UP_WIDTH-1:0]               seg_len,
        input logic [S_PFN_WIDTH-1:0]               pfn,
        input logic [EID_WIDTH-1:0]                 eid,
        input logic [TOKEN_ID_WIDTH-1:0]            tok
    );
        SDT_L1_ITEM_t item;
        item = '{rsvd: '0, l2_base: l2_base_of(region)[PA_WIDTH-1:3], eid: eid, token_id: tok,
                  s_pfn: pfn, seg_len: seg_len, seg_base: seg_base,
                  type_bit: type_bit, valid: valid};
        mem[l1_addr(region)] = item;
    endtask

    // 段式一级条目
    task automatic set_l1_seg(
        input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH]   region,
        input logic [PA_UP_WIDTH-1:0]               seg_base,
        input logic [PA_UP_WIDTH-1:0]               seg_len,
        input logic [S_PFN_WIDTH-1:0]               pfn,
        input logic [EID_WIDTH-1:0]                 eid,
        input logic [TOKEN_ID_WIDTH-1:0]            tok
    );
        set_l1_item(region, 1'b1, 1'b1, seg_base, seg_len, pfn, eid, tok);
    endtask

    task automatic set_l2(
        input logic [PA_BASE_WIDTH-1:PA_UP_WIDTH]   region,
        input logic [PA_UP_WIDTH-1:0]               page,
        input logic                                 valid,
        input logic [S_PFN_WIDTH-1:0]               pfn,
        input logic [EID_WIDTH-1:0]                 eid,
        input logic [TOKEN_ID_WIDTH-1:0]            tok
    );
        SDT_L2_ITEM_t item;
        item = '{rsvd: '0, eid: eid, token_id: tok, s_pfn: pfn, valid: valid};
        mem[l2_addr(region, page)] = item;
    endtask

    // ========================================================================
    // 握手与检查
    // ========================================================================
    task automatic chk(input string name, input logic cond);
        checks++;
        if (!cond) begin
            errors++;
            $display("FAIL %-52s", name);
        end
        else begin
            $display("ok   %-52s", name);
        end
    endtask

    // 发一个 walk 请求: 本沿被接收后 req_valid 拉低 (激励统一在下降沿给)
    task automatic walk_start(input logic [PA_BASE_WIDTH-1:0] pa);
        while (!req_ready) @(negedge clk);
        @(negedge clk);
        req_valid  = 1'b1;
        req_pa     = pa;
        @(posedge clk);                     // 本沿完成接收 (ready 已在上一拍确认)
        @(negedge clk);
        req_valid  = 1'b0;
    endtask

    // 等结果并在 rsp_valid 那一拍采样 (不改 rsp_ready)
    task automatic wait_rsp();
        int unsigned n;
        n = 0;
        while (!rsp_valid && (n < TIMEOUT)) begin
            @(negedge clk);
            n++;
        end
        if (!rsp_valid) begin
            $display("[DBG] 超时: state=%b arvalid=%b arready=%b rvalid=%b rsp_ready=%b",
                     dut.state, tw_arvalid, tw_arready, tw_rvalid, rsp_ready);
            $fatal(1, "wait_rsp 超时: 没有 rsp_valid");
        end
        rsp_l1      = rsp_sdt_l1_item;
        rsp_l2      = rsp_sdt_l2_item;
        rsp_l2_read = rsp_sdt_l2_read;
    endtask

    // 收走结果 (rsp_ready = 1 时, 结果在下一个上升沿被取走)
    task automatic take_rsp();
        @(negedge clk);
    endtask

    // 一个完整的 walk: 发请求 + 收结果
    task automatic walk_one(input logic [PA_BASE_WIDTH-1:0] pa);
        walk_start(pa);
        wait_rsp();
        take_rsp();
    endtask

    // ========================================================================
    initial begin
        sdt_l1_base    = L1_BASE;
        req_valid      = 1'b0;
        req_pa         = '0;
        rsp_ready      = 1'b1;
        tw_arready     = 1'b1;
        rsp_delay      = 0;                 // tw_rdata / tw_rvalid 由下面的从端模型驱动

        wait (rst_n === 1'b1);
        repeat (5) @(negedge clk);

        // ====================================================================
        // 复位后的静态状态
        chk("复位后: req_ready = 1", req_ready == 1'b1);
        chk("复位后: rsp_valid = 0", rsp_valid == 1'b0);
        chk("复位后: tw_arvalid = 0", tw_arvalid == 1'b0);
        chk("复位后: rsp_sdt_l2_read = 0", rsp_sdt_l2_read == 1'b0);

        // ====================================================================
        // Type = 1: 该区间有 1 个段表 + N 个页表. PA 落在段区间内 -> 段式收工, 只读一级
        // region 2: 段区间 [4, 8] (闭区间), S_PFN 0x15555
        set_l1_seg(.region(12'h002), .seg_base(5'd4), .seg_len(5'd4),
                   .pfn(18'h15555), .eid(11'h123), .tok(10'h2aa));

        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h002, 5'd6));
        chk("段式: 只读一级表一次", (rd_cnt - rd_before) == 1);
        chk("段式: rsp_sdt_l2_read = 0", rsp_l2_read == 1'b0);
        chk("段式: 一级条目原样回 (base/len/type/valid)",
            (rsp_l1.valid == 1'b1) && (rsp_l1.type_bit == 1'b1) &&
            (rsp_l1.seg_base == 5'd4) && (rsp_l1.seg_len == 5'd4));
        chk("段式: 一级条目内容 (s_pfn / eid / token)",
            (rsp_l1.s_pfn == 18'h15555) && (rsp_l1.eid == 11'h123) &&
            (rsp_l1.token_id == 10'h2aa));
        chk("段式: 没读二级, 二级条目输出清 0", rsp_l2 == '0);
        chk("段式: 一级读地址 = 表基地址 + 段高位 * 16B", last_rd_addr == l1_addr(12'h002));

        // 闭区间两端
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h002, 5'd4));
        chk("段式: 左端命中 (闭区间), 只读一级",
            (rsp_l2_read == 1'b0) && ((rd_cnt - rd_before) == 1));
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h002, 5'd8));
        chk("段式: 右端命中 (闭区间), 只读一级",
            (rsp_l2_read == 1'b0) && ((rd_cnt - rd_before) == 1));

        // ====================================================================
        // 段外: 该区间的页表来接 -> 读二级 (这就是"段与页共存"的能力)
        set_l2(.region(12'h002), .page(5'd9), .valid(1'b1),
               .pfn(18'h0cccc), .eid(11'h0f0), .tok(10'h0f0));
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h002, 5'd9));
        chk("段外: 读了一级 + 二级 (两次)", (rd_cnt - rd_before) == 2);
        chk("段外: rsp_sdt_l2_read = 1", rsp_l2_read == 1'b1);
        chk("段外: 二级条目内容 (s_pfn / eid / token / valid)",
            (rsp_l2.valid == 1'b1) && (rsp_l2.s_pfn == 18'h0cccc) &&
            (rsp_l2.eid == 11'h0f0) && (rsp_l2.token_id == 10'h0f0));
        chk("段外: 两次读的地址分别是 一级 / 二级",
            (prev_rd_addr == l1_addr(12'h002)) && (last_rd_addr == l2_addr(12'h002, 5'd9)));

        // 紧接着做一次段式命中: 端口上的二级条目必须清 0, 不能残留上一次的页式结果
        walk_one(mk_req_pa(12'h002, 5'd6));
        chk("段式命中: 上一次的二级条目被清 0 (不残留)",
            (rsp_l2_read == 1'b0) && (rsp_l2 == '0) && (rsp_l1.valid == 1'b1));

        // 段高位不同 -> 另一个一级条目 (没写过, 读回全 0)
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h003, 5'd6));
        chk("段高位不同: 一级条目无效, 不再读二级",
            (rsp_l1.valid == 1'b0) && (rsp_l2_read == 1'b0) && ((rd_cnt - rd_before) == 1));

        // ====================================================================
        // Type = 0: 该区间均为页表 -> 直接读二级
        // 段区间故意给成能罩住被查页的 [0, 31]: 万一实现忘了看 type_bit (按区间判), 就会错在
        // 不读二级, 被下面的 rd_cnt 抓到
        set_l1_item(.region(12'h006), .valid(1'b1), .type_bit(1'b0), .seg_base(5'd0),
                    .seg_len(5'd31), .pfn(18'h0), .eid(11'h0), .tok(10'h0));
        set_l2(.region(12'h006), .page(5'd3), .valid(1'b1),
               .pfn(18'h0ddd), .eid(11'h0e1), .tok(10'h0e1));
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h006, 5'd3));
        chk("Type = 0: 走二级 (两次读)", (rd_cnt - rd_before) == 2);
        chk("Type = 0: rsp_sdt_l2_read = 1 且二级内容正确",
            (rsp_l2_read == 1'b1) && (rsp_l2.valid == 1'b1) && (rsp_l2.s_pfn == 18'h0ddd));
        chk("Type = 0: 两次读的地址分别是 一级 / 二级",
            (prev_rd_addr == l1_addr(12'h006)) && (last_rd_addr == l2_addr(12'h006, 5'd3)));

        // ====================================================================
        // 二级条目无效: 段表条目 + 段外, 读两次但二级 valid = 0
        // 注意: 这一拍与上面"段式命中"那一拍, 一级 / 二级的 valid 位完全一样 —— 上级只有靠
        //       rsp_sdt_l2_read 才能把这两种情况分开 (段式命中 vs 段外且二级无效)
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h002, 5'd10));        // page 10 没写过
        chk("二级条目无效: 读两次且 rsp_sdt_l2_read = 1",
            ((rd_cnt - rd_before) == 2) && (rsp_l2_read == 1'b1));
        chk("二级条目无效: 二级 valid = 0 (一级仍有效)",
            (rsp_l2.valid == 1'b0) && (rsp_l1.valid == 1'b1));

        // ====================================================================
        // 段区间上界正好到 31 (软件约束的合法边界, 断言不应触发)
        set_l1_seg(.region(12'h009), .seg_base(5'd28), .seg_len(5'd3),
                   .pfn(18'h00123), .eid(11'h002), .tok(10'h002));
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h009, 5'd31));
        chk("段区间到 31: 右端命中, 只读一级",
            (rsp_l2_read == 1'b0) && ((rd_cnt - rd_before) == 1) && (rsp_l1.valid == 1'b1));
        set_l2(.region(12'h009), .page(5'd27), .valid(1'b1),
               .pfn(18'h0eee), .eid(11'h0e2), .tok(10'h0e2));
        rd_before = rd_cnt;
        walk_one(mk_req_pa(12'h009, 5'd27));
        chk("段区间到 31: 左端外走二级",
            (rsp_l2_read == 1'b1) && ((rd_cnt - rd_before) == 2) && (rsp_l2.s_pfn == 18'h0eee));

        // ====================================================================
        // AR 通道: 从端不收时不撤地址、也不收新请求
        tw_arready = 1'b0;
        walk_start(mk_req_pa(12'h002, 5'd6));
        repeat (3) @(negedge clk);
        chk("存储忙: tw_arvalid 保持", tw_arvalid == 1'b1);
        chk("存储忙: 读地址保持", tw_araddr == l1_addr(12'h002));
        chk("存储忙: 不再收新请求", req_ready == 1'b0);
        tw_arready = 1'b1;
        @(negedge clk);                       // 这一拍 AR 被接收
        chk("AR 被接收后: tw_arvalid 撤销 (AXI 要求)", tw_arvalid == 1'b0);
        wait_rsp();
        chk("存储忙解除: 结果正确 (段式命中)",
            (rsp_l2_read == 1'b0) && (rsp_l1.s_pfn == 18'h15555));
        take_rsp();

        // ====================================================================
        // R 通道迟到: 发出 AR 后 R 隔几拍才回来, 结果不许提前出来
        rsp_delay = 2;
        walk_start(mk_req_pa(12'h002, 5'd6));
        repeat (2) @(negedge clk);
        chk("R 迟到: tw_rready 保持 (等着收)", tw_rready == 1'b1);
        chk("R 迟到: rsp_valid 不提前", rsp_valid == 1'b0);
        wait_rsp();
        chk("R 迟到: 结果仍然正确", (rsp_l2_read == 1'b0) && (rsp_l1.s_pfn == 18'h15555));
        take_rsp();
        rsp_delay = 0;

        // ====================================================================
        // 下游不收结果: 结果与两个条目都保持, 新请求也不许进
        rsp_ready  = 1'b0;
        walk_start(mk_req_pa(12'h002, 5'd6));
        wait_rsp();
        chk("结果未被取走: rsp_valid 保持", rsp_valid == 1'b1);
        chk("结果未被取走: req_ready = 0", req_ready == 1'b0);
        req_valid  = 1'b1;
        req_pa     = mk_req_pa(12'h002, 5'd4);
        repeat (3) @(negedge clk);
        chk("结果未被取走: 新请求不被接收", req_ready == 1'b0);
        chk("结果未被取走: 结果保持不变",
            (rsp_valid == 1'b1) &&
            (rsp_sdt_l1_item == rsp_l1) && (rsp_sdt_l2_item == rsp_l2) &&
            (rsp_sdt_l2_read == rsp_l2_read));
        req_valid  = 1'b0;
        rsp_ready  = 1'b1;
        @(negedge clk);
        chk("结果取走后: rsp_valid 归 0", rsp_valid == 1'b0);
        chk("结果取走后: req_ready 恢复", req_ready == 1'b1);

        // ====================================================================
        // 背靠背: 上一个结果没取走时挂上第二个请求, 两个结果不能串
        set_l1_seg(.region(12'h00a), .seg_base(5'd0), .seg_len(5'd0),
                   .pfn(18'h00777), .eid(11'h077), .tok(10'h077));
        req_valid  = 1'b1;
        req_pa     = mk_req_pa(12'h002, 5'd6);      // A: eid 0x123
        @(posedge clk);                             // A 被接收
        req_pa     = mk_req_pa(12'h00a, 5'd0);      // B: eid 0x077
        wait_rsp();
        chk("背靠背: 第 1 个结果是 A", (rsp_l2_read == 1'b0) && (rsp_l1.eid == 11'h123));
        take_rsp();
        wait_rsp();
        chk("背靠背: 第 2 个结果是 B",
            (rsp_l2_read == 1'b0) && (rsp_l1.eid == 11'h077) && (rsp_l1.seg_base == 5'd0));
        take_rsp();
        req_valid  = 1'b0;

        // ====================================================================
        repeat (5) @(negedge clk);
        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdptw 单元自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
