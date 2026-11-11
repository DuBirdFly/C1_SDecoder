`timescale 1ns/1ps

// 实验: 不改 rtl, 用 wrapper_sdtlb 把 sdtlb 的所有 input (cam* / fill* / inv*)
// 都打 1 拍再送进未改动的 sdtlb, 看这个修法的效果.
//
// 所有 input 同一个 clk 域, 统一打拍后 fill 和 inv 仍然同拍到达阵列,
// 因此同拍 inv_all + fill 的置无效优先可以保留 (不像只打 fill* 时会被回退).
// 代价是整条接口多 1 拍延迟, tb 的请求/响应采样也要多等一个时钟块事件.
//
// 注意: 装填之间留了间隔. 如果 fill_en 连续有效, 打拍后的使能与数据仍在同一沿更新,
// Latch 可能在使能落下前抓到下一拍的数据 (9496ad4 为此在写数据上加了一级缓冲).
//
// 期望效果:
//   1. 绕圈后不再出现重复 tag -> a_cam0_hit_vector_onehot0 不再报;
//   2. 同拍 inv_all + fill 的置无效优先保留 (两者一起晚 1 拍);
//   3. 反压拍从 fill 请求拍挪到写拍 T+1.
module tb_sdtlb_fix;

    import sdecoder_pkg::*;

    logic                   clk;
    logic                   rst_n;

    int                     errors = 0;
    int                     checks = 0;

    logic                   rsp_hit;
    logic [SDTLB_ENTRIES-1:0] hit_vector;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_vector <= '0;
        end
        else begin
            hit_vector <= dut.u_sdtlb.cam0_hit_vector_r;
        end
    end

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

    sdtlb_if sdtlb_if (.clk(clk), .rst_n(rst_n));

    wrapper_sdtlb dut (.sdtlb_if(sdtlb_if));

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb_fix, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdtlb_fix);
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

    task automatic set_req(
        logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0]   high,
        logic [PA_UP_WIDTH-1:0]                 idx
    );
        sdtlb_if.drv.cam0_req_valid <= 1'b1;
        sdtlb_if.drv.cam0_req_pa    <= {high, idx, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        do @(sdtlb_if.drv); while (!sdtlb_if.drv.cam0_req_ready);
        sdtlb_if.drv.cam0_req_valid <= 1'b0;
        @(sdtlb_if.drv);                        // 输入寄存器拍
        @(sdtlb_if.drv);                        // 响应拍 (整条接口多 1 拍)
        rsp_hit = sdtlb_if.drv.cam0_hit;
    endtask

    task automatic fill_one(
        input logic [PA_BASE_WIDTH-1:0]     base,
        input logic [PA_UP_WIDTH-1:0]       up,
        input logic [EID_WIDTH-1:0]         eid,
        input logic [TOKEN_ID_WIDTH-1:0]    tok,
        input logic [S_PFN_WIDTH-1:0]       pfn
    );
        sdtlb_if.drv.fill_pa_base  <= base;
        sdtlb_if.drv.fill_pa_up    <= up;
        sdtlb_if.drv.fill_eid      <= eid;
        sdtlb_if.drv.fill_token_id <= tok;
        sdtlb_if.drv.fill_s_pfn    <= pfn;
        sdtlb_if.drv.fill_en       <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_en       <= 1'b0;
    endtask

    // 同拍给 fill 和 inv_all
    task automatic fill_with_inv_all(
        input logic [PA_BASE_WIDTH-1:0]     base,
        input logic [PA_UP_WIDTH-1:0]       up,
        input logic [EID_WIDTH-1:0]         eid,
        input logic [TOKEN_ID_WIDTH-1:0]    tok,
        input logic [S_PFN_WIDTH-1:0]       pfn
    );
        sdtlb_if.drv.fill_pa_base  <= base;
        sdtlb_if.drv.fill_pa_up    <= up;
        sdtlb_if.drv.fill_eid      <= eid;
        sdtlb_if.drv.fill_token_id <= tok;
        sdtlb_if.drv.fill_s_pfn    <= pfn;
        sdtlb_if.drv.fill_en       <= 1'b1;
        sdtlb_if.drv.inv_all       <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_en       <= 1'b0;
        sdtlb_if.drv.inv_all       <= 1'b0;
    endtask

    function automatic logic [PA_BASE_WIDTH-1:0] tag_of(input int i);
        return {12'h100 + 12'(i / 32), 5'(i % 32)};
    endfunction

    localparam int                          LAST = SDTLB_ENTRIES - 1;
    localparam logic [PA_BASE_WIDTH-1:0]    LAST_TAG = tag_of(LAST);

    task automatic print_table();
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            $display("  entry[%0d] = valid=%b pa_base=%h pa_up=%0d s_pfn=%0d",
                     i,
                     dut.u_sdtlb.tag_item[i].valid,
                     dut.u_sdtlb.tag_item[i].pa_base,
                     dut.u_sdtlb.tag_item[i].pa_up,
                     dut.u_sdtlb.data_item[i].s_pfn);
        end
    endtask

    initial begin
        sdtlb_if.drv.cam0_req_valid <= 1'b0;
        sdtlb_if.drv.cam0_req_pa    <= '0;
        sdtlb_if.drv.cam1_req_valid <= 1'b0;
        sdtlb_if.drv.cam1_req_pa    <= '0;
        sdtlb_if.drv.fill_en        <= 1'b0;
        sdtlb_if.drv.fill_pa_base   <= '0;
        sdtlb_if.drv.fill_pa_up     <= '0;
        sdtlb_if.drv.fill_eid       <= '0;
        sdtlb_if.drv.fill_token_id  <= '0;
        sdtlb_if.drv.fill_s_pfn     <= '0;
        sdtlb_if.drv.inv_all        <= 1'b0;
        sdtlb_if.drv.inv_en         <= 1'b0;
        sdtlb_if.drv.inv_pa         <= '0;

        wait (rst_n === 1'b1);
        repeat (10) @(sdtlb_if.drv);

        // ====================================================================
        // 1. 顺序装填一圈 (留出间隔, 让打拍后的数据稳定), 再用最后一条的 tag 查表
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            fill_one(tag_of(i), 5'(i % 32), 11'(i), 10'(i), 18'(i));
            repeat (3) @(sdtlb_if.drv);
        end
        repeat (10) @(sdtlb_if.drv);

        set_req(.high(LAST_TAG[PA_BASE_WIDTH-1:PA_UP_WIDTH]), .idx(LAST_TAG[PA_UP_WIDTH-1:0]));
        @(negedge clk);
        $display("");
        $display("--------------------------------------------------------------");
        $display("[FILL 打拍] 查表 tag = {12'h%h, 5'd%0d} (最后一条)",
                 LAST_TAG[PA_BASE_WIDTH-1:PA_UP_WIDTH], LAST_TAG[PA_UP_WIDTH-1:0]);
        $display("  cam0_hit          = %b", rsp_hit);
        $display("  cam0_hit_vector_r = %b, 命中条目数 = %0d", hit_vector, $countones(hit_vector));
        print_table();
        $display("--------------------------------------------------------------");
        chk("1. 最后一条命中", rsp_hit == 1'b1);
        chk("1. 命中向量 onehot0 (无重复 tag)", $onehot0(hit_vector));
        chk("1. 只命中最后一条", hit_vector == ({{(SDTLB_ENTRIES-1){1'b0}}, 1'b1} << LAST));

        // 0 号条目应该还是第一次装填的内容, 没有被绕圈写坏
        // note: 上面为了抓 hit_vector 等到了 negedge, 这里先回到时钟块事件再发请求
        @(sdtlb_if.drv);
        set_req(.high(12'h100), .idx(5'd0));
        chk("1. 0 号条目仍是第一次装填的内容 (pfn = 0)",
            (rsp_hit == 1'b1) && (sdtlb_if.drv.cam0_hit_data_item.s_pfn == 18'd0));
        repeat (5) @(sdtlb_if.drv);

        // ====================================================================
        // 2. 同拍 inv_all + fill: 置无效优先, 本次装填应当被丢弃
        fill_with_inv_all(tag_of(0), 5'd0, 11'h7ff, 10'h3ff, 18'h3ffff);
        repeat (10) @(sdtlb_if.drv);
        set_req(.high(12'h100), .idx(5'd0));
        $display("");
        $display("[同拍 inv_all + fill] 查表刚想装填的 tag = {12'h100, 5'd0}");
        $display("  cam0_hit = %b (期望 0: inv_all 赢)", rsp_hit);
        chk("2. 同拍 inv_all + fill: 置无效优先", rsp_hit == 1'b0);
        repeat (5) @(sdtlb_if.drv);

        // ====================================================================
        // 3. 反压拍位置: 请求拍 T ready 应为 1, 写拍 T+1 才拉低
        sdtlb_if.drv.fill_pa_base <= {12'h300, 5'd1};
        sdtlb_if.drv.fill_pa_up   <= 5'd1;
        sdtlb_if.drv.fill_en      <= 1'b1;
        @(sdtlb_if.drv);                        // 请求拍 T
        $display("");
        $display("[反压拍] 请求拍 T: cam0_req_ready = %b (期望 1)", sdtlb_if.drv.cam0_req_ready);
        chk("3. 请求拍 ready = 1", sdtlb_if.drv.cam0_req_ready == 1'b1);
        sdtlb_if.drv.fill_en <= 1'b0;
        @(sdtlb_if.drv);                        // 写拍 T+1
        $display("[反压拍] 写拍 T+1: cam0_req_ready = %b (期望 0)", sdtlb_if.drv.cam0_req_ready);
        chk("3. 写拍 ready = 0", sdtlb_if.drv.cam0_req_ready == 1'b0);
        @(sdtlb_if.drv);                        // 写拍之后
        chk("3. 写拍后 ready = 1", sdtlb_if.drv.cam0_req_ready == 1'b1);

        $display("");
        $display("==============================================================");
        $display("[SUMMARY] cam* / fill* / inv* 都打 1 拍:");
        $display("  - 绕圈后的重复 tag / onehot0: 已消除");
        $display("  - 同拍 inv_all + fill 的置无效优先: 保留 (inv 与 fill 一起晚 1 拍)");
        $display("  - 反压拍: 从 fill 请求拍挪到写拍 T+1");
        $display("  - 代价: cam* / fill* / inv* 全部多 1 拍延迟");
        $display("==============================================================");

        $display("\n%0d checks, %0d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdtlb fill 打拍实验有 %0d 条不符", errors);
        end
        $finish;
    end

endmodule
