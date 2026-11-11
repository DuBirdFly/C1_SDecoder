`timescale 1ns/1ps

// 复现 tb_sdtlb 的 assert error: a_cam0_hit_vector_onehot0 (CAM1 侧同理).
//
// 根因 (sdtlb / sdtlb_tag_item 的装填写使能):
//   写 Latch 的使能是组合量 fill_en ? victim_sel : '0, 而 victim_sel 又在装填沿自己
//   步进到下一格. 使能与指针同沿变化, 写沿之后这个组合使能会短暂指向下一格 (tb 里是
//   drv 块 output skew 的窗口, 硬件里是同沿竞争), 下一格的 Latch 对输入透明, 于是本次
//   tag / data 又被写进下一格 (Valid 是 FF, 这一拍不动).
//   顺序装填时下一格还没 Valid, 看不出问题; 指针绕满一圈时下一格正好是 0 号, 而 0 号
//   本来就 Valid —— 两个有效条目带着同一条 tag, 查表命中向量出现 2 位, $onehot0 失败.
//
// 最小序列:
//   1. 顺序装填 SDTLB_ENTRIES 个互不相同的条目, 轮转指针正好绕回 0 号;
//   2. 最后一次装填 (SDTLB_ENTRIES-1 号) 的 tag / data 同时被写进 0 号, 0 号仍然 Valid;
//   3. 用最后一条的 tag 查表 -> 0 号与最后一条都命中, onehot0 被打破.
module tb_sdtlb_err;

    import sdecoder_pkg::*;

    logic                   clk;
    logic                   rst_n;

    int                     errors = 0;
    int                     checks = 0;

    logic                   rsp_hit;
    logic [SDTLB_ENTRIES-1:0] hit_vector;

    // 断言检查的是寄存器输出 cam0_hit_vector_r. 该寄存器在 posedge 更新, 所以在 posedge
    // 的 active 区 (NBA 之前) 抓到的才是"响应拍"的值; negedge 时 NBA 已落定, 直接读即可
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hit_vector <= '0;
        end
        else begin
            hit_vector <= dut.cam0_hit_vector_r;
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

    sdtlb dut (
        .clk(clk), .rst_n(rst_n),

        .cam0_req_valid(sdtlb_if.cam0_req_valid), .cam0_req_ready(sdtlb_if.cam0_req_ready),
        .cam0_req_pa(sdtlb_if.cam0_req_pa),
        .cam0_hit(sdtlb_if.cam0_hit),
        .cam0_hit_tag_item(sdtlb_if.cam0_hit_tag_item), .cam0_hit_data_item(sdtlb_if.cam0_hit_data_item),

        .cam1_req_valid(sdtlb_if.cam1_req_valid), .cam1_req_ready(sdtlb_if.cam1_req_ready),
        .cam1_req_pa(sdtlb_if.cam1_req_pa),
        .cam1_hit(sdtlb_if.cam1_hit),
        .cam1_hit_tag_item(sdtlb_if.cam1_hit_tag_item), .cam1_hit_data_item(sdtlb_if.cam1_hit_data_item),

        .fill_en(sdtlb_if.fill_en), .fill_pa_base(sdtlb_if.fill_pa_base), .fill_pa_up(sdtlb_if.fill_pa_up),
        .fill_eid(sdtlb_if.fill_eid), .fill_token_id(sdtlb_if.fill_token_id),
        .fill_s_pfn(sdtlb_if.fill_s_pfn),
        .inv_all(sdtlb_if.inv_all), .inv_en(sdtlb_if.inv_en), .inv_pa(sdtlb_if.inv_pa)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_sdtlb_err, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_sdtlb_err);
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

    // 与 tb_sdtlb 相同的查表驱动: 等到响应拍再返回, 此时 rsp_hit 是本次请求的响应
    task automatic set_req(
        logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0]   high,
        logic [PA_UP_WIDTH-1:0]                 idx
    );
        sdtlb_if.drv.cam0_req_valid <= 1'b1;
        sdtlb_if.drv.cam0_req_pa    <= {high, idx, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        do @(sdtlb_if.drv); while (!sdtlb_if.drv.cam0_req_ready);
        sdtlb_if.drv.cam0_req_valid <= 1'b0;
        @(sdtlb_if.drv);                    // 响应拍 (打 1 拍)
        rsp_hit = sdtlb_if.drv.cam0_hit;
    endtask

    // 装填一个条目 (drv 块驱动一拍)
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

    // 第 i 个装填用的 tag: 12 位段高位 + 5 位段内页号, 各条互不相同
    function automatic logic [PA_BASE_WIDTH-1:0] tag_of(input int i);
        return {12'h100 + 12'(i / 32), 5'(i % 32)};
    endfunction

    localparam int                          LAST = SDTLB_ENTRIES - 1;
    localparam logic [PA_BASE_WIDTH-1:0]    LAST_TAG = tag_of(LAST);

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

        // 顺序装填 SDTLB_ENTRIES 条互不相同的 tag, 轮转指针正好绕回 0 号
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            fill_one(tag_of(i), 5'(i % 32), 11'(i), 10'(i), 18'(i));
        end
        repeat (20) @(sdtlb_if.drv);

        // 用最后一条的 tag 查表: 最后一条与绕圈时被写坏的 0 号都命中
        set_req(.high(LAST_TAG[PA_BASE_WIDTH-1:PA_UP_WIDTH]), .idx(LAST_TAG[PA_UP_WIDTH-1:0]));
        @(negedge clk);
        $display("");
        $display("--------------------------------------------------------------");
        $display("查表 tag          = {12'h%h, 5'd%0d} (第 %0d 次装填)",
                 LAST_TAG[PA_BASE_WIDTH-1:PA_UP_WIDTH], LAST_TAG[PA_UP_WIDTH-1:0], SDTLB_ENTRIES);
        $display("cam0_hit          = %b", rsp_hit);
        $display("cam0_hit_vector_r = %b", hit_vector);
        $display("命中条目数        = %0d", $countones(hit_vector));
        $display("0 号条目 = valid=%b pa_base=%h pa_up=%0d s_pfn=%0d",
                 dut.tag_item[0].valid, dut.tag_item[0].pa_base, dut.tag_item[0].pa_up,
                 dut.data_item[0].s_pfn);
        $display("%0d 号条目 = valid=%b pa_base=%h pa_up=%0d s_pfn=%0d",
                 SDTLB_ENTRIES-1,
                 dut.tag_item[SDTLB_ENTRIES-1].valid, dut.tag_item[SDTLB_ENTRIES-1].pa_base,
                 dut.tag_item[SDTLB_ENTRIES-1].pa_up, dut.data_item[SDTLB_ENTRIES-1].s_pfn);
        $display("--------------------------------------------------------------");

        chk("查表命中", rsp_hit == 1'b1);
        chk("命中向量必须 onehot0", $onehot0(hit_vector));

        $display("\n%0d checks, %0d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdtlb 命中向量 onehot0 检查失败: %0d 条", errors);
        end
        $finish;
    end

endmodule
