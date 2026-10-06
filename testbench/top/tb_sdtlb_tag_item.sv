// =============================================================================
// tb_sdtlb_tag_item: sdtlb_tag_item 的单元自检 (全相联 CAM 的单条目行为)
//
// 跑法 (在仓库根目录):
//   make -C simulation all TB_TOP=tb_sdtlb_tag_item
//   日志与产物在 simulation/run_single_testcase/tb_sdtlb_tag_item.TestBase/
//
// 说明: 只例化 sdtlb_tag_item, 不依赖 UVM, 也不参与 tb_top 的冒烟流程;
//       覆盖 装入 / 命中比较 / 无效化 / 复位 四类行为,
//       末尾打印 "<N> checks, <M> errors" 与 "RESULT: PASS|FAIL", 失败时再 $fatal 提前结束.
//       注意: VCS 在 $fatal 时退出码仍是 0, 因此判定要看 log/simv.log 里的 RESULT 行,
//       不能只看 make 的返回值 (与仓库现有 UVM 流程的判断口径一致).
// =============================================================================
`timescale 1ns/1ps
module tb_sdtlb_tag_item;

    import sdecoder_pkg::*;

    logic                clk = 0;
    logic                rst_n = 0;
    logic                req_vld;
    logic [PA_WIDTH-1:0] req_pa;
    logic [16:0]         wr_pa_base;
    logic [ 4:0]         wr_pa_up;
    logic                wr_pa_vld;
    logic                inv_all;
    logic                inv_en;
    logic [PA_WIDTH-1:0] inv_pa;
    logic                req_hit;

    int errors = 0;
    int checks = 0;

    always #5 clk = ~clk;

    sdtlb_tag_item dut (
        .clk(clk), .rst_n(rst_n),
        .req_vld(req_vld), .req_pa(req_pa),
        .wr_pa_base(wr_pa_base), .wr_pa_up(wr_pa_up), .wr_pa_vld(wr_pa_vld),
        .inv_all(inv_all), .inv_en(inv_en), .inv_pa(inv_pa),
        .req_hit(req_hit)
    );

    // 段空间索引 = {PA[46:35] (12b), PA[34:30] (5b)}
    function automatic logic [PA_WIDTH-1:0] mk_pa(input logic [11:0] high, input logic [4:0] idx);
        mk_pa = {1'b0, high, idx, 30'h0};
    endfunction

    task automatic chk(input string name, input logic [PA_WIDTH-1:0] pa, input logic exp);
        req_pa = pa; #1;
        checks++;
        if (req_hit !== exp) begin
            errors++;
            $display("FAIL %-30s pa=%h hit=%b exp=%b", name, pa, req_hit, exp);
        end
        else begin
            $display("ok   %-30s pa=%h hit=%b", name, pa, req_hit);
        end
    endtask

    // 用一个时钟周期把 wr_pa_base / wr_pa_up / wr_pa_vld 写入 tag_item
    task automatic load(input logic [16:0] base, input logic [4:0] up);
        @(negedge clk);
        wr_pa_base = base; wr_pa_up = up; wr_pa_vld = 1'b1;
        @(negedge clk);
        wr_pa_vld = 1'b0;
    endtask

    // 按地址置无效, 拉高一拍
    task automatic inv_addr(input logic [PA_WIDTH-1:0] pa);
        @(negedge clk);
        inv_en = 1'b1; inv_pa = pa;
        @(negedge clk);
        inv_en = 1'b0;
    endtask

    // 置无效全部条目, 拉高一拍
    task automatic inv_everything();
        @(negedge clk);
        inv_all = 1'b1;
        @(negedge clk);
        inv_all = 1'b0;
    endtask

    initial begin
        req_vld = 1'b1; req_pa = '0; wr_pa_base = '0; wr_pa_up = '0; wr_pa_vld = 1'b0;
        inv_all = 1'b0; inv_en = 1'b0; inv_pa = '0;
        @(negedge clk); rst_n = 1'b1;

        // ================= 装入与命中比较 =================
        chk("after reset (invalid)", mk_pa(12'h000, 5'd0), 1'b0);

        // 写使能 wr_pa_vld=0 时, 改入口不生效
        @(negedge clk);
        wr_pa_base = {12'h235, 5'd4}; wr_pa_up = 5'd9;
        chk("write disabled (vld=0)", mk_pa(12'h235, 5'd4), 1'b0);

        // 段式: {12'h235, 4}, 上界 9, 闭区间 [4, 9]
        load({12'h235, 5'd4}, 5'd9);
        chk("seg low bound",   mk_pa(12'h235, 5'd4),  1'b1);
        chk("seg upper bound", mk_pa(12'h235, 5'd9),  1'b1);
        chk("seg middle",      mk_pa(12'h235, 5'd6),  1'b1);
        chk("seg below range", mk_pa(12'h235, 5'd3),  1'b0);
        chk("seg above range", mk_pa(12'h235, 5'd10), 1'b0);
        chk("differs PA[35]",  mk_pa(12'h234, 5'd6),  1'b0);
        chk("differs PA[46]",  mk_pa(12'h235 ^ 12'h800, 5'd6), 1'b0);
        chk("differs PA[36]",  mk_pa(12'h235 ^ 12'h002, 5'd6), 1'b0);

        req_vld = 1'b0; chk("req_vld=0", mk_pa(12'h235, 5'd6), 1'b0); req_vld = 1'b1;

        // 装填当拍: 比较仍读旧寄存器, 新值下一拍才生效
        load({12'h100, 5'd7}, 5'd7);
        @(negedge clk);
        wr_pa_base = {12'h0aa, 5'd5}; wr_pa_up = 5'd5; wr_pa_vld = 1'b1;
        chk("same-cycle keeps old",   mk_pa(12'h100, 5'd7), 1'b1);
        chk("same-cycle new pending", mk_pa(12'h0aa, 5'd5), 1'b0);
        @(negedge clk); wr_pa_vld = 1'b0;
        chk("next-cycle new valid",  mk_pa(12'h0aa, 5'd5), 1'b1);
        chk("next-cycle old gone",   mk_pa(12'h100, 5'd7), 1'b0);

        // 覆盖写(重填): 同一地址改映射
        load({12'h0bb, 5'd5}, 5'd5);
        chk("refill: old base miss", mk_pa(12'h0aa, 5'd5), 1'b0);
        chk("refill: new base hit",  mk_pa(12'h0bb, 5'd5), 1'b1);

        // 页式: wr_pa_base[34:30] == wr_pa_up[34:30]
        load({12'h100, 5'd7}, 5'd7);
        chk("page hit",        mk_pa(12'h100, 5'd7), 1'b1);
        chk("page idx-1 miss", mk_pa(12'h100, 5'd6), 1'b0);
        chk("page idx+1 miss", mk_pa(12'h100, 5'd8), 1'b0);

        // 满段: base = 0, up = 31
        load({12'h000, 5'd0}, 5'd31);
        chk("full seg first", mk_pa(12'h000, 5'd0),  1'b1);
        chk("full seg last",  mk_pa(12'h000, 5'd31), 1'b1);

        // 上界饱和, 不产生环形误命中
        load({12'h123, 5'd30}, 5'd31);
        chk("sat 30", mk_pa(12'h123, 5'd30), 1'b1);
        chk("sat 31", mk_pa(12'h123, 5'd31), 1'b1);
        chk("sat 29", mk_pa(12'h123, 5'd29), 1'b0);
        chk("sat 0",  mk_pa(12'h123, 5'd0),  1'b0);

        // ================= 按地址置无效 =================
        inv_addr(mk_pa(12'h123, 5'd31));
        chk("inv inside: cleared",     mk_pa(12'h123, 5'd31), 1'b0);
        chk("inv inside: whole entry", mk_pa(12'h123, 5'd30), 1'b0);

        load({12'h123, 5'd30}, 5'd31);
        inv_addr(mk_pa(12'h123, 5'd29));
        chk("inv below range: kept", mk_pa(12'h123, 5'd30), 1'b1);
        inv_addr(mk_pa(12'h123, 5'd0));
        chk("inv wrap range: kept",  mk_pa(12'h123, 5'd31), 1'b1);
        inv_addr(mk_pa(12'h122, 5'd31));
        chk("inv other seg: kept",   mk_pa(12'h123, 5'd31), 1'b1);
        @(negedge clk); inv_en = 1'b0; inv_pa = mk_pa(12'h123, 5'd31);
        @(negedge clk);
        chk("inv_en=0: kept",        mk_pa(12'h123, 5'd31), 1'b1);

        inv_addr(mk_pa(12'h123, 5'd31));
        chk("inv upper bound inclusive", mk_pa(12'h123, 5'd31), 1'b0);

        // ================= 刷新优先于装入 =================
        // 条目当前无效, 同一拍既装入又按地址置无效(地址命中装入值) -> 保持无效.
        // 这一条验证 inv_match 的条件本身: 若把 tag_item.valid 并进条件, 清位分支不会被
        // 选中, 装入会生效, 这条就会 FAIL.
        @(negedge clk);
        wr_pa_base = {12'h123, 5'd30}; wr_pa_up = 5'd31; wr_pa_vld = 1'b1;
        inv_en = 1'b1; inv_pa = mk_pa(12'h123, 5'd30);
        @(negedge clk);
        wr_pa_vld = 1'b0; inv_en = 1'b0;
        chk("inv wins over fill", mk_pa(12'h123, 5'd30), 1'b0);

        // 条目当前有效, 同一拍既装入(另一段)又按地址置无效(命中当前条目):
        // else if 的优先级生效, 旧条目被清掉, 且新的装入不落进寄存器
        load({12'h123, 5'd30}, 5'd31);
        chk("prio setup: entry valid", mk_pa(12'h123, 5'd30), 1'b1);
        @(negedge clk);
        wr_pa_base = {12'h777, 5'd1}; wr_pa_up = 5'd1; wr_pa_vld = 1'b1;
        inv_en = 1'b1; inv_pa = mk_pa(12'h123, 5'd30);
        @(negedge clk);
        wr_pa_vld = 1'b0; inv_en = 1'b0;
        chk("valid entry: flush clears", mk_pa(12'h123, 5'd30), 1'b0);
        chk("valid entry: fill blocked", mk_pa(12'h777, 5'd1),  1'b0);

        // 反向: 无效化地址不命中时, 同拍的装入照常生效
        @(negedge clk);
        wr_pa_base = {12'h123, 5'd30}; wr_pa_up = 5'd31; wr_pa_vld = 1'b1;
        inv_en = 1'b1; inv_pa = mk_pa(12'h001, 5'd1);
        @(negedge clk);
        wr_pa_vld = 1'b0; inv_en = 1'b0;
        chk("fill proceeds when inv misses", mk_pa(12'h123, 5'd30), 1'b1);

        // inv_all 与装入同拍 -> 条目保持无效
        @(negedge clk);
        wr_pa_base = {12'h123, 5'd30}; wr_pa_up = 5'd31; wr_pa_vld = 1'b1; inv_all = 1'b1;
        @(negedge clk);
        wr_pa_vld = 1'b0; inv_all = 1'b0;
        chk("inv_all wins over fill", mk_pa(12'h123, 5'd30), 1'b0);

        // ================= inv_all 清全部 =================
        load({12'h123, 5'd30}, 5'd31);
        chk("before inv_all", mk_pa(12'h123, 5'd30), 1'b1);
        inv_everything();
        chk("after inv_all",  mk_pa(12'h123, 5'd30), 1'b0);

        // 无效化后可以重新装填
        load({12'h123, 5'd30}, 5'd31);
        chk("refill after inv_all", mk_pa(12'h123, 5'd30), 1'b1);

        // ================= 异步复位 =================
        @(negedge clk); rst_n = 1'b0; #1;
        chk("async reset clears", mk_pa(12'h123, 5'd30), 1'b0);
        rst_n = 1'b1;

        $display("\n%d checks, %d errors", checks, errors);
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
