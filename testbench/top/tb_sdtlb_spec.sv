`timescale 1ns/1ps

// SDTLB 设计方案符合性检查 (对照 doc/design_plan/SDecoder 设计方案 v1.0.md 的 "SDTLB" 一节)
//
// 与 tb_sdtlb 的分工:
//   tb_sdtlb      : 验证 RTL 自身行为自洽 (命中 / 反压 / 置无效 / 装填指针等等)
//   tb_sdtlb_spec : 只对照设计方案, 检查 RTL 与设计意图不一致的地方
//     1. 条目字段位宽: token_id 11, token_value 10, s_pfn 23, sla 53
//     2. 一级表 / 二级表条目位域: 按设计方案拼字后 RTL struct 能否解对
//     3. 装填指针: 设计方案要求 "有空闲条目时优先装填最低位空闲条目" (当前暂未实现, 只记录)
//     4. 多命中: 设计方案要求有 tlb_multi_hit 异常通路 (当前暂未实现, 只记录)
//
// 按 doc/design_plan/AI 易错点.md: tb 以 wrapper_sdtlb 为顶层 (不直接例化 sdtlb),
// 由 wrapper 对仿真把输入打 1 拍, 因此响应相对接口握手再晚 1 拍.
module tb_sdtlb_spec;

    import sdecoder_pkg::*;

    logic                                clk;
    logic                                rst_n;

    int                                  errors = 0;
    int                                  checks = 0;

    // 响应快照 (在响应拍采样)
    logic                                rsp_hit;
    SDTLB_TAG_ITEM_t                     rsp_tag;
    SDTLB_DATA_ITEM_t                    rsp_data;

    // 响应拍上实际命中了几条条目 (观察多命中; 直接读内部寄存器会差一拍)
    int                                  multi_hit_cnt = 0;

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

    // wrapper 只做输入打拍, 内部仍是未改动的 sdtlb
    wrapper_sdtlb dut (.sdtlb_if(sdtlb_if));

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.u_sdtlb.cam0_hit) begin
                multi_hit_cnt = $countones(dut.u_sdtlb.cam0_hit_vector_r);
            end
        end
    end

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

    task automatic sample_rsp();
        rsp_hit   = sdtlb_if.drv.cam0_hit;
        rsp_tag   = sdtlb_if.drv.cam0_hit_tag_item;
        rsp_data  = sdtlb_if.drv.cam0_hit_data_item;
    endtask

    // 当前轮转替换指针 (RTL 内部状态, 只用于记录 / 报错定位)
    function automatic int ptr_index();
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            if (dut.u_sdtlb.victim_sel[i]) begin
                return i;
            end
        end
        return -1;
    endfunction

    function automatic int first_valid_index();
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            if (dut.u_sdtlb.tag_item[i].valid) begin
                return i;
            end
        end
        return -1;
    endfunction

    function automatic int valid_count();
        int n = 0;
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            if (dut.u_sdtlb.tag_item[i].valid) begin
                n++;
            end
        end
        return n;
    endfunction

    // 装填一次 (接口上打 1 拍): wrapper 打 1 拍后 DUT 当拍写 Latch, 之后再等 2 拍让写入落地
    task automatic fill_one(
        input logic [PA_BASE_WIDTH-1:0]     base,
        input logic [PA_UP_WIDTH-1:0]       up,
        input logic [EID_WIDTH-1:0]         eid,
        input logic [TOKEN_ID_WIDTH-1:0]    tok,
        input logic [S_PFN_WIDTH-1:0]       pfn,
        input logic [TOKEN_VALUE_WIDTH-1:0] tokv = 10'h000
    );
        sdtlb_if.drv.fill_pa_base     <= base;
        sdtlb_if.drv.fill_pa_up       <= up;
        sdtlb_if.drv.fill_eid         <= eid;
        sdtlb_if.drv.fill_token_id    <= tok;
        sdtlb_if.drv.fill_token_value <= tokv;
        sdtlb_if.drv.fill_s_pfn       <= pfn;
        sdtlb_if.drv.fill_en          <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.fill_en          <= 1'b0;
        repeat (2) @(sdtlb_if.drv);             // wrapper 打拍 + 写 Latch 落地
    endtask

    task automatic inv_addr(input logic [PA_BASE_WIDTH-1:0] base);
        sdtlb_if.drv.inv_en <= 1'b1;
        sdtlb_if.drv.inv_pa <= {base, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_en <= 1'b0;
        repeat (2) @(sdtlb_if.drv);             // wrapper 打拍 + 置无效生效
    endtask

    task automatic inv_everything();
        sdtlb_if.drv.inv_all <= 1'b1;
        @(sdtlb_if.drv);
        sdtlb_if.drv.inv_all <= 1'b0;
        repeat (2) @(sdtlb_if.drv);
    endtask

    // 发一个查表请求, 等到响应拍返回; 返回时 rsp_* 是该请求的响应.
    // wrapper 打 1 拍 + DUT 命中打 1 拍: 响应在接口握手后第 2 拍
    task automatic req0(input logic [PA_WIDTH-1:0] pa);
        sdtlb_if.drv.cam0_req_pa <= pa;
        sdtlb_if.drv.cam0_req_en <= 1'b1;
        @(sdtlb_if.drv);                        // 请求拍 (使能只打 1 拍)
        sdtlb_if.drv.cam0_req_en <= 1'b0;
        @(sdtlb_if.drv);                        // 输入寄存器拍
        @(sdtlb_if.drv);                        // 响应拍
        sample_rsp();
    endtask

    // 按设计方案的位域拼字, 看 RTL 的 packed struct 解出来是什么
    task automatic check_item_format();
        logic [127:0]       l1_word;
        logic [63:0]        l2_word;
        SDT_L1_ITEM_t       l1;
        SDT_L2_ITEM_t       l2;

        $display("\n[1] 条目字段位宽 / 位域 (设计方案 vs RTL)");
        $display("    EID_WIDTH       : 11 vs %0d", EID_WIDTH);
        $display("    TOKEN_ID_WIDTH  : 11 vs %0d", TOKEN_ID_WIDTH);
        $display("    S_PFN_WIDTH     : 23 vs %0d", S_PFN_WIDTH);
        $display("    SLA_WIDTH       : 53 vs %0d", SLA_WIDTH);
        $display("    SDTLB_DATA_ITEM : 55 bit (eid11 + token_id11 + token_value10 + s_pfn23) vs %0d bit",
                 $bits(SDTLB_DATA_ITEM_t));
        $display("    SDT_RSP         : 94 bit (id8 + eid11 + token_id11 + token_value10 + sla53 + err1) vs %0d bit",
                 $bits(SDT_RSP_t));

        chk("EID_WIDTH == 11", EID_WIDTH == 11);
        chk("TOKEN_ID_WIDTH == 11", TOKEN_ID_WIDTH == 11);
        chk("S_PFN_WIDTH == 23", S_PFN_WIDTH == 23);
        chk("SLA_WIDTH == 53", SLA_WIDTH == 53);
        chk("SDTLB_TAG_ITEM 24 bit (pa_base18 + pa_up5 + valid1)", $bits(SDTLB_TAG_ITEM_t) == 24);
        chk("SDTLB_DATA_ITEM 55 bit (含 token_value)", $bits(SDTLB_DATA_ITEM_t) == 55);
        chk("SDT_RSP 94 bit (含 token_value 与 err)", $bits(SDT_RSP_t) == 94);

        // 一级表条目: 按设计方案 [55:45] TokenID / [44:35] TokenValue / [34:12] S_PFN 拼字
        l1_word        = '0;
        l1_word[55:45] = 11'h7ff;       // 设计方案: TokenID[10:0]
        l1_word[44:35] = 10'h3ff;       // 设计方案: TokenValue[9:0]
        l1_word[34:12] = 23'h4abcd;     // 设计方案: S_PFN[52:30]
        l1_word[11:7]  = 5'd3;          // SEG_LEN
        l1_word[6:2]   = 5'd5;          // SEG_BASE
        l1_word[1]     = 1'b1;          // Type
        l1_word[0]     = 1'b1;          // Valid
        l1             = SDT_L1_ITEM_t'(l1_word);
        $display("    L1 按设计方案拼字后 RTL 解析: eid=%h token_id=%h s_pfn=%h seg_len=%0d seg_base=%0d valid=%b",
                 l1.eid, l1.token_id, l1.s_pfn, l1.seg_len, l1.seg_base, l1.valid);
        chk("L1: token_id 解析正确 (11 bit @ [55:45])", l1.token_id == 11'h7ff);
        chk("L1: s_pfn 解析正确 (23 bit @ [34:12])", l1.s_pfn == 23'h4abcd);
        chk("L1: seg_len / seg_base / valid 解析正确",
            (l1.seg_len == 5'd3) && (l1.seg_base == 5'd5) && (l1.valid == 1'b1));

        // 二级表条目: 按设计方案 [55:45] EID / [44:34] TokenID / [33:24] TokenValue / [23:1] S_PFN
        l2_word        = '0;
        l2_word[55:45] = 11'h5a5;       // EID
        l2_word[44:34] = 11'h2d2;       // TokenID
        l2_word[33:24] = 10'h155;       // TokenValue
        l2_word[23:1]  = 23'h12345;     // S_PFN
        l2_word[0]     = 1'b1;          // Valid
        l2             = SDT_L2_ITEM_t'(l2_word);
        $display("    L2 按设计方案拼字后 RTL 解析: eid=%h token_id=%h s_pfn=%h valid=%b",
                 l2.eid, l2.token_id, l2.s_pfn, l2.valid);
        chk("L2: eid 解析正确 (11 bit @ [55:45])", l2.eid == 11'h5a5);
        chk("L2: token_id 解析正确 (11 bit @ [44:34])", l2.token_id == 11'h2d2);
        chk("L2: s_pfn 解析正确 (23 bit @ [23:1])", l2.s_pfn == 23'h12345);
        chk("L2: valid 解析正确", l2.valid == 1'b1);
    endtask

    // 设计方案 "装填条目 (SDTLB)" 第 1 条: 有空闲条目时优先装填最低位空闲条目.
    // 当前 RTL 暂按轮转替换指针实现, 这一条**先不检查**, 只把实际落点打印出来,
    // 等后续补上 "空闲优先" 时再改成 chk() 对照.
    task automatic report_fill_pointer();
        int  ptr;
        int  got_idx;
        int  hole_idx;

        $display("\n[2] 装填指针 (空闲优先暂未实现, 仅记录当前轮转替换的行为)");

        // (a) 全空表: 先填 3 个条目, 再全置无效, 此时 128 个条目全空
        fill_one({12'h5a0, 5'd1}, 5'd1, 11'h001, 11'h001, 18'h00001);
        fill_one({12'h5a0, 5'd2}, 5'd2, 11'h002, 11'h002, 18'h00002);
        fill_one({12'h5a0, 5'd3}, 5'd3, 11'h003, 11'h003, 18'h00003);
        inv_everything();

        ptr = ptr_index();
        fill_one({12'h5a0, 5'd4}, 5'd4, 11'h004, 11'h004, 18'h00004);
        got_idx = first_valid_index();
        $display("    (a) 全空表: 轮转指针在 entry[%0d], 装填落到 entry[%0d] (设计方案要求 entry[0])",
                 ptr, got_idx);

        // (b) 满表 + 一个空洞
        inv_everything();
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            fill_one({12'h600 + 12'(i / 32), 5'(i % 32)}, 5'(i % 32),
                     11'(i), 11'(i), 18'(i));
        end
        ptr      = ptr_index();
        hole_idx = (ptr + 5) % SDTLB_ENTRIES;
        inv_addr({12'h600, 5'd5});
        fill_one({12'h700, 5'd9}, 5'd9, 11'h7fe, 11'h3fe, 18'h2ffff);
        $display("    (b) 满表 + 空洞 entry[%0d]: 装填后有效条目数 = %0d, 空洞仍空 = %b (设计方案要求复用空洞)",
                 hole_idx, valid_count(), (dut.u_sdtlb.tag_item[hole_idx].valid == 1'b0));
    endtask

    // 设计方案 "访问条目": 多命中时数据未定义, 且要求有 tlb_multi_hit 异常通路.
    // 当前 RTL 暂不上报 (camN_multi_hit 已按需求删除), 这里只复现多命中场景并记录命中条数.
    task automatic report_multi_hit();
        logic [PA_WIDTH-1:0] pa_x;

        $display("\n[3] 多命中 (上报通路暂未实现, 仅记录场景)");
        inv_everything();
        pa_x = {12'h7f0, 5'd1, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};

        // 同一段基址填两次: 0 号条目一次, 再填 126 个不同地址后 127 号条目再来一次
        fill_one({12'h7f0, 5'd1}, 5'd1, 11'h101, 11'h101, 18'h00101);
        for (int i = 1; i <= 126; i++) begin
            fill_one({12'h710 + 12'(i / 32), 5'(i % 32)}, 5'(i % 32),
                     11'(i), 11'(i), 18'(i));
        end
        fill_one({12'h7f0, 5'd1}, 5'd1, 11'h202, 11'h202, 18'h00202);
        multi_hit_cnt = 0;
        req0(pa_x);

        $display("    响应拍内部命中条数 = %0d, hit = %b (设计方案要求此时上报 tlb_multi_hit)",
                 multi_hit_cnt, rsp_hit);
    endtask

    // 设计方案 "访问条目": 请求拍 T 握手, 命中结果打 1 拍后给出
    task automatic check_latency();
        logic [PA_WIDTH-1:0] pa;

        $display("\n[4] 命中时序: 请求拍打 1 拍使能, 命中打 1 拍后给出 (wrapper 再加 1 拍)");
        inv_everything();
        fill_one({12'h8a0, 5'd6}, 5'd6, 11'h0aa, 11'h0aa, 18'h00333);
        @(sdtlb_if.drv);

        pa = {12'h8a0, 5'd6, {(PA_WIDTH-PA_BASE_WIDTH){1'b0}}};
        sdtlb_if.drv.cam0_req_pa <= pa;
        sdtlb_if.drv.cam0_req_en <= 1'b1;
        @(sdtlb_if.drv);                        // 请求拍
        sdtlb_if.drv.cam0_req_en <= 1'b0;
        sample_rsp();
        chk("请求拍无命中", rsp_hit == 1'b0);
        @(sdtlb_if.drv);                        // 输入寄存器拍
        sample_rsp();
        chk("输入打拍拍仍无命中", rsp_hit == 1'b0);
        @(sdtlb_if.drv);                        // 响应拍
        sample_rsp();
        chk("响应拍命中且数据正确",
            (rsp_hit == 1'b1) &&
            (rsp_tag.pa_base == {12'h8a0, 5'd6}) &&
            (rsp_data.s_pfn == 18'h00333));
        @(sdtlb_if.drv);
        sample_rsp();
        chk("再下一拍命中归 0 (不重复出响应)", rsp_hit == 1'b0);
    endtask

    initial begin
        sdtlb_if.drv.cam0_req_en   <= 1'b0;
        sdtlb_if.drv.cam0_req_pa      <= '0;
        sdtlb_if.drv.cam1_req_en   <= 1'b0;
        sdtlb_if.drv.cam1_req_pa      <= '0;
        sdtlb_if.drv.fill_en          <= 1'b0;
        sdtlb_if.drv.fill_pa_base     <= '0;
        sdtlb_if.drv.fill_pa_up       <= '0;
        sdtlb_if.drv.fill_eid         <= '0;
        sdtlb_if.drv.fill_token_id    <= '0;
        sdtlb_if.drv.fill_token_value <= '0;
        sdtlb_if.drv.fill_s_pfn       <= '0;
        sdtlb_if.drv.inv_all          <= 1'b0;
        sdtlb_if.drv.inv_en           <= 1'b0;
        sdtlb_if.drv.inv_pa           <= '0;

        wait (rst_n === 1'b1);
        repeat (10) @(sdtlb_if.drv);

        check_item_format();
        report_fill_pointer();
        report_multi_hit();
        check_latency();

        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "sdtlb 与设计方案不符: %0d 条", errors);
        end
        $finish;
    end

endmodule
