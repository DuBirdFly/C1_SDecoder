`timescale 1ns/1ps

module tb_sdecoder;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    logic clk;
    logic rst_n;

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

    sdecoder_if sdecoder_if (
        .clk    (clk),
        .rst_n  (rst_n)
    );

    sdecoder dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (sdecoder_if.req_valid),
        .req_ready          (sdecoder_if.req_ready),
        .req_pa             (sdecoder_if.req_pa),
        .req_id             (sdecoder_if.req_id),

        .rsp_valid          (sdecoder_if.rsp_valid),
        .rsp_ready          (sdecoder_if.rsp_ready),
        .rsp_id             (sdecoder_if.rsp_id),
        .rsp_fcode          (sdecoder_if.rsp_fcode),
        .rsp_eid            (sdecoder_if.rsp_eid),
        .rsp_token_id       (sdecoder_if.rsp_token_id),
        .rsp_sla            (sdecoder_if.rsp_sla),

        .tw_araddr          (sdecoder_if.tw_araddr),
        .tw_arvalid         (sdecoder_if.tw_arvalid),
        .tw_arready         (sdecoder_if.tw_arready),
        .tw_rdata           (sdecoder_if.tw_rdata),
        .tw_rvalid          (sdecoder_if.tw_rvalid),
        .tw_rready          (sdecoder_if.tw_rready),

        .cfg_wr             (sdecoder_if.cfg_wr),
        .cfg_rd             (sdecoder_if.cfg_rd),
        .cfg_addr           (sdecoder_if.cfg_addr),
        .cfg_wdata          (sdecoder_if.cfg_wdata),
        .cfg_rdata          (sdecoder_if.cfg_rdata)
    );

    // 本地表: A/B 两个页在同一个 32GB 区间里, L1 Type = 0
    localparam logic [PA_WIDTH-1:0] L1_BASE = 48'h0000_0000_1000;
    localparam logic [PA_WIDTH-1:0] L2_BASE = 48'h0000_0000_2000;

    SDT_L1_ITEM_t                   l1_item_page;
    SDT_L1_ITEM_t                   l1_item_seg;
    SDT_L2_ITEM_t                   l2_item [2];

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
    always_ff @(posedge sdecoder_if.clk or negedge sdecoder_if.rst_n) begin
        if (!sdecoder_if.rst_n) begin
            sdecoder_if.tw_arready <= 1'b1;
            sdecoder_if.tw_rvalid  <= 1'b0;
            sdecoder_if.tw_rdata   <= '0;
        end
        else begin
            sdecoder_if.tw_arready <= 1'b1;
            sdecoder_if.tw_rvalid  <= sdecoder_if.tw_arvalid && sdecoder_if.tw_arready;
            if (sdecoder_if.tw_arvalid && sdecoder_if.tw_arready) begin
                sdecoder_if.tw_rdata <= mem_read(sdecoder_if.tw_araddr);
            end
        end
    end

    initial begin
        // 32GB 区间 0: Type=0 (全页表), L2 指向 0x2000; A 用 idx0, B 用 idx1
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
        l1_item_seg.token_id = 10'h300;
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

        uvm_config_db#(virtual sdecoder_if)::set(null, "*", "vif", sdecoder_if);
        run_test();
    end

endmodule
