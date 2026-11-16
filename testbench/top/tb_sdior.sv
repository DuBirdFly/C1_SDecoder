`timescale 1ns/1ps

// sdior 单元自检 (SDecoder_IA / SDecoder_IS / SDecoder_PTBR)
//
// 按设计方案 "可配置的寄存器": 目前只实现 3 个寄存器, SDecoder_ES 暂不实现.
//   - SDecoder_IA : W1P, 写 bit[0] = 1 产生 1 拍 inv_all
//   - SDecoder_IS : W1P, 写 bit[63] = 1 产生 1 拍 inv_en, 字的低位是整条 PA[47:0]
//   - SDecoder_PTBR: RW, 一级表基地址 (16B 对界), 复位值 0
module tb_sdior;

    import sdecoder_pkg::*;

    logic                                clk;
    logic                                rst_n;

    int                                  errors = 0;
    int                                  checks = 0;

    logic                                cfg_wr;
    logic                                cfg_rd;
    logic [SDIOR_ADDR_WIDTH-1:0]         cfg_addr;
    logic [SDIOR_DATA_WIDTH-1:0]         cfg_wdata;
    logic [SDIOR_DATA_WIDTH-1:0]         cfg_rdata;

    logic [PA_WIDTH-1:0]                 sdecoder_ptbr;
    logic                                inv_all;
    logic                                inv_en;
    logic [PA_WIDTH-1:0]                 inv_pa;

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
        .clk            (clk            ),
        .rst_n          (rst_n          ),
        .cfg_wr         (cfg_wr         ),
        .cfg_rd         (cfg_rd         ),
        .cfg_addr       (cfg_addr       ),
        .cfg_wdata      (cfg_wdata      ),
        .cfg_rdata      (cfg_rdata      ),
        .sdecoder_ptbr  (sdecoder_ptbr  ),
        .inv_all        (inv_all        ),
        .inv_en         (inv_en         ),
        .inv_pa         (inv_pa         )
    );

    task automatic chk(input string name, input logic cond);
        checks++;
        if (!cond) begin
            errors++;
            $display("FAIL %-58s", name);
        end
        else begin
            $display("ok   %-58s", name);
        end
    endtask

    // 写一个寄存器: 拉高 cfg_wr 一拍
    task automatic wr_reg(
        input logic [SDIOR_ADDR_WIDTH-1:0]  addr,
        input logic [SDIOR_DATA_WIDTH-1:0]  data
    );
        @(negedge clk);
        cfg_wr    = 1'b1;
        cfg_addr  = addr;
        cfg_wdata = data;
        @(negedge clk);
        cfg_wr    = 1'b0;
        cfg_wdata = '0;
    endtask

    // 读一个寄存器: 地址保持一拍, 在上升沿后采样组合读数据
    task automatic rd_reg(
        input  logic [SDIOR_ADDR_WIDTH-1:0] addr,
        output logic [SDIOR_DATA_WIDTH-1:0] data
    );
        @(negedge clk);
        cfg_rd   = 1'b1;
        cfg_addr = addr;
        @(posedge clk);
        data = cfg_rdata;
        @(negedge clk);
        cfg_rd   = 1'b0;
    endtask

    // 常驻统计: inv_all / inv_en 各拉高了多少拍, 以及 inv_en 那拍的 inv_pa
    int unsigned                 all_cnt = 0;
    int unsigned                 en_cnt  = 0;
    logic [PA_WIDTH-1:0]         inv_pa_cap;

    always @(posedge clk) begin
        if (rst_n) begin
            if (inv_all) all_cnt++;
            if (inv_en) begin
                en_cnt++;
                inv_pa_cap <= inv_pa;
            end
        end
    end

    logic [SDIOR_DATA_WIDTH-1:0] rd_data;
    int unsigned                 all_snap;
    int unsigned                 en_snap;

    initial begin
        cfg_wr    = 1'b0;
        cfg_rd    = 1'b0;
        cfg_addr  = '0;
        cfg_wdata = '0;

        wait (rst_n === 1'b1);
        repeat (5) @(negedge clk);

        // 复位值
        rd_reg(ADDR_SDECODER_PTBR, rd_data);
        chk("复位后 SDecoder_PTBR = 0", rd_data == '0);
        chk("复位后 sdecoder_ptbr 输出 = 0", sdecoder_ptbr == '0);
        chk("复位后 inv_all / inv_en 都为 0", (inv_all == 1'b0) && (inv_en == 1'b0));

        // SDecoder_PTBR: 可读写, 读回只有低 PA_WIDTH 位
        wr_reg(ADDR_SDECODER_PTBR, 64'h0000_0000_3000);
        rd_reg(ADDR_SDECODER_PTBR, rd_data);
        chk("SDecoder_PTBR 可读写", rd_data[PA_WIDTH-1:0] == 48'h0000_0000_3000);
        chk("SDecoder_PTBR 直通输出", sdecoder_ptbr == 48'h0000_0000_3000);

        // SDecoder_IA: 写 0 不产生脉冲
        all_snap = all_cnt;
        en_snap  = en_cnt;
        wr_reg(ADDR_SDECODER_IA, 64'h0);
        repeat (2) @(posedge clk);
        chk("SDecoder_IA 写 0 不产生 inv_all 脉冲", all_cnt == all_snap);

        // SDecoder_IA: 写 bit[0] = 1 产生 1 拍 inv_all
        all_snap = all_cnt;
        en_snap  = en_cnt;
        wr_reg(ADDR_SDECODER_IA, 64'h1);
        repeat (2) @(posedge clk);
        chk("SDecoder_IA 写 1 产生 1 拍 inv_all", all_cnt == all_snap + 1);
        chk("SDecoder_IA 不产生 inv_en", en_cnt == en_snap);

        // SDecoder_IS: 写 bit[63] = 1, 低位是整条 PA[47:0] (置无效是 1GB 粒度, PA[29:0] 必须为 0)
        all_snap = all_cnt;
        en_snap  = en_cnt;
        wr_reg(ADDR_SDECODER_IS, (64'h1 << SDIOR_IS_W1P_BIT) | 64'h0000_0000_4000_0000);
        repeat (2) @(posedge clk);
        chk("SDecoder_IS 产生 1 拍 inv_en", en_cnt == en_snap + 1);
        chk("SDecoder_IS 的 inv_pa 是字的低位 PA[47:0]",
            inv_pa_cap == 48'h0000_4000_0000);
        chk("SDecoder_IS 不产生 inv_all", all_cnt == all_snap);

        // W1P 寄存器读回 0
        rd_reg(ADDR_SDECODER_IA, rd_data);
        chk("SDecoder_IA 读回 0", rd_data == '0);
        rd_reg(ADDR_SDECODER_IS, rd_data);
        chk("SDecoder_IS 读回 0", rd_data == '0);

        // SDecoder_PTBR 不受 W1P 操作影响
        rd_reg(ADDR_SDECODER_PTBR, rd_data);
        chk("W1P 操作不动 SDecoder_PTBR", rd_data[PA_WIDTH-1:0] == 48'h0000_0000_3000);

        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdior 自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
