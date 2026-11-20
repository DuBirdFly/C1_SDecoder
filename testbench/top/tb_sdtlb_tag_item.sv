`default_nettype none

`timescale 1ns/1ps

// sdtlb_tag_item 单元自检: 装填 (fill), 置无效 (inv), 以及两者同拍时条目层的优先级.
//
// 装填与置无效的仲裁在阵列层做 (按 "inv 是否命中本次装填地址" 决定丢不丢这笔装填),
// 条目层拿到的 fill_en 已经是门控过的, 所以一拍里不会再出现 "该被丢弃的失效":
//
//   Valid 的更新优先级: fill_en  >  inv_all || inv_match
//
// 本 tb 的次序: 只装填 (正常) -> 只置无效 (正常) -> 同拍 inv + fill (条目层装填赢).
module tb_sdtlb_tag_item;

    import sdecoder_pkg::*;

    localparam logic [PA_BASE_WIDTH-1:0] TAG_A    = {12'h100, 5'd8};
    localparam logic [PA_UP_WIDTH-1:0]   TAG_A_UP = 5'd8;

    logic                       clk;
    logic                       rst_n;

    // 查表端口 (item 里命中是组合输出, 没有打拍)
    logic                       cam0_req_en;
    logic [PA_WIDTH-1:0]        cam0_req_pa;
    logic                       cam0_hit;
    logic                       cam1_req_en;
    logic [PA_WIDTH-1:0]        cam1_req_pa;
    logic                       cam1_hit;

    // 装填 (本拍有效, 本拍写 Latch)
    logic                       fill_en;
    logic [PA_BASE_WIDTH-1:0]   fill_pa_base;
    logic [PA_UP_WIDTH-1:0]     fill_pa_up;

    // 置无效 (inv_en 是总使能, inv_all / inv_sel 只在它有效的当拍起作用)
    logic                       inv_en;
    logic                       inv_all;
    logic                       inv_sel;
    logic [PA_BASE_WIDTH-1:0]   inv_sel_pa;

    SDTLB_TAG_ITEM_t            tag_item;
    logic                       tag_valid;

    int unsigned checks = 0;
    int unsigned errors = 0;

    crg #(
        .CLK_FREQ ( 2_500 )
    ) u_crg (
        .clk     (clk      ),
        .rst_n   (rst_n    )
    );

    sdtlb_tag_item dut (
        .clk              (clk            ),
        .rst_n            (rst_n          ),

        .cam0_req_en      (cam0_req_en    ),
        .cam0_req_pa      (cam0_req_pa    ),
        .cam0_hit         (cam0_hit       ),

        .cam1_req_en      (cam1_req_en    ),
        .cam1_req_pa      (cam1_req_pa    ),
        .cam1_hit         (cam1_hit       ),

        .fill_en       (fill_en     ),
        .fill_pa_base  (fill_pa_base),
        .fill_pa_up    (fill_pa_up  ),

        .inv_en           (inv_en         ),
        .inv_all          (inv_all        ),
        .inv_sel           (inv_sel         ),
        .inv_sel_pa           (inv_sel_pa         ),

        .tag_item         (tag_item       ),
        .tag_valid        (tag_valid      )
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
        fill_pa_base <= base;
        fill_pa_up   <= up;
        fill_en      <= 1'b1;
        wait_cycle();                   // 这一沿写 Latch 并置 Valid
        fill_en <= 1'b0;
    endtask

    // 按地址置无效, 拉高一拍
    task automatic do_inv(input logic [PA_BASE_WIDTH-1:0] base);
        wait_cycle();
        inv_en      <= 1'b1;
        inv_sel_pa  <= base;
        inv_sel     <= 1'b1;
        wait_cycle();                   // 这一沿清 Valid
        inv_en      <= 1'b0;
        inv_sel     <= 1'b0;
    endtask

    // 同一拍请求 "置无效 base" 和 "装填 base"; 返回这一沿之后的 Valid
    task automatic do_fill_and_inv(
        input  logic [PA_BASE_WIDTH-1:0] base,
        input  logic [PA_UP_WIDTH-1:0]   up,
        output logic                     valid_after
    );
        wait_cycle();
        fill_pa_base <= base;
        fill_pa_up   <= up;
        fill_en      <= 1'b1;
        inv_en      <= 1'b1;
        inv_sel_pa  <= base;
        inv_sel     <= 1'b1;
        wait_cycle();                   // 同一沿: inv 清位与 fill 置位撞车
        valid_after = tag_valid;
        fill_en <= 1'b0;
        inv_en      <= 1'b0;
        inv_sel     <= 1'b0;
    endtask

    // 查一次表 (命中是组合输出, 在请求有效的那一拍取值)
    task automatic do_req(
        input  logic [PA_BASE_WIDTH-1:0] base,
        output logic                     hit
    );
        wait_cycle();
        cam0_req_pa <= {base, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        cam0_req_en <= 1'b1;
        wait_cycle();                   // 请求有效的一拍
        hit = cam0_hit;
        cam0_req_en <= 1'b0;
    endtask

    logic hit;
    logic valid_after;

    initial begin
        cam0_req_en     = 1'b0;
        cam0_req_pa     = '0;
        cam1_req_en     = 1'b0;
        cam1_req_pa     = '0;
        fill_en      = 1'b0;
        fill_pa_base = '0;
        fill_pa_up   = '0;
        inv_en          = 1'b0;
        inv_all         = 1'b0;
        inv_sel          = 1'b0;
        inv_sel_pa          = '0;
        hit             = 1'b0;
        valid_after     = 1'b0;

        wait (rst_n === 1'b1);
        repeat (10) wait_cycle();

        // ====================================================================
        // 只装填 -> 条目有效, 查表命中
        do_fill(TAG_A, TAG_A_UP);
        chk("只装填: Valid = 1", tag_valid === 1'b1);
        chk("只装填: tag 内容正确", (tag_item.pa_base === TAG_A) && (tag_item.pa_up === TAG_A_UP));
        do_req(TAG_A, hit);
        chk("只装填: 查表命中", hit === 1'b1);

        // ====================================================================
        // 只置无效 -> 条目无效, 查表不命中
        do_inv(TAG_A);
        chk("只置无效: Valid = 0", tag_valid === 1'b0);
        do_req(TAG_A, hit);
        chk("只置无效: 查表不命中", hit === 1'b0);

        // ====================================================================
        // 同拍 inv + fill -> 条目层装填优先 (冲突的装填在阵列层就丢了, 到不了这里)
        do_fill(TAG_A, TAG_A_UP);
        chk("同拍前置: 重新装填后 Valid = 1", tag_valid === 1'b1);

        do_fill_and_inv(TAG_A, TAG_A_UP, valid_after);
        $display("");
        $display("--------------------------------------------------------------");
        $display("同拍 inv + fill: 条目层装填优先 (阵列层会先丢掉冲突的装填)");
        $display("  tag_valid   = %b", tag_valid);
        $display("  tag_item.pa_base = 0x%h", tag_item.pa_base);
        $display("--------------------------------------------------------------");
        chk("同拍 inv+fill: 条目层装填赢, Valid = 1", valid_after === 1'b1);
        chk("同拍 inv+fill: 拍末 Valid 仍为 1", tag_valid === 1'b1);
        chk("同拍 inv+fill: tag 保持装填内容", (tag_item.pa_base === TAG_A) && (tag_item.pa_up === TAG_A_UP));
        do_req(TAG_A, hit);
        chk("同拍 inv+fill: 查表命中", hit === 1'b1);

        // 装填通路没被这次仲裁破坏: 再来一次普通装填仍能命中
        do_fill(TAG_A, TAG_A_UP);
        do_req(TAG_A, hit);
        chk("仲裁后再装填: 恢复命中", (tag_valid === 1'b1) && (hit === 1'b1));

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
