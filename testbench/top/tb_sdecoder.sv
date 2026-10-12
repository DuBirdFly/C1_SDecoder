`timescale 1ns/1ps
module tb_sdecoder;

    import sdecoder_pkg::*;

    // 代换表基地址: 软件约定一级表 64KB 对界, 二级表 256B 对界
    localparam logic [PA_WIDTH-1:0] L1_BASE = 48'h0001_0000;
    localparam logic [PA_WIDTH-1:0] L2_BASE = 48'h0002_0000;

    localparam int unsigned TIMEOUT = 400;      // 单个握手的等待上限 (拍), 防 tb 挂死

    logic                       clk;
    logic                       rst_n;

    int                         errors = 0;
    int                         checks = 0;

    SDEC_RSP_t                  rsp;            // 最近一次响应
    int unsigned                rd_before;      // 走表读次数快照
    int unsigned                n_sent;         // 队列满测试里实际发出的请求数

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

    sdecoder_if sdecoder_if (.clk(clk), .rst_n(rst_n));

    sdecoder dut (
        .clk                 (clk                               ),
        .rst_n               (rst_n                             ),

        .req_valid           (sdecoder_if.req_valid             ),
        .req_ready           (sdecoder_if.req_ready             ),
        .req_pa              (sdecoder_if.req_pa                ),
        .req_rw              (sdecoder_if.req_rw                ),
        .req_id              (sdecoder_if.req_id                ),

        .rsp_valid           (sdecoder_if.rsp_valid             ),
        .rsp_ready           (sdecoder_if.rsp_ready             ),
        .rsp_id              (sdecoder_if.rsp_id                ),
        .rsp_fault           (sdecoder_if.rsp_fault             ),
        .rsp_eid             (sdecoder_if.rsp_eid               ),
        .rsp_tokenid         (sdecoder_if.rsp_tokenid           ),
        .rsp_sla             (sdecoder_if.rsp_sla               ),
        .rsp_fcode           (sdecoder_if.rsp_fcode             ),

        .tw_req_valid        (sdecoder_if.tw_req_valid          ),
        .tw_req_ready        (sdecoder_if.tw_req_ready          ),
        .tw_req_addr         (sdecoder_if.tw_req_addr           ),
        .tw_req_size         (sdecoder_if.tw_req_size           ),
        .tw_req_id           (sdecoder_if.tw_req_id             ),
        .tw_rsp_valid        (sdecoder_if.tw_rsp_valid          ),
        .tw_rsp_ready        (sdecoder_if.tw_rsp_ready          ),
        .tw_rsp_data         (sdecoder_if.tw_rsp_data           ),
        .tw_rsp_id           (sdecoder_if.tw_rsp_id             ),
        .tw_rsp_err          (sdecoder_if.tw_rsp_err            ),

        .cfg_enable          (sdecoder_if.cfg_enable            ),
        .cfg_sdt_l1_base     (sdecoder_if.cfg_sdt_l1_base       ),
        .cfg_inv_all         (sdecoder_if.cfg_inv_all           ),
        .cfg_inv_addr_valid  (sdecoder_if.cfg_inv_addr_valid    ),
        .cfg_inv_addr        (sdecoder_if.cfg_inv_addr          ),
        .cfg_inv_busy        (sdecoder_if.cfg_inv_busy          ),

        .errinfo_fcode       (sdecoder_if.errinfo_fcode         ),
        .errinfo_rw          (sdecoder_if.errinfo_rw            ),
        .errinfo_pa          (sdecoder_if.errinfo_pa            )
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(test_pkg::FSDB_LIMIT_SIZE, test_pkg::FSDB_FILENAME, test_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdecoder, "+all");
        $display("===============================================");
    end
`endif

    // ========================================================================
    // 本地存储模型: 按字节地址存 16B 条目, 收到读请求后回一拍数据
    // (tw_* 从端口不放进 clocking block, 由这里的时序逻辑直接驱动)
    // ========================================================================
    logic [127:0]               mem [logic [PA_WIDTH-1:0]];
    int unsigned                tw_rd_cnt;
    logic [1:0]                 inj_err;        // 下一次读返回的错误指示

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
            sdecoder_if.tw_req_ready <= 1'b1;
            sdecoder_if.tw_rsp_valid <= 1'b0;
            sdecoder_if.tw_rsp_data  <= '0;
            sdecoder_if.tw_rsp_id    <= '0;
            sdecoder_if.tw_rsp_err   <= '0;
            tw_rd_cnt                <= 0;
        end
        else begin
            if (sdecoder_if.tw_req_valid && sdecoder_if.tw_req_ready && !sdecoder_if.tw_rsp_valid) begin
                sdecoder_if.tw_rsp_valid <= 1'b1;
                sdecoder_if.tw_rsp_data  <= mem_read(sdecoder_if.tw_req_addr);
                sdecoder_if.tw_rsp_id    <= sdecoder_if.tw_req_id;
                sdecoder_if.tw_rsp_err   <= inj_err;
                tw_rd_cnt                <= tw_rd_cnt + 1;
            end
            else if (sdecoder_if.tw_rsp_valid && sdecoder_if.tw_rsp_ready) begin
                sdecoder_if.tw_rsp_valid <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 表项与请求地址的构造 (与设计方案的索引方式一致)
    // ========================================================================
    function automatic logic [PA_WIDTH-1:0] l1_addr(input logic [PA_L1_IDX_WIDTH-1:0] idx);
        return {L1_BASE[PA_WIDTH-1:4], 4'h0} +
               {{(PA_WIDTH - PA_L1_IDX_WIDTH - 4){1'b0}}, idx, 4'h0};
    endfunction

    function automatic logic [PA_WIDTH-1:0] l2_addr(input logic [PA_UP_WIDTH-1:0] idx);
        return {L2_BASE[PA_WIDTH-1:3], 3'h0} +
               {{(PA_WIDTH - PA_UP_WIDTH - 3){1'b0}}, idx, 3'h0};
    endfunction

    function automatic logic [PA_WIDTH-1:0] mk_pa(
        input logic [PA_L1_IDX_WIDTH-1:0]   region,
        input logic [PA_UP_WIDTH-1:0]       page,
        input logic [PA_OFFSET_WIDTH-1:0]   low
    );
        return {1'b0, region, page, low};
    endfunction

    task automatic set_l1_seg(
        input logic [PA_L1_IDX_WIDTH-1:0]   idx,
        input logic [EID_WIDTH-1:0]         eid,
        input logic [TOKEN_ID_WIDTH-1:0]    tok,
        input logic [S_PFN_WIDTH-1:0]       pfn,
        input logic [4:0]                   seg_base,
        input logic [4:0]                   seg_len,
        input logic                         valid
    );
        SDT_L1_ITEM_t item;
        item = '{rsvd: '0, l2_base: L2_BASE[PA_WIDTH-1:3], eid: eid, token_id: tok, s_pfn: pfn,
                  seg_len: seg_len, seg_base: seg_base, type_bit: 1'b1, valid: valid};
        mem[l1_addr(idx)] = item;
    endtask

    task automatic set_l1_page(input logic [PA_L1_IDX_WIDTH-1:0] idx, input logic valid);
        SDT_L1_ITEM_t item;
        item = '{rsvd: '0, l2_base: L2_BASE[PA_WIDTH-1:3], eid: '0, token_id: '0, s_pfn: '0,
                  seg_len: '0, seg_base: '0, type_bit: 1'b0, valid: valid};
        mem[l1_addr(idx)] = item;
    endtask

    task automatic set_l2(
        input logic [PA_UP_WIDTH-1:0]       idx,
        input logic [EID_WIDTH-1:0]         eid,
        input logic [TOKEN_ID_WIDTH-1:0]    tok,
        input logic [S_PFN_WIDTH-1:0]       pfn,
        input logic                         valid
    );
        SDT_L2_ITEM_t item;
        item = '{rsvd: '0, eid: eid, token_id: tok, s_pfn: pfn, valid: valid};
        mem[l2_addr(idx)] = item;
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

    // 激励统一在下降沿给出 (上升沿采样, 无竞争); req_valid 只拉一拍
    task automatic req_send(
        input logic [PA_WIDTH-1:0]      pa,
        input logic                     rw,
        input logic [REQ_ID_WIDTH-1:0]  id
    );
        while (!sdecoder_if.req_ready) @(negedge clk);
        @(negedge clk);
        sdecoder_if.req_valid = 1'b1;
        sdecoder_if.req_pa    = pa;
        sdecoder_if.req_rw    = rw;
        sdecoder_if.req_id    = id;
        @(posedge clk);                     // 本沿完成接收 (ready 已在上一拍确认)
        @(negedge clk);
        sdecoder_if.req_valid = 1'b0;
    endtask

    // 收一个响应 (rsp_ready 常高)
    task automatic rsp_get();
        int unsigned n;
        n = 0;
        while (!sdecoder_if.rsp_valid && (n < TIMEOUT)) begin
            @(negedge clk);
            n++;
        end
        if (!sdecoder_if.rsp_valid) begin
            $display("[DBG] 超时: cnt=%0d rdp=%0d wrp=%0d eng=%b rspv=%b pp=%b tw_req_vld=%b tw_req_rdy=%b tw_rsp_vld=%b walker=%b",
                     dut.fifo_cnt, dut.rd_ptr, dut.wr_ptr, dut.engine, dut.rsp_vld_r, dut.head_pop,
                     sdecoder_if.tw_req_valid, sdecoder_if.tw_req_ready, sdecoder_if.tw_rsp_valid,
                     dut.u_sdptw.state);
            $fatal(1, "rsp_get 超时: 没有响应");
        end
        rsp = '{req_id: sdecoder_if.rsp_id, fault: sdecoder_if.rsp_fault, fcode: sdecoder_if.rsp_fcode,
                eid: sdecoder_if.rsp_eid, token_id: sdecoder_if.rsp_tokenid, sla: sdecoder_if.rsp_sla};
        @(negedge clk);
    endtask

    // 一个完整的代换: 发请求 + 收响应
    task automatic xact(
        input logic [PA_WIDTH-1:0]      pa,
        input logic                     rw,
        input logic [REQ_ID_WIDTH-1:0]  id
    );
        req_send(pa, rw, id);
        rsp_get();
    endtask

    task automatic inv_by_addr(input logic [PA_BASE_WIDTH-1:0] pa);
        @(negedge clk);
        sdecoder_if.cfg_inv_addr       = pa;
        sdecoder_if.cfg_inv_addr_valid = 1'b1;
        @(negedge clk);
        sdecoder_if.cfg_inv_addr_valid = 1'b0;
    endtask

    task automatic inv_everything();
        @(negedge clk);
        sdecoder_if.cfg_inv_all = 1'b1;
        @(negedge clk);
        sdecoder_if.cfg_inv_all = 1'b0;
    endtask

    // ========================================================================
    initial begin
        sdecoder_if.req_valid          = 1'b0;
        sdecoder_if.req_pa             = '0;
        sdecoder_if.req_rw             = 1'b0;
        sdecoder_if.req_id             = '0;
        sdecoder_if.rsp_ready          = 1'b1;
        sdecoder_if.cfg_enable         = 1'b0;
        sdecoder_if.cfg_sdt_l1_base    = '0;
        sdecoder_if.cfg_inv_all        = 1'b0;
        sdecoder_if.cfg_inv_addr_valid = 1'b0;
        sdecoder_if.cfg_inv_addr       = '0;
        inj_err = 2'b00;

        wait (rst_n === 1'b1);
        repeat (10) @(negedge clk);

        // ====================================================================
        // 配置与使能
        chk("cfg_enable = 0: req_ready = 0", sdecoder_if.req_ready == 1'b0);
        chk("cfg_inv_busy = 0", sdecoder_if.cfg_inv_busy == 1'b0);

        sdecoder_if.cfg_enable      = 1'b1;
        sdecoder_if.cfg_sdt_l1_base = L1_BASE;
        repeat (5) @(negedge clk);
        chk("cfg_enable = 1: req_ready = 1", sdecoder_if.req_ready == 1'b1);

        // ====================================================================
        // 一级条目无效 (读回全 0): 地址非法, 并登记 ERRINFO
        xact(mk_pa(12'h010, 5'd0, 30'h1234), 1'b1, 8'h11);
        chk("L1 无效: 报异常", rsp.fault == 1'b1);
        chk("L1 无效: 异常码 = 地址非法", rsp.fcode == FCODE_ADDR_ILLEGAL);
        chk("L1 无效: rsp_id 与请求一致", rsp.req_id == 8'h11);
        chk("L1 无效: ERRINFO 记录编码 / 地址 / 读写",
            (sdecoder_if.errinfo_fcode == FCODE_ADDR_ILLEGAL) &&
            (sdecoder_if.errinfo_pa == mk_pa(12'h010, 5'd0, 30'h1234)) &&
            (sdecoder_if.errinfo_rw == 1'b1));

        // ====================================================================
        // 段式代换: 一个一级条目覆盖 8~12 五个 1GB 页
        set_l1_seg(.idx(12'h002), .eid(11'h123), .tok(10'h2aa), .pfn(18'h15555),
                   .seg_base(5'd8), .seg_len(5'd4), .valid(1'b1));

        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd10, 30'h0abc), 1'b0, 8'h22);
        chk("段式: 不报异常", rsp.fault == 1'b0);
        chk("段式: EID / TokenID", (rsp.eid == 11'h123) && (rsp.token_id == 10'h2aa));
        chk("段式: SLA = S_PFN + 段内偏移", rsp.sla == {18'h15555 + 18'd2, 30'h0abc});
        chk("段式: 走表只读一级条目", (tw_rd_cnt - rd_before) == 1);

        // 同一页再来: 已回填 SDTLB, 不再走表
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd10, 30'h0abc), 1'b0, 8'h23);
        chk("段式: 第二次命中快表", (rsp.fault == 1'b0) && (tw_rd_cnt == rd_before));

        // 回填的是整段: 段内其它页也应命中
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd12, 30'h0001), 1'b0, 8'h24);
        chk("段式: 段内其它页命中且偏移正确",
            (rsp.fault == 1'b0) && (rsp.sla == {18'h15555 + 18'd4, 30'h0001}) &&
            (tw_rd_cnt == rd_before));

        // 段外: 该区间没有页表条目, 报地址非法
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd20, 30'h0), 1'b0, 8'h25);
        chk("段式: 段外走页表且二级条目无效",
            (rsp.fault == 1'b1) && (rsp.fcode == FCODE_ADDR_ILLEGAL) &&
            ((tw_rd_cnt - rd_before) == 2));

        // ====================================================================
        // 页式代换: 二级条目
        set_l1_page(.idx(12'h003), .valid(1'b1));
        set_l2(.idx(5'd3), .eid(11'h0f0), .tok(10'h0f0), .pfn(18'h0cccc), .valid(1'b1));

        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h003, 5'd3, 30'h0def), 1'b0, 8'h33);
        chk("页式: 不报异常", rsp.fault == 1'b0);
        chk("页式: EID / TokenID / SLA",
            (rsp.eid == 11'h0f0) && (rsp.token_id == 10'h0f0) &&
            (rsp.sla == {18'h0cccc, 30'h0def}));
        chk("页式: 走表读了一级加二级", (tw_rd_cnt - rd_before) == 2);

        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h003, 5'd3, 30'h0def), 1'b0, 8'h34);
        chk("页式: 第二次命中快表", (rsp.fault == 1'b0) && (tw_rd_cnt == rd_before));

        // 二级条目无效
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h003, 5'd5, 30'h0), 1'b0, 8'h35);
        chk("页式: 二级条目无效报地址非法",
            (rsp.fault == 1'b1) && (rsp.fcode == FCODE_ADDR_ILLEGAL) &&
            ((tw_rd_cnt - rd_before) == 2));

        // ====================================================================
        // PA[47] = 1: IO 空间, 本 IP 不处理, 直接报地址非法且不走表
        rd_before = tw_rd_cnt;
        xact({1'b1, mk_pa(12'h003, 5'd3, 30'h0)[PA_WIDTH-2:0]}, 1'b0, 8'h36);
        chk("PA[47] = 1: 报地址非法",
            (rsp.fault == 1'b1) && (rsp.fcode == FCODE_ADDR_ILLEGAL));
        chk("PA[47] = 1: 不走表", tw_rd_cnt == rd_before);

        // ====================================================================
        // 段式 SLA 溢出: S_PFN 加段内偏移产生进位
        set_l1_seg(.idx(12'h004), .eid(11'h001), .tok(10'h001), .pfn(18'h3ffff),
                   .seg_base(5'd0), .seg_len(5'd4), .valid(1'b1));
        xact(mk_pa(12'h004, 5'd2, 30'h0), 1'b0, 8'h44);
        chk("SLA 溢出: 报地址非法",
            (rsp.fault == 1'b1) && (rsp.fcode == FCODE_ADDR_ILLEGAL));

        // ====================================================================
        // 走表访存不可纠错: 报机器检查错, 并登记 ERRINFO
        set_l1_page(.idx(12'h006), .valid(1'b1));
        set_l2(.idx(5'd1), .eid(11'h011), .tok(10'h011), .pfn(18'h01111), .valid(1'b1));
        inj_err = 2'b10;
        xact(mk_pa(12'h006, 5'd1, 30'h0), 1'b0, 8'h55);
        inj_err = 2'b00;
        chk("读错误注入: 报不可纠错",
            (rsp.fault == 1'b1) && (rsp.fcode == FCODE_UNCORRECT));
        chk("读错误注入: ERRINFO 记录不可纠错",
            sdecoder_if.errinfo_fcode == FCODE_UNCORRECT);

        // 可纠错错误按正常处理
        inj_err = 2'b01;
        xact(mk_pa(12'h006, 5'd1, 30'h0), 1'b0, 8'h56);
        inj_err = 2'b00;
        chk("可纠错错误: 按正常处理",
            (rsp.fault == 1'b0) && (rsp.sla == {18'h01111, 30'h0}));

        // ====================================================================
        // 按地址置无效: 段条目被清掉后需要重新走表
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd10, 30'h0abc), 1'b0, 8'h66);
        chk("inv(地址) 前置: 命中快表", (rsp.fault == 1'b0) && (tw_rd_cnt == rd_before));

        inv_by_addr(mk_pa(12'h002, 5'd10, 30'h0)[PA_L1_IDX_MSB:PA_UP_LSB]);
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd10, 30'h0abc), 1'b0, 8'h67);
        chk("inv(地址): 置无效后重新走表",
            (rsp.fault == 1'b0) && ((tw_rd_cnt - rd_before) == 1));
        chk("inv(地址): 结果仍然正确", rsp.sla == {18'h15555 + 18'd2, 30'h0abc});

        // 范围外的地址置无效不影响该条目
        inv_by_addr(mk_pa(12'h002, 5'd20, 30'h0)[PA_L1_IDX_MSB:PA_UP_LSB]);
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h002, 5'd10, 30'h0abc), 1'b0, 8'h68);
        chk("inv(地址): 范围外不误清", (rsp.fault == 1'b0) && (tw_rd_cnt == rd_before));

        // ====================================================================
        // 全部置无效
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h003, 5'd3, 30'h0def), 1'b0, 8'h71);
        chk("inv_all 前置: 命中快表", (rsp.fault == 1'b0) && (tw_rd_cnt == rd_before));

        inv_everything();
        rd_before = tw_rd_cnt;
        xact(mk_pa(12'h003, 5'd3, 30'h0def), 1'b0, 8'h72);
        chk("inv_all: 置无效后重新走表",
            (rsp.fault == 1'b0) && ((tw_rd_cnt - rd_before) == 2));
        chk("inv_all: 结果仍然正确", rsp.sla == {18'h0cccc, 30'h0def});

        // ====================================================================
        // 下游不收响应时反压上游, 并且响应严格按请求顺序返回
        sdecoder_if.rsp_ready = 1'b0;
        repeat (5) @(negedge clk);

        n_sent = 0;
        for (int i = 0; i < 8; i++) begin
            @(negedge clk);
            if (!sdecoder_if.req_ready) begin
                break;
            end
            req_send(mk_pa(12'h020 + 12'(i), 5'd0, 30'h0), 1'b0, 8'hc0 + 8'(i));
            n_sent++;
        end
        repeat (10) @(negedge clk);
        chk("队列满: req_ready 拉低", sdecoder_if.req_ready == 1'b0);
        chk("队列满: 至少积压了 2 个请求", n_sent >= 2);

        sdecoder_if.rsp_ready = 1'b1;
        for (int i = 0; i < n_sent; i++) begin
            rsp_get();
            chk($sformatf("顺序: 第 %0d 个响应 id 正确", i), rsp.req_id == (8'hc0 + 8'(i)));
        end
        repeat (5) @(negedge clk);
        chk("排空后 req_ready 恢复", sdecoder_if.req_ready == 1'b1);

        // ====================================================================
        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdecoder 自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
