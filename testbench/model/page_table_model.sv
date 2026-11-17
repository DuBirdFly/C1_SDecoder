`ifndef _PAGE_TABLE_MODEL_SV_
`define _PAGE_TABLE_MODEL_SV_

// 一页表的参考模型 (纯 SV class, 不依赖 UVM)
//   内存按 16B 对齐的地址索引 (一次读最多返回 16B), 未写过的地址读回 0
class page_table_model;

    protected logic [127:0] mem[bit [PA_WIDTH-1:0]];

    function new();
        mem.delete();
    endfunction

    // ---- 内存 ----
    function void clear();
        mem.delete();
    endfunction

    function void write_word(input logic [PA_WIDTH-1:0] addr, input logic [127:0] data);
        mem[addr & ~48'hf] = data;
    endfunction

    function logic [127:0] read_word(input logic [PA_WIDTH-1:0] addr);
        if (mem.exists(addr & ~48'hf)) begin
            return mem[addr & ~48'hf];
        end
        return '0;
    endfunction

    // ---- 一级表 ----
    // 一级表条目地址 = {L1_BASE[47:4], 4'h0} + idx * 16
    function void write_l1(
        input logic [PA_WIDTH-1:0]  l1_base,
        input logic [11:0]          idx,
        input SDT_L1_ITEM_t         item
    );
        write_word({l1_base[PA_WIDTH-1:4], 4'h0} + (PA_WIDTH'(idx) << 4), 128'(item));
    endfunction

    // ---- 二级表 ----
    // 二级表条目地址 = {L2_BASE[47:3], 3'h0} + idx * 8
    function void write_l2(
        input logic [PA_WIDTH-1:0]  l2_base,
        input logic [4:0]           idx,
        input SDT_L2_ITEM_t         item
    );
        write_word({l2_base[PA_WIDTH-1:3], 3'h0} + (PA_WIDTH'(idx) << 3), 128'(item));
    endfunction

    // ---- 一次 Page Walk 的理想结果 (与 rtl/sdpwu.sv 的语义一致) ----
    function SDPWU_FINISH_t expect_finish(
        input logic [PA_WIDTH-1:0]      l1_base,
        input logic [PA_WIDTH-1:0]      pa,
        input logic [SDMQ_IDX_WIDTH-1:0] sdmq_idx
    );
        SDPWU_FINISH_t      res;
        logic [PA_WIDTH:0]  l1_addr;
        logic [PA_WIDTH:0]  l2_addr;
        logic [127:0]       l1_word;
        logic [127:0]       l2_word;
        logic [PA_UP_WIDTH-1:0] req_up;
        logic [PA_UP_WIDTH-1:0] seg_base;
        logic [PA_UP_WIDTH-1:0] seg_len;
        logic [PA_UP_WIDTH:0]   seg_end;
        logic [L2_BASE_WIDTH-1:0] l2_base;

        res       = '0;
        res.sdmq_idx = sdmq_idx;
        req_up    = pa[PA_BASE_LSB +: PA_UP_WIDTH];

        // 一级表读取
        l1_addr = {1'b0, {l1_base[PA_WIDTH-1:SDIOR_PTBR_LSB], {SDIOR_PTBR_LSB{1'b0}}}} +
                  {{(PA_WIDTH + 1 - 16){1'b0}}, pa[46:PA_HIGH_LSB], 4'h0};
        l1_word = read_word(l1_addr[PA_WIDTH-1:0]);

        seg_base = l1_word[L1_SEG_BASE_LSB +: PA_UP_WIDTH];
        seg_len  = l1_word[L1_SEG_LEN_LSB  +: PA_UP_WIDTH];
        seg_end  = {1'b0, seg_base} + {1'b0, seg_len};

        if (l1_addr[PA_WIDTH]) begin
            res.err[SDMQ_RSP_ERR_OOB_BIT] = 1'b1;
        end
        else if (seg_end > 6'd31) begin
            res.err[SDMQ_RSP_ERR_MALFORMED_BIT] = 1'b1;
        end
        else if (!l1_word[L1_VALID_BIT]) begin
            res.err[SDMQ_RSP_ERR_PAGE_FAULT_BIT] = 1'b1;
        end
        else if (l1_word[L1_TYPE_BIT] && (req_up >= seg_base) && (req_up <= seg_base + seg_len)) begin
            // 段式命中
            res.hit         = 1'b1;
            res.s_pfn       = l1_word[L1_S_PFN_LSB +: S_PFN_WIDTH] +
                              {18'b0, req_up - seg_base};
            res.eid         = l1_word[L1_EID_LSB +: EID_WIDTH];
            res.token_id    = l1_word[L1_TOKEN_ID_LSB +: TOKEN_ID_WIDTH];
            res.token_value = l1_word[L1_TOKEN_VALUE_LSB +: TOKEN_VALUE_WIDTH];
        end
        else begin
            // 二级表
            l2_base = l1_word[L1_L2_BASE_LSB +: L2_BASE_WIDTH];
            l2_addr = {1'b0, l2_base, 3'h0} +
                      {{(PA_WIDTH + 1 - PA_UP_WIDTH - 3){1'b0}}, req_up, 3'h0};
            l2_word = read_word(l2_addr[PA_WIDTH-1:0]);
            if (l2_addr[PA_WIDTH]) begin
                res.err[SDMQ_RSP_ERR_OOB_BIT] = 1'b1;
            end
            else if (!l2_word[L2_VALID_BIT]) begin
                res.err[SDMQ_RSP_ERR_PAGE_FAULT_BIT] = 1'b1;
            end
            else begin
                res.hit         = 1'b1;
                res.s_pfn       = l2_word[L2_S_PFN_LSB +: S_PFN_WIDTH];
                res.eid         = l2_word[L2_EID_LSB +: EID_WIDTH];
                res.token_id    = l2_word[L2_TOKEN_ID_LSB +: TOKEN_ID_WIDTH];
                res.token_value = l2_word[L2_TOKEN_VALUE_LSB +: TOKEN_VALUE_WIDTH];
            end
        end

        return res;
    endfunction

endclass

`endif // _PAGE_TABLE_MODEL_SV_
