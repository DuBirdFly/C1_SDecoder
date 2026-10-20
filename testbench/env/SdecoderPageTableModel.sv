`ifndef _SDECODER_PAGE_TABLE_MODEL_SV_
`define _SDECODER_PAGE_TABLE_MODEL_SV_

// SdecoderPageTableModel: 两级 SDT 本地表模型
//   响应 SDPTW 的 tw_* 读请求:
//     - AR 的 ready 在 arvalid 后随机延迟 LATENCY_MIN~LATENCY_MAX 拍拉高, 保持 1 拍
//     - R 的 valid 在 AR 握手后再随机延迟 LATENCY_MIN~LATENCY_MAX 拍拉高
//     - rvalid 一直保持到 rready 为 1 (AXI 式)
//     - L1 读整 16B 条目
//     - L2 读 8B 条目, 按 araddr[3] 放到 16B 总线的对应 lane
//   表内容固定为本 smoke 用例的 A/B 页 + 32GB 区间 1 的段.
class SdecoderPageTableModel extends uvm_component;

    `uvm_component_utils(SdecoderPageTableModel)

    virtual sdecoder_if vif;

    int unsigned ar_count;

    localparam logic [PA_WIDTH-1:0] L1_BASE = 48'h0000_0000_1000;
    localparam logic [PA_WIDTH-1:0] L2_BASE = 48'h0000_0000_2000;
    localparam int unsigned         LATENCY_MIN = 15;
    localparam int unsigned         LATENCY_MAX = 50;

    SDT_L1_ITEM_t l1_item_page;
    SDT_L1_ITEM_t l1_item_seg;
    SDT_L2_ITEM_t l2_item[2];

    function new(string name = "SdecoderPageTableModel", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ar_count = 0;
        if (!uvm_config_db#(virtual sdecoder_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "SdecoderPageTableModel: no virtual sdecoder_if")
        end
        init_table();
    endfunction

    function void init_table();
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
    endfunction

    // 本地表读: L1 16B 直接返回, L2 8B 按 araddr[3] 放到 16B 总线的对应 lane
    function logic [127:0] mem_read(input logic [PA_WIDTH-1:0] addr);
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

    task run_phase(uvm_phase phase);
        logic [PA_WIDTH-1:0] addr;
        int unsigned         ar_latency;
        int unsigned         r_latency;

        vif.tw_arready <= 1'b0;
        vif.tw_rvalid  <= 1'b0;
        vif.tw_rdata   <= '0;

        wait (vif.rst_n === 1'b1);

        forever begin
            vif.tw_arready <= 1'b0;
            vif.tw_rvalid  <= 1'b0;

            @(vif.mon);
            if (vif.mon.tw_arvalid) begin
                addr       = vif.mon.tw_araddr;
                ar_latency = $urandom_range(LATENCY_MAX, LATENCY_MIN);

                // AR ready: arvalid 后随机等若干拍, 只拉高 1 拍
                repeat (ar_latency) @(vif.mon);
                vif.tw_arready <= 1'b1;
                @(vif.mon);
                if (vif.mon.tw_arvalid && vif.mon.tw_arready) begin
                    ar_count++;
                end
                vif.tw_arready <= 1'b0;

                // R valid: AR 握手后再随机等若干拍
                r_latency = $urandom_range(LATENCY_MAX, LATENCY_MIN);
                repeat (r_latency) @(vif.mon);
                vif.tw_rdata  <= mem_read(addr);
                vif.tw_rvalid <= 1'b1;

                // 保持 R 直到被 rready 取走
                do @(vif.mon); while (!(vif.mon.tw_rvalid && vif.mon.tw_rready));
                vif.tw_rvalid <= 1'b0;
            end
        end
    endtask

endclass

`endif // _SDECODER_PAGE_TABLE_MODEL_SV_
