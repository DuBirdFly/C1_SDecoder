`timescale 1ns/1ps
module tb_sdior;

    import sdecoder_pkg::*;

    // 端口都是简单的寄存器访问信号 (没有总线协议), 所以不建 interface, 直接在 tb 里驱动
    logic                           clk;
    logic                           rst_n;

    int                             errors = 0;
    int                             checks = 0;

    // ---- 驱动 ----
    logic                           cfg_wr;
    logic                           cfg_rd;
    logic [SDIOR_ADDR_WIDTH-1:0]    cfg_addr;
    logic [SDIOR_DATA_WIDTH-1:0]    cfg_wdata;

    // ---- 观察 ----
    logic [SDIOR_DATA_WIDTH-1:0]    cfg_rdata;
    logic [PA_WIDTH-1:0]            sdt_l1_base;
    logic                           inv_all;
    logic                           inv_en;
    logic [PA_WIDTH-1:0]            inv_pa;

    // 读任务采样回来的值 (组合读, 在"读当拍"的沿上取)
    logic [SDIOR_DATA_WIDTH-1:0]    rd_data;
    logic                           rd_inv_all;
    logic                           rd_inv_en;

    // 脉冲宽度观察: 数 inv_* 在上升沿上压了几拍.
    // 写完之后只在下一个下降沿采一次 inv_* 是抓不到"脉冲被拉宽"的 (那时早已归 0),
    // 所以用计数器量宽度: 一次写正好占 1 个上升沿.
    int unsigned                    inv_all_cycles;
    int unsigned                    inv_en_cycles;
    int unsigned                    cyc_before;
    int unsigned                    cyc_before2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_all_cycles <= 0;
            inv_en_cycles  <= 0;
        end
        else begin
            if (inv_all) inv_all_cycles <= inv_all_cycles + 1;
            if (inv_en)  inv_en_cycles  <= inv_en_cycles + 1;
        end
    end

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

    sdior dut (
        .clk          (clk          ),
        .rst_n        (rst_n        ),
        .cfg_wr       (cfg_wr       ),
        .cfg_rd       (cfg_rd       ),
        .cfg_addr     (cfg_addr     ),
        .cfg_wdata    (cfg_wdata    ),
        .cfg_rdata    (cfg_rdata    ),
        .sdt_l1_base  (sdt_l1_base  ),
        .inv_all      (inv_all      ),
        .inv_en       (inv_en       ),
        .inv_pa       (inv_pa       )
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdior, "+all");
        $display("===============================================");
    end
`endif

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

    // SDecoder_IS 写的是整条 PA[47:0], 置无效只用到 PA[47:30] (1GB 粒度);
    // 这里让 PA[47:30] 取非 0 的区分值, inv_pa 的检查才有意义
    localparam logic [PA_BASE_WIDTH-1:0] IS_BASE_A = 18'h1_2345;
    localparam logic [PA_BASE_WIDTH-1:0] IS_BASE_B = 18'h1_0000;
    localparam logic [PA_BASE_WIDTH-1:0] IS_BASE_C = 18'h0_9999;
    localparam logic [PA_BASE_WIDTH-1:0] IS_BASE_D = 18'h1_1111;
    localparam logic [PA_WIDTH-1:0]      IS_PA_A = {IS_BASE_A, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
    localparam logic [PA_WIDTH-1:0]      IS_PA_B = {IS_BASE_B, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
    localparam logic [PA_WIDTH-1:0]      IS_PA_C = {IS_BASE_C, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
    localparam logic [PA_WIDTH-1:0]      IS_PA_D = {IS_BASE_D, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};

    // W1P 写数据: 把触发位置 1 (IA 是 bit 0, IS 是 bit 63); IS 还要把整条 PA 填在低位
    function automatic logic [SDIOR_DATA_WIDTH-1:0] w1p_ia();
        return {{(SDIOR_DATA_WIDTH-1){1'b0}}, 1'b1} << SDIOR_IA_W1P_BIT;
    endfunction

    function automatic logic [SDIOR_DATA_WIDTH-1:0] w1p_is(input logic [PA_WIDTH-1:0] pa);
        return ({{(SDIOR_DATA_WIDTH-1){1'b0}}, 1'b1} << SDIOR_IS_W1P_BIT)
               | {{(SDIOR_DATA_WIDTH-PA_WIDTH){1'b0}}, pa};
    endfunction

    // 发一次寄存器写: 下降沿给激励, 停在"写当拍"的上升沿 —— 这一拍 inv_* 还压着, 读写寄存器
    // 也已经在这一沿更新. 配合 cfg_write_end 用, 中间的检查点都取在写当拍.
    task automatic cfg_write_start(
        input logic [SDIOR_ADDR_WIDTH-1:0] addr,
        input logic [SDIOR_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        cfg_wr    = 1'b1;
        cfg_addr  = addr;
        cfg_wdata = data;
        @(posedge clk);
    endtask

    // 撤销写使能, 并再等一拍: 组合量稳定后才让调用者取样
    task automatic cfg_write_end();
        @(negedge clk);
        cfg_wr = 1'b0;
        @(negedge clk);
    endtask

    // 完整写一次 (不关心中间拍)
    task automatic cfg_write(
        input logic [SDIOR_ADDR_WIDTH-1:0] addr,
        input logic [SDIOR_DATA_WIDTH-1:0] data
    );
        cfg_write_start(addr, data);
        cfg_write_end();
    endtask

    // 读一次寄存器: 组合读, 在被读的那一拍取样 (rd_data / rd_inv_*)
    task automatic cfg_read(input logic [SDIOR_ADDR_WIDTH-1:0] addr);
        @(negedge clk);
        cfg_rd   = 1'b1;
        cfg_addr = addr;
        @(posedge clk);
        rd_data    = cfg_rdata;
        rd_inv_all = inv_all;
        rd_inv_en  = inv_en;
        @(negedge clk);
        cfg_rd   = 1'b0;
    endtask

    initial begin
        cfg_wr    = 1'b0;
        cfg_rd    = 1'b0;
        cfg_addr  = ADDR_SDECODER_IA;
        cfg_wdata = '0;

        wait (rst_n === 1'b1);
        repeat (4) @(negedge clk);

        // ====================================================================
        // 复位状态: 三个寄存器都是复位值
        chk("复位后: sdt_l1_base = 0", sdt_l1_base == '0);
        chk("复位后: inv_all = 0",     inv_all == 1'b0);
        chk("复位后: inv_en = 0",      inv_en == 1'b0);

        // ====================================================================
        // 复位后第一次就读 SDT_L1_BASE: 读出来的整字不许有 X.
        // 注: 这条挡不住"分支只赋一部分位"那种锁存器 (高位是先前 default 分支写下的 0,
        //     仿真里看不出 X), 那种只能靠读代码 / 综合检查; 这里用 $isunknown 判而不是 ==,
        //     因为 == 遇 X 会被 chk 当成成功
        cfg_read(ADDR_SDT_L1_BASE);
        chk("复位后第一次读 SDT_L1_BASE: 整字没有 X", $isunknown(rd_data) == 1'b0);
        chk("复位后第一次读 SDT_L1_BASE: 整字为 0",   rd_data == '0);

        // ====================================================================
        // 0x2 SDT_L1_BASE (RW): 写同步生效, 读回写入值
        cfg_write_start(ADDR_SDT_L1_BASE, 48'h0001_0000);
        chk("写 SDT_L1_BASE: 当拍不产生 inv_all", inv_all == 1'b0);
        chk("写 SDT_L1_BASE: 当拍不产生 inv_en",  inv_en == 1'b0);
        cfg_write_end();
        chk("写 SDT_L1_BASE: 下一拍更新为写入值", sdt_l1_base == 48'h0001_0000);
        chk("写 SDT_L1_BASE: 读回 = 写入值",      cfg_rdata == 48'h0001_0000);

        // 再写一个值: 覆盖, 不是或上去
        cfg_write(ADDR_SDT_L1_BASE, 48'h0002_0000);
        chk("再写 SDT_L1_BASE: 覆盖为新值", sdt_l1_base == 48'h0002_0000);
        chk("再写 SDT_L1_BASE: 读回 = 新值", cfg_rdata == 48'h0002_0000);
        cfg_write(ADDR_SDT_L1_BASE, '0);
        chk("写 0 到 SDT_L1_BASE: 归 0", sdt_l1_base == '0);

        cfg_write(ADDR_SDT_L1_BASE, 48'h0001_0000);
        chk("重设 SDT_L1_BASE 给后面的检查用", sdt_l1_base == 48'h0001_0000);

        // ====================================================================
        // 0x0 / 0x1 是只写寄存器: 读回 0, 而且读不许触发 inv
        cfg_read(ADDR_SDECODER_IA);
        chk("读 SDecoder_IA (只写): 读回 0",         rd_data == '0);
        chk("读 SDecoder_IA: 不产生 inv_all",        rd_inv_all == 1'b0);
        chk("读 SDecoder_IA: 不产生 inv_en",         rd_inv_en == 1'b0);

        cfg_read(ADDR_SDECODER_IS);
        chk("读 SDecoder_IS (只写): 读回 0",         rd_data == '0);
        chk("读 SDecoder_IS: 不产生 inv_en",         rd_inv_en == 1'b0);
        chk("读 SDecoder_IS: 不产生 inv_all",        rd_inv_all == 1'b0);

        // ====================================================================
        // 0x1 SDecoder_IS (W1P): 触发位 bit[63] 写 1 才当拍发 1 拍 inv_en,
        // 字的低 48 位是整条 PA, 原样送到 inv_pa (sdtlb 内部只用 PA[47:30])
        cyc_before = inv_en_cycles;
        cfg_write_start(ADDR_SDECODER_IS, w1p_is(IS_PA_A));
        chk("写 SDecoder_IS: 当拍 inv_en = 1",       inv_en == 1'b1);
        chk("写 SDecoder_IS: 当拍 inv_pa = 整条 PA[47:0]", inv_pa == IS_PA_A);
        chk("写 SDecoder_IS: 当拍 inv_all = 0",      inv_all == 1'b0);
        cfg_write_end();
        chk("写 SDecoder_IS: inv_en 只占 1 个上升沿",
            (inv_en_cycles - cyc_before) == 1);
        chk("写 SDecoder_IS: 不动 sdt_l1_base",      sdt_l1_base == 48'h0001_0000);

        // W1P: 不写触发位就不许有脉冲 (PA 位上有值也不行)
        cyc_before  = inv_en_cycles;
        cyc_before2 = inv_all_cycles;
        cfg_write(ADDR_SDECODER_IS, {{(SDIOR_DATA_WIDTH-PA_WIDTH){1'b0}}, IS_PA_B});
        chk("写 SDecoder_IS 不设触发位: 没有 inv_en 脉冲",
            (inv_en_cycles - cyc_before) == 0);
        chk("写 SDecoder_IS 不设触发位: 也没有 inv_all 脉冲",
            (inv_all_cycles - cyc_before2) == 0);
        chk("写 SDecoder_IS 不设触发位: 不动 sdt_l1_base", sdt_l1_base == 48'h0001_0000);

        // 连写两次 IS: 每次都要重新发脉冲 (脉冲不是"写过一次就没了"的状态)
        cyc_before = inv_en_cycles;
        cfg_write_start(ADDR_SDECODER_IS, w1p_is(IS_PA_B));
        chk("连写 IS 第 1 次: inv_en = 1",           inv_en == 1'b1);
        cfg_write_end();
        cfg_write_start(ADDR_SDECODER_IS, w1p_is(IS_PA_C));
        chk("连写 IS 第 2 次: inv_en = 1",           inv_en == 1'b1);
        chk("连写 IS 第 2 次: inv_pa 跟着换",         inv_pa == IS_PA_C);
        cfg_write_end();
        chk("连写 IS 两次: inv_en 一共占 2 个上升沿",
            (inv_en_cycles - cyc_before) == 2);

        // ====================================================================
        // 0x0 SDecoder_IA (W1P): 触发位 bit[0] 写 1 才当拍发 1 拍 inv_all
        cyc_before = inv_all_cycles;
        cfg_write_start(ADDR_SDECODER_IA, w1p_ia());
        chk("写 SDecoder_IA: 当拍 inv_all = 1",      inv_all == 1'b1);
        chk("写 SDecoder_IA: 当拍 inv_en = 0",       inv_en == 1'b0);
        cfg_write_end();
        chk("写 SDecoder_IA: inv_all 只占 1 个上升沿",
            (inv_all_cycles - cyc_before) == 1);
        chk("写 SDecoder_IA: 不动 sdt_l1_base",      sdt_l1_base == 48'h0001_0000);

        // W1P: 写 0 (不触发) 不许有脉冲
        cyc_before = inv_all_cycles;
        cfg_write(ADDR_SDECODER_IA, '0);
        chk("写 SDecoder_IA 写 0: 没有 inv_all 脉冲",
            (inv_all_cycles - cyc_before) == 0);

        // ====================================================================
        // 背靠背: 连着两个上升沿各写一个寄存器, 两个都生效且互不串
        cfg_write_start(ADDR_SDECODER_IS, w1p_is(IS_PA_D));
        chk("背靠背: 第 1 拍 inv_en = 1",            inv_en == 1'b1);
        @(negedge clk);
        cfg_addr  = ADDR_SDT_L1_BASE;
        cfg_wdata = 48'h0003_0000;
        @(posedge clk);
        chk("背靠背: 第 2 拍 inv_en 归 0",           inv_en == 1'b0);
        chk("背靠背: 第 2 拍 inv_all = 0",           inv_all == 1'b0);
        cfg_write_end();
        chk("背靠背: SDT_L1_BASE 更新",              sdt_l1_base == 48'h0003_0000);
        chk("背靠背: 读回 = 新的一级表基地址",        cfg_rdata == 48'h0003_0000);

        // ====================================================================
        // 静止: 没有访问时三个输出都不动 (也不该有脉冲)
        cfg_addr = ADDR_SDECODER_IA;
        cfg_wdata = '0;
        cyc_before  = inv_all_cycles;
        cyc_before2 = inv_en_cycles;
        repeat (4) @(negedge clk);
        chk("静止: inv_all 保持 0",                  inv_all == 1'b0);
        chk("静止: inv_en 保持 0",                   inv_en == 1'b0);
        chk("静止: sdt_l1_base 保持",                sdt_l1_base == 48'h0003_0000);
        chk("静止: 4 拍里 inv_all 一个沿都没压",       inv_all_cycles == cyc_before);
        chk("静止: 4 拍里 inv_en 一个沿都没压",        inv_en_cycles == cyc_before2);

        // ====================================================================
        repeat (4) @(negedge clk);
        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdior 单元自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
