`timescale 1ns/1ps
module tb_syn_fifo;

    // 端口都是简单信号 (没有总线协议), 所以不建 interface, 直接在 tb 里驱动
    localparam int unsigned WIDTH     = 8;
    localparam int unsigned DEPTH     = 4;              // 2 的幂
    localparam int unsigned DEPTH_ODD = 5;              // 非 2 的幂, 专门查指针回绕

    logic               clk;
    logic               rst_n;

    int                 errors = 0;
    int                 checks = 0;

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

    // ---- 被测 FIFO A: 深度 4 ----
    logic               a_wr_en;
    logic [WIDTH-1:0]   a_wrdata;
    logic               a_rd_en;
    logic [WIDTH-1:0]   a_rd_data;
    logic               a_full;
    logic               a_almost_full;
    logic               a_empty;
    logic               a_almost_empty;

    syn_fifo #(
        .WIDTH              (WIDTH     ),
        .DEPTH              (DEPTH     ),
        .ALMOST_FULL_LEVEL  (DEPTH - 1 ),
        .ALMOST_EMPTY_LEVEL (1         )
    ) u_fifo_a (
        .clk          (clk            ),
        .rst_n        (rst_n          ),
        .wr_en        (a_wr_en        ),
        .wrdata       (a_wrdata       ),
        .rd_en        (a_rd_en        ),
        .rd_data      (a_rd_data      ),
        .full         (a_full         ),
        .almost_full  (a_almost_full  ),
        .empty        (a_empty        ),
        .almost_empty (a_almost_empty )
    );

    // ---- 被测 FIFO B: 深度 5 ----
    logic               b_wr_en;
    logic [WIDTH-1:0]   b_wrdata;
    logic               b_rd_en;
    logic [WIDTH-1:0]   b_rd_data;
    logic               b_full;
    logic               b_almost_full;
    logic               b_empty;
    logic               b_almost_empty;

    syn_fifo #(
        .WIDTH              (WIDTH     ),
        .DEPTH              (DEPTH_ODD ),
        .ALMOST_FULL_LEVEL  (DEPTH_ODD - 1 ),
        .ALMOST_EMPTY_LEVEL (1         )
    ) u_fifo_b (
        .clk          (clk            ),
        .rst_n        (rst_n          ),
        .wr_en        (b_wr_en        ),
        .wrdata       (b_wrdata       ),
        .rd_en        (b_rd_en        ),
        .rd_data      (b_rd_data      ),
        .full         (b_full         ),
        .almost_full  (b_almost_full  ),
        .empty        (b_empty        ),
        .almost_empty (b_almost_empty )
    );

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

    // 激励统一在下降沿给出 (上升沿采样), wr_en / rd_en 只拉一拍
    task automatic a_write(input logic [WIDTH-1:0] data);
        @(negedge clk);
        a_wr_en = 1'b1;
        a_wrdata = data;
        @(posedge clk);
        @(negedge clk);
        a_wr_en = 1'b0;
    endtask

    task automatic a_read_expect(input logic [WIDTH-1:0] exp, input string name);
        // 首字直通: rd_en 之前队头就应出现在 rd_data 上
        chk($sformatf("%s: 队头 = %0h", name, exp), a_rd_data == exp);
        @(negedge clk);
        a_rd_en = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_rd_en = 1'b0;
    endtask

    task automatic b_write(input logic [WIDTH-1:0] data);
        @(negedge clk);
        b_wr_en = 1'b1;
        b_wrdata = data;
        @(posedge clk);
        @(negedge clk);
        b_wr_en = 1'b0;
    endtask

    task automatic b_read_expect(input logic [WIDTH-1:0] exp, input string name);
        chk($sformatf("%s: 队头 = %0h", name, exp), b_rd_data == exp);
        @(negedge clk);
        b_rd_en = 1'b1;
        @(posedge clk);
        @(negedge clk);
        b_rd_en = 1'b0;
    endtask

    initial begin
        a_wr_en = 1'b0;  a_wrdata = '0;  a_rd_en = 1'b0;
        b_wr_en = 1'b0;  b_wrdata = '0;  b_rd_en = 1'b0;

        wait (rst_n === 1'b1);
        repeat (4) @(negedge clk);

        // ====================================================================
        // 复位状态
        chk("复位: empty = 1",        a_empty == 1'b1);
        chk("复位: full = 0",         a_full == 1'b0);
        chk("复位: almost_empty = 1", a_almost_empty == 1'b1);
        chk("复位: almost_full = 0",  a_almost_full == 1'b0);

        // ====================================================================
        // 写一个: 首字直通
        a_write(8'h11);
        chk("写 1 个: empty = 0",           a_empty == 1'b0);
        chk("写 1 个: almost_empty = 1",    a_almost_empty == 1'b1);
        chk("写 1 个: 首字直通 rd_data",    a_rd_data == 8'h11);
        chk("写 1 个: almost_full = 0",     a_almost_full == 1'b0);

        // ====================================================================
        // 写满: full / almost_full 的水位
        a_write(8'h22);
        a_write(8'h33);
        chk("写 3 个: almost_full = 1 (阈值 3)", a_almost_full == 1'b1);
        chk("写 3 个: full = 0",                 a_full == 1'b0);
        chk("写 3 个: almost_empty = 0",         a_almost_empty == 1'b0);

        a_write(8'h44);
        chk("写 4 个: full = 1", a_full == 1'b1);

        // 满时再写应被忽略: 后面读出来的顺序不能变
        a_write(8'h55);
        chk("满时写被忽略: full 仍为 1", a_full == 1'b1);

        a_read_expect(8'h11, "顺序 1/4");
        a_read_expect(8'h22, "顺序 2/4");
        a_read_expect(8'h33, "顺序 3/4");
        a_read_expect(8'h44, "顺序 4/4");
        chk("读空: empty = 1",        a_empty == 1'b1);
        chk("读空: almost_empty = 1", a_almost_empty == 1'b1);
        chk("读空: full = 0",         a_full == 1'b0);

        // 空时读应无效
        @(negedge clk);
        a_rd_en = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_rd_en = 1'b0;
        chk("空时读被忽略: empty 仍为 1", a_empty == 1'b1);

        // ====================================================================
        // 指针回绕 (深度 4, 连写连读 3 轮)
        for (int round = 0; round < 3; round++) begin
            for (int i = 0; i < DEPTH; i++) begin
                a_write(8'(round * DEPTH + i));
            end
            for (int i = 0; i < DEPTH; i++) begin
                a_read_expect(8'(round * DEPTH + i), $sformatf("回绕 第%0d轮 %0d/%0d", round, i, DEPTH));
            end
        end

        // ====================================================================
        // 同拍又写又读: 占用数不变, 数据顺序不乱
        a_write(8'ha1);
        a_write(8'ha2);
        @(negedge clk);
        a_wr_en  = 1'b1;
        a_wrdata = 8'ha3;
        a_rd_en  = 1'b1;
        @(posedge clk);
        @(negedge clk);
        a_wr_en = 1'b0;
        a_rd_en = 1'b0;
        chk("同拍读写: empty 仍为 0",        a_empty == 1'b0);
        chk("同拍读写: full 仍为 0",         a_full == 1'b0);
        chk("同拍读写: 队头推进到 8'ha2",    a_rd_data == 8'ha2);
        a_read_expect(8'ha2, "同拍后 1/2");
        a_read_expect(8'ha3, "同拍后 2/2");
        chk("同拍读写后: empty = 1", a_empty == 1'b1);

        // ====================================================================
        // 非 2 次幂深度 (5): 水位与回绕
        for (int i = 0; i < DEPTH_ODD; i++) begin
            b_write(8'hb0 + 8'(i));
        end
        chk("深度 5: full = 1",            b_full == 1'b1);
        chk("深度 5: almost_full = 1",     b_almost_full == 1'b1);
        chk("深度 5: 首字直通 rd_data",    b_rd_data == 8'hb0);
        b_write(8'hbf);
        chk("深度 5: 满时写被忽略",        b_full == 1'b1);
        for (int i = 0; i < DEPTH_ODD; i++) begin
            b_read_expect(8'hb0 + 8'(i), $sformatf("深度 5 顺序 %0d/%0d", i, DEPTH_ODD));
        end
        chk("深度 5: 排空后 empty = 1",        b_empty == 1'b1);
        chk("深度 5: 排空后 almost_empty = 1", b_almost_empty == 1'b1);
        chk("深度 5: 排空后 full = 0",         b_full == 1'b0);

        for (int round = 0; round < 2; round++) begin
            for (int i = 0; i < DEPTH_ODD; i++) begin
                b_write(8'hc0 + 8'(round * DEPTH_ODD + i));
            end
            for (int i = 0; i < DEPTH_ODD; i++) begin
                b_read_expect(8'hc0 + 8'(round * DEPTH_ODD + i),
                              $sformatf("深度 5 回绕 第%0d轮 %0d/%0d", round, i, DEPTH_ODD));
            end
        end

        // ====================================================================
        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "syn_fifo 自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
