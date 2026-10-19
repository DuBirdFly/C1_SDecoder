`timescale 1ns/1ps

module tb_sdecoder;
    import sdecoder_pkg::*;

    logic                           clk;
    logic                           rst_n;

    // 代换请求
    logic                           req_valid;
    logic                           req_ready;
    logic [PA_WIDTH-1:0]            req_pa;
    logic [REQ_ID_WIDTH-1:0]        req_id;

    // 代换响应
    logic                           rsp_valid;
    logic                           rsp_ready;
    logic [REQ_ID_WIDTH-1:0]        rsp_id;
    logic [2:0]                     rsp_fcode;
    logic [EID_WIDTH-1:0]           rsp_eid;
    logic [TOKEN_ID_WIDTH-1:0]      rsp_token_id;
    logic [SLA_WIDTH-1:0]           rsp_sla;

    // Page Walk 访存
    logic [PA_WIDTH-1:0]            tw_araddr;
    logic                           tw_arvalid;
    logic                           tw_arready;
    logic [127:0]                   tw_rdata;
    logic                           tw_rvalid;
    logic                           tw_rready;

    // 配置与刷新
    logic                           cfg_wr;
    logic                           cfg_rd;
    logic [SDIOR_ADDR_WIDTH-1:0]    cfg_addr;
    logic [SDIOR_DATA_WIDTH-1:0]    cfg_wdata;
    logic [SDIOR_DATA_WIDTH-1:0]    cfg_rdata;

    // 本地表: A/B 两个页在同一个 32GB 区间里, L1 Type = 0
    localparam logic [PA_WIDTH-1:0] L1_BASE = 48'h0000_0000_1000;
    localparam logic [PA_WIDTH-1:0] L2_BASE = 48'h0000_0000_2000;
    localparam logic [PA_WIDTH-1:0] PA_A    = 48'h0000_0000_1234;
    localparam logic [PA_WIDTH-1:0] PA_B    = 48'h0000_4000_5678;
    localparam logic [PA_WIDTH-1:0] PA_S    = 48'h0000_0009_8000_0111;

    SDT_L1_ITEM_t                   l1_item_page;
    SDT_L1_ITEM_t                   l1_item_seg;
    SDT_L2_ITEM_t                   l2_item [2];

    int                             errors = 0;
    int                             checks = 0;
    int unsigned                    tw_ar_cnt;

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

    sdecoder dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (req_valid),
        .req_ready          (req_ready),
        .req_pa             (req_pa),
        .req_id             (req_id),

        .rsp_valid          (rsp_valid),
        .rsp_ready          (rsp_ready),
        .rsp_id             (rsp_id),
        .rsp_fcode          (rsp_fcode),
        .rsp_eid            (rsp_eid),
        .rsp_token_id       (rsp_token_id),
        .rsp_sla            (rsp_sla),

        .tw_araddr          (tw_araddr),
        .tw_arvalid         (tw_arvalid),
        .tw_arready         (tw_arready),
        .tw_rdata           (tw_rdata),
        .tw_rvalid          (tw_rvalid),
        .tw_rready          (tw_rready),

        .cfg_wr             (cfg_wr),
        .cfg_rd             (cfg_rd),
        .cfg_addr           (cfg_addr),
        .cfg_wdata          (cfg_wdata),
        .cfg_rdata          (cfg_rdata)
    );

    // 本地表读模型: L1 16B 直接返回, L2 8B 按 araddr[3] 放到 16B 总线的对应 lane
    function automatic logic [127:0] mem_read(input logic [PA_WIDTH-1:0] addr);
        logic [63:0] l2_sel;
        begin
            l2_sel = '0;
            if (addr == L1_BASE) begin
                mem_read = l1_item_page;
            end
            else if (addr == (L1_BASE + 48'd16)) begin
                mem_read = l1_item_seg;
            end
            else begin
                for (int i = 0; i < 2; i++) begin
                    if (addr == (L2_BASE + 48'(i * 8))) begin
                        l2_sel = l2_item[i];
                    end
                end
                mem_read = addr[3] ? {l2_sel, 64'b0} : {64'b0, l2_sel};
            end
        end
    endfunction

    // 一拍 AR 对应下一拍 R; 一次只处理一个读
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tw_arready <= 1'b1;
            tw_rvalid  <= 1'b0;
            tw_rdata   <= '0;
            tw_ar_cnt  <= 0;
        end
        else begin
            tw_arready <= 1'b1;
            tw_rvalid  <= tw_arvalid && tw_arready;
            if (tw_arvalid && tw_arready) begin
                tw_rdata   <= mem_read(tw_araddr);
                tw_ar_cnt  <= tw_ar_cnt + 1;
            end
        end
    end

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

    task automatic cfg_write(
        input logic [SDIOR_ADDR_WIDTH-1:0] addr,
        input logic [SDIOR_DATA_WIDTH-1:0] data
    );
        @(posedge clk);
        cfg_wr    <= 1'b1;
        cfg_addr  <= addr;
        cfg_wdata <= data;
        @(posedge clk);
        cfg_wr    <= 1'b0;
        @(posedge clk);
    endtask

    task automatic send_req(
        input logic [PA_WIDTH-1:0]      pa,
        input logic [REQ_ID_WIDTH-1:0]  id
    );
        @(posedge clk);
        req_valid <= 1'b1;
        req_pa    <= pa;
        req_id    <= id;
        do @(posedge clk); while (!req_ready);
        req_valid <= 1'b0;
    endtask

    // rsp_ready 默认为 0, 这里先采样响应, 再拉高 rsp_ready 一拍把它取走
    task automatic wait_rsp(
        input string                        name,
        input logic [REQ_ID_WIDTH-1:0]      exp_id,
        input logic [2:0]                   exp_fcode,
        input logic [EID_WIDTH-1:0]         exp_eid,
        input logic [TOKEN_ID_WIDTH-1:0]    exp_token,
        input logic [SLA_WIDTH-1:0]         exp_sla
    );
        while (!rsp_valid) @(posedge clk);

        chk({name, ": id"},       rsp_id == exp_id);
        chk({name, ": fcode"},    rsp_fcode == exp_fcode);
        if (exp_fcode == 3'b000) begin
            chk({name, ": eid"},      rsp_eid == exp_eid);
            chk({name, ": token_id"}, rsp_token_id == exp_token);
            chk({name, ": sla"},      rsp_sla == exp_sla);
        end

        rsp_ready <= 1'b1;
        @(posedge clk);
        rsp_ready <= 1'b0;
        @(posedge clk);
    endtask

    initial begin
        int unsigned ar_before;

        // 初始驱动
        req_valid  = 1'b0;
        req_pa     = '0;
        req_id     = '0;
        rsp_ready  = 1'b0;
        cfg_wr     = 1'b0;
        cfg_rd     = 1'b0;
        cfg_addr   = '0;
        cfg_wdata  = '0;

        // 本地表: L1 Type=0 (全页表), L2 指向 0x2000; A 用 idx0, B 用 idx1
        l1_item_page = '0;
        l1_item_page.valid    = 1'b1;
        l1_item_page.type_bit = 1'b0;
        l1_item_page.l2_base  = 45'h400;

        // 32GB 区间 1: Type=1, 段覆盖 [4, 8], 页表基地址 0x3000 (本测试只用段内)
        l1_item_seg = '0;
        l1_item_seg.valid    = 1'b1;
        l1_item_seg.type_bit = 1'b1;
        l1_item_seg.l2_base  = 45'h600;
        l1_item_seg.eid      = 11'h300;
        l1_item_seg.token_id = 10'h400;
        l1_item_seg.s_pfn    = 18'h10000;
        l1_item_seg.seg_base = 5'd4;
        l1_item_seg.seg_len  = 5'd4;

        for (int i = 0; i < 2; i++) begin
            l2_item[i] = '0;
            l2_item[i].valid    = 1'b1;
            l2_item[i].eid      = 11'h100 + 11'(i);
            l2_item[i].token_id = 10'h200 + 10'(i);
            l2_item[i].s_pfn    = 18'h1 + 18'(i);
        end

        wait (rst_n === 1'b1);
        repeat (5) @(posedge clk);

        cfg_write(ADDR_SDT_L1_BASE, {16'b0, L1_BASE});
        repeat (5) @(posedge clk);

        // A: 未命中 -> walk -> 响应, 填 SDTLB
        send_req(PA_A, 8'h11);
        wait_rsp("A miss", 8'h11, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});

        // A 再请求: 应命中, 不再走表
        ar_before = tw_ar_cnt;
        send_req(PA_A, 8'h12);
        wait_rsp("A hit", 8'h12, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});
        chk("A hit: no table walk", tw_ar_cnt == ar_before);

        // B: 未命中 + 命中
        send_req(PA_B, 8'h21);
        wait_rsp("B miss", 8'h21, 3'b000,
                 l2_item[1].eid, l2_item[1].token_id,
                 {l2_item[1].s_pfn, PA_B[PA_BASE_LSB-1:0]});

        ar_before = tw_ar_cnt;
        send_req(PA_B, 8'h22);
        wait_rsp("B hit", 8'h22, 3'b000,
                 l2_item[1].eid, l2_item[1].token_id,
                 {l2_item[1].s_pfn, PA_B[PA_BASE_LSB-1:0]});
        chk("B hit: no table walk", tw_ar_cnt == ar_before);

        // 段式: Type=1, PA_S 落在 [4, 8] 内, 只读 L1
        send_req(PA_S, 8'h61);
        wait_rsp("seg miss", 8'h61, 3'b000,
                 l1_item_seg.eid, l1_item_seg.token_id,
                 {l1_item_seg.s_pfn + 18'd2, PA_S[PA_BASE_LSB-1:0]});

        ar_before = tw_ar_cnt;
        send_req(PA_S, 8'h62);
        wait_rsp("seg hit", 8'h62, 3'b000,
                 l1_item_seg.eid, l1_item_seg.token_id,
                 {l1_item_seg.s_pfn + 18'd2, PA_S[PA_BASE_LSB-1:0]});
        chk("seg hit: no table walk", tw_ar_cnt == ar_before);

        // 单独置无效 A, 再让 A miss 和 B hit 同拍在途: B 应先返回
        cfg_write(ADDR_SDECODER_IS, {1'b1, 15'b0, PA_A[PA_WIDTH-1:PA_BASE_LSB], {PA_BASE_LSB{1'b0}}});
        repeat (5) @(posedge clk);

        send_req(PA_A, 8'h31);
        send_req(PA_B, 8'h32);

        wait_rsp("out-of-order B", 8'h32, 3'b000,
                 l2_item[1].eid, l2_item[1].token_id,
                 {l2_item[1].s_pfn, PA_B[PA_BASE_LSB-1:0]});
        wait_rsp("out-of-order A", 8'h31, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});

        // 响应反压: 不取响应时 req_ready 应拉低
        rsp_ready <= 1'b0;
        send_req(PA_A, 8'h41);
        while (!rsp_valid) @(posedge clk);
        chk("backpressure: rsp_valid", rsp_valid == 1'b1);
        chk("backpressure: req_ready low", req_ready == 1'b0);
        wait_rsp("backpressure A", 8'h41, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});
        chk("backpressure: req_ready recovered", req_ready == 1'b1);

        // 全部置无效: A 需要重新 walk, 然后再命中
        cfg_write(ADDR_SDECODER_IA, 64'h1);
        repeat (5) @(posedge clk);

        send_req(PA_A, 8'h51);
        wait_rsp("A miss after inv_all", 8'h51, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});

        ar_before = tw_ar_cnt;
        send_req(PA_A, 8'h52);
        wait_rsp("A hit after inv_all", 8'h52, 3'b000,
                 l2_item[0].eid, l2_item[0].token_id,
                 {l2_item[0].s_pfn, PA_A[PA_BASE_LSB-1:0]});
        chk("A hit after inv_all: no table walk", tw_ar_cnt == ar_before);

        $display("\n%d checks, %d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
        end
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
