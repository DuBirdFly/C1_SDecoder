`ifndef _SDPWU_SCB_SV_
`define _SDPWU_SCB_SV_

// SDPWU_TOP 的 scoreboard: 从写口重建页表, 算 Page Walk 的理想结果并比对
class SdpwuScb extends uvm_scoreboard;

    `uvm_component_utils(SdpwuScb)

    uvm_analysis_imp#(SdpwuItem, SdpwuScb) imp;

    logic [PA_WIDTH-1:0]        l1_base;        // 由 env 注入

    // 从写口 (SDPWU_MEM_WR) 重建的页表: 按 16B 对齐地址索引
    logic [PW_RDATA_WIDTH-1:0]  mem [bit [PA_WIDTH-1:0]];

    // sdmq_idx -> 本次 Page Walk 的 PA (start 握手时记录)
    logic [PA_WIDTH-1:0]        pa_of_idx [logic [SDMQ_IDX_WIDTH-1:0]];

    int start_cnt = 0;
    int mem_rd_cnt = 0;
    int finish_cnt = 0;
    int err_cnt = 0;

    function new(string name = "SdpwuScb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    function automatic logic [PW_RDATA_WIDTH-1:0] read_word(input logic [PA_WIDTH-1:0] addr);
        bit [PA_WIDTH-1:0] key;
        key = addr & ~48'hf;
        if (mem.exists(key)) begin
            return mem[key];
        end
        return '0;
    endfunction

    // 一次 Page Walk 的理想结果 (语义与 rtl/sdpwu.sv 一致)
    function automatic SDPWU_FINISH_t expect_finish(
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

        res          = '0;
        res.sdmq_idx = sdmq_idx;
        req_up       = pa[PA_BASE_LSB +: PA_UP_WIDTH];

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
            res.hit         = 1'b1;
            res.s_pfn       = l1_word[L1_S_PFN_LSB +: S_PFN_WIDTH] + {18'b0, req_up - seg_base};
            res.eid         = l1_word[L1_EID_LSB +: EID_WIDTH];
            res.token_id    = l1_word[L1_TOKEN_ID_LSB +: TOKEN_ID_WIDTH];
            res.token_value = l1_word[L1_TOKEN_VALUE_LSB +: TOKEN_VALUE_WIDTH];
        end
        else begin
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

    function void write(SdpwuItem tr);
        SDPWU_FINISH_t exp;

        case (tr.kind)
            SDPWU_START_SEEN: begin
                start_cnt++;
                pa_of_idx[tr.sdmq_idx] = tr.pa;
            end

            SDPWU_MEM_WR: begin
                mem[tr.mem_addr & ~48'hf] = tr.mem_wdata;
            end

            SDPWU_MEM_RD: begin
                mem_rd_cnt++;
            end

            SDPWU_FINISH: begin
                finish_cnt++;
                if (!pa_of_idx.exists(tr.sdmq_idx)) begin
                    err_cnt++;
                    `uvm_error(
                        "SCB_IDX",
                        $sformatf("finish 的 sdmq_idx=%0d 没有对应的 start", tr.sdmq_idx)
                    )
                end
                else begin
                    exp = expect_finish(pa_of_idx[tr.sdmq_idx], tr.sdmq_idx);
                    if (tr.finish_item !== exp) begin
                        err_cnt++;
                        `uvm_error(
                            "SCB_FINISH",
                            $sformatf("sdmq_idx=%0d: got hit=%0b eid=%h tok=%h tokv=%h pfn=%h err=%b, exp hit=%0b eid=%h tok=%h tokv=%h pfn=%h err=%b",
                                      tr.sdmq_idx,
                                      tr.finish_item.hit, tr.finish_item.eid,
                                      tr.finish_item.token_id, tr.finish_item.token_value,
                                      tr.finish_item.s_pfn, tr.finish_item.err,
                                      exp.hit, exp.eid, exp.token_id, exp.token_value,
                                      exp.s_pfn, exp.err)
                        )
                    end
                end
            end

            default: begin
                err_cnt++;
                `uvm_error("SCB_KIND", $sformatf("unexpected item kind: %s", tr.kind.name()))
            end
        endcase
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        `uvm_info(
            "SCB",
            $sformatf("start=%0d mem_rd=%0d finish=%0d err=%0d",
                      start_cnt, mem_rd_cnt, finish_cnt, err_cnt),
            UVM_LOW
        )

        if (err_cnt != 0) begin
            `uvm_error("SCB", $sformatf("%0d 条比对错误", err_cnt))
        end
        else begin
            `uvm_info("SCB", "sdpwu 比对全部通过", UVM_LOW)
        end
    endfunction

endclass

`endif // _SDPWU_SCB_SV_
