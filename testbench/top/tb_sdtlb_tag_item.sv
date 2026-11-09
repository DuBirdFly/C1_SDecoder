`default_nettype none

`timescale 1ns/1ps

// sdtlb_tag_item 单元自检: 装填 (fill), 置无效 (inv), 以及两者同拍的仲裁.
//
// sdtlb 现在装填不打拍: 装填在 fill_en 当拍写 Latch, 置无效也当拍清 Valid,
// 两者同拍由 item 的 if/else 仲裁 —— 置无效优先, 本次装填丢弃:
//
//   Valid 的更新优先级: inv_all || inv_match  >  fill_wr_en
//
// 本 tb 的次序: 只装填 (正常) -> 只置无效 (正常) -> 同拍 inv + fill (inv 赢).
module tb_sdtlb_tag_item;

    import sdecoder_pkg::*;

    localparam logic [PA_BASE_WIDTH-1:0] TAG_A    = {12'h100, 5'd8};
    localparam logic [PA_UP_WIDTH-1:0]   TAG_A_UP = 5'd8;

    logic                       clk;
    logic                       rst_n;

    // 查表端口 (item 里命中是组合输出, 没有打拍)
    logic                       req0_en;
    logic [PA_WIDTH-1:0]        req0_pa;
    logic                       req0_hit;
    logic                       req1_en;
    logic [PA_WIDTH-1:0]        req1_pa;
    logic                       req1_hit;

    // 装填 (本拍有效, 本拍写 Latch)
    logic                       fill_wr_en;
    logic [PA_BASE_WIDTH-1:0]   fill_wr_pa_base;
    logic [PA_UP_WIDTH-1:0]     fill_wr_pa_up;

    // 置无效
    logic                       inv_all;
    logic                       inv_en;
    logic [PA_WIDTH-1:0]        inv_pa;

    SDTLB_TAG_ITEM_t            tag_item;

    int unsigned checks = 0;
    int unsigned errors = 0;

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

    sdtlb_tag_item dut (
        .clk              (clk            ),
        .rst_n            (rst_n          ),

        .req0_en          (req0_en        ),
        .req0_pa          (req0_pa        ),
        .req0_hit         (req0_hit       ),

        .req1_en          (req1_en        ),
        .req1_pa          (req1_pa        ),
        .req1_hit         (req1_hit       ),

        .fill_wr_en       (fill_wr_en     ),
        .fill_wr_pa_base  (fill_wr_pa_base),
        .fill_wr_pa_up    (fill_wr_pa_up  ),

        .inv_all          (inv_all        ),
        .inv_en           (inv_en         ),
        .inv_pa           (inv_pa         ),

        .tag_item         (tag_item       )
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb_tag_item, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdtlb_tag_item);
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

    // 等到一个时钟沿, 并让这一沿的寄存器更新落定再返回
    task automatic wait_cycle();
        @(posedge clk);
        #1;
    endtask

    // 请求一次装填 (拉高一拍)
    task automatic do_fill(
        input logic [PA_BASE_WIDTH-1:0] base,
        input logic [PA_UP_WIDTH-1:0]   up
    );
        wait_cycle();
        fill_wr_pa_base <= base;
        fill_wr_pa_up   <= up;
        fill_wr_en      <= 1'b1;
        wait_cycle();                   // 这一沿写 Latch 并置 Valid
        fill_wr_en <= 1'b0;
    endtask

    // 按地址置无效, 拉高一拍
    task automatic do_inv(input logic [PA_BASE_WIDTH-1:0] base);
        wait_cycle();
        inv_pa <= {base, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        inv_en <= 1'b1;
        wait_cycle();                   // 这一沿清 Valid
        inv_en <= 1'b0;
    endtask

    // 同一拍请求 "置无效 base" 和 "装填 base"; 返回这一沿之后的 Valid
    task automatic do_fill_and_inv(
        input  logic [PA_BASE_WIDTH-1:0] base,
        input  logic [PA_UP_WIDTH-1:0]   up,
        output logic                     valid_after
    );
        wait_cycle();
        fill_wr_pa_base <= base;
        fill_wr_pa_up   <= up;
        fill_wr_en      <= 1'b1;
        inv_pa          <= {base, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        inv_en          <= 1'b1;
        wait_cycle();                   // 同一沿: inv 清位与 fill 置位撞车
        valid_after = tag_item.valid;
        fill_wr_en <= 1'b0;
        inv_en     <= 1'b0;
    endtask

    // 查一次表 (命中是组合输出, 在请求有效的那一拍取值)
    task automatic do_req(
        input  logic [PA_BASE_WIDTH-1:0] base,
        output logic                     hit
    );
        wait_cycle();
        req0_pa <= {base, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        req0_en <= 1'b1;
        wait_cycle();                   // 请求有效的一拍
        hit = req0_hit;
        req0_en <= 1'b0;
    endtask

    logic hit;
    logic valid_after;

    initial begin
        req0_en         = 1'b0;
        req0_pa         = '0;
        req1_en         = 1'b0;
        req1_pa         = '0;
        fill_wr_en      = 1'b0;
        fill_wr_pa_base = '0;
        fill_wr_pa_up   = '0;
        inv_all         = 1'b0;
        inv_en          = 1'b0;
        inv_pa          = '0;
        hit             = 1'b0;
        valid_after     = 1'b0;

        wait (rst_n === 1'b1);
        repeat (10) wait_cycle();

        // ====================================================================
        // 只装填 -> 条目有效, 查表命中
        do_fill(TAG_A, TAG_A_UP);
        chk("只装填: Valid = 1", tag_item.valid === 1'b1);
        chk("只装填: tag 内容正确",
            (tag_item.pa_base === TAG_A) && (tag_item.pa_up === TAG_A_UP));
        do_req(TAG_A, hit);
        chk("只装填: 查表命中", hit === 1'b1);

        // ====================================================================
        // 只置无效 -> 条目无效, 查表不命中
        do_inv(TAG_A);
        chk("只置无效: Valid = 0", tag_item.valid === 1'b0);
        do_req(TAG_A, hit);
        chk("只置无效: 查表不命中", hit === 1'b0);

        // ====================================================================
        // 同拍 inv + fill -> 置无效优先, 本次装填丢弃
        do_fill(TAG_A, TAG_A_UP);
        chk("同拍前置: 重新装填后 Valid = 1", tag_item.valid === 1'b1);

        do_fill_and_inv(TAG_A, TAG_A_UP, valid_after);
        $display("");
        $display("--------------------------------------------------------------");
        $display("同拍 inv + fill: 置无效优先, 装填被丢弃");
        $display("  tag_item.valid   = %b", tag_item.valid);
        $display("  tag_item.pa_base = 0x%h", tag_item.pa_base);
        $display("--------------------------------------------------------------");
        chk("同拍 inv+fill: 置无效赢, Valid = 0", valid_after === 1'b0);
        chk("同拍 inv+fill: 拍末 Valid 仍为 0", tag_item.valid === 1'b0);
        do_req(TAG_A, hit);
        chk("同拍 inv+fill: 查表不命中", hit === 1'b0);

        // 装填通路没被这次仲裁破坏: 再来一次普通装填仍能命中
        do_fill(TAG_A, TAG_A_UP);
        do_req(TAG_A, hit);
        chk("仲裁后再装填: 恢复命中", (tag_item.valid === 1'b1) && (hit === 1'b1));

        $display("\n%0d checks, %0d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdtlb_tag_item 单元自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule

`default_nettype wire
