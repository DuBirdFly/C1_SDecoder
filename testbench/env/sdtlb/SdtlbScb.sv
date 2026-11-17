`ifndef _SDTLB_SCB_SV_
`define _SDTLB_SCB_SV_

// SDTLB 的 scoreboard: 维护 128 条目的参考模型, 逐拍比对查表响应
//   模型语义与 RTL 一致:
//     - 装填: 写到当前替换指针指向的条目, 指针每装填一次步进 (复位指向 0 号)
//     - 命中: valid && 高位 (PA[47:35]) 相等 && pa_base[4:0] <= PA[34:30] <= pa_up
//     - 置无效: inv_all 清全部; inv_sel 清被覆盖的条目 (含无效条目), 同拍与装填时置无效优先
class SdtlbScb extends uvm_scoreboard;

    `uvm_component_utils(SdtlbScb)

    uvm_analysis_imp#(SdtlbItem, SdtlbScb) imp;

    typedef struct {
        bit                             valid;
        logic [PA_BASE_WIDTH-1:0]       pa_base;
        logic [PA_UP_WIDTH-1:0]         pa_up;
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [S_PFN_WIDTH-1:0]         s_pfn;
    } entry_t;

    entry_t  mdl[SDTLB_ENTRIES];
    int unsigned victim;        // 当前替换指针 (复位指向 0 号)

    int req_cnt  = 0;
    int fill_cnt = 0;
    int inv_cnt  = 0;
    int err_cnt  = 0;

    function new(string name = "SdtlbScb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
        foreach (mdl[i]) begin
            mdl[i] = '{default: '0};
            mdl[i].valid = 1'b0;
        end
        victim = 0;
    endfunction

    // 地址是否落在条目覆盖的范围内 (不含 valid)
    function automatic bit in_range(input logic [PA_WIDTH-1:0] pa, input entry_t e);
        logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] high;
        logic [PA_UP_WIDTH-1:0]               up;
        high = pa[PA_HIGH_LSB +: (PA_BASE_WIDTH - PA_UP_WIDTH)];
        up   = pa[PA_BASE_LSB +: PA_UP_WIDTH];
        return (high == e.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]) &&
               (up >= e.pa_base[PA_UP_WIDTH-1:0]) &&
               (up <= e.pa_up);
    endfunction

    // 地址是否落在条目覆盖的范围内 (inv_sel 用): inv_sel_pa 就是 PA[47:30], 18 bit
    function automatic bit in_range_base(input logic [PA_BASE_WIDTH-1:0] base, input entry_t e);
        logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0] high;
        logic [PA_UP_WIDTH-1:0]               up;
        high = base[PA_BASE_WIDTH-1:PA_UP_WIDTH];
        up   = base[PA_UP_WIDTH-1:0];
        return (high == e.pa_base[PA_BASE_WIDTH-1:PA_UP_WIDTH]) &&
               (up >= e.pa_base[PA_UP_WIDTH-1:0]) &&
               (up <= e.pa_up);
    endfunction

    // 预测一个端口在给定请求下的响应; 多条命中时按 onehot0_mux 的行为取最后一条
    function automatic void predict(input logic [PA_WIDTH-1:0] pa,
                                    output logic hit,
                                    output SDTLB_TAG_ITEM_t tag,
                                    output SDTLB_DATA_ITEM_t data);
        hit  = 1'b0;
        tag  = '0;
        data = '0;
        for (int unsigned i = 0; i < SDTLB_ENTRIES; i++) begin
            if (mdl[i].valid && in_range(pa, mdl[i])) begin
                hit  = 1'b1;
                tag  = '{pa_base: mdl[i].pa_base, pa_up: mdl[i].pa_up, valid: 1'b1};
                data = '{eid: mdl[i].eid, token_id: mdl[i].token_id,
                         token_value: mdl[i].token_value, s_pfn: mdl[i].s_pfn};
            end
        end
    endfunction

    // 比对单个端口
    function void check_port(input string        port,
                              input bit            en,
                              input logic [PA_WIDTH-1:0] pa,
                              input logic          act_hit,
                              input SDTLB_TAG_ITEM_t  act_tag,
                              input SDTLB_DATA_ITEM_t act_data);
        logic            exp_hit;
        SDTLB_TAG_ITEM_t exp_tag;
        SDTLB_DATA_ITEM_t exp_data;

        if (!en) begin
            // 没发请求时响应必须全 0
            if ((act_hit !== 1'b0) || (act_tag !== '0) || (act_data !== '0)) begin
                err_cnt++;
                `uvm_error(
                    "SCB_IDLE",
                    $sformatf("%s 未请求但响应非 0: hit=%b tag=%h data=%h",
                              port, act_hit, act_tag, act_data)
                )
            end
            return;
        end

        predict(pa, exp_hit, exp_tag, exp_data);
        if ((act_hit !== exp_hit) || (act_tag !== exp_tag) || (act_data !== exp_data)) begin
            err_cnt++;
            `uvm_error(
                "SCB_REQ",
                $sformatf("%s pa=0x%0h: hit=%b/exp %b, tag=%h/exp %h, data=%h/exp %h",
                          port, pa, act_hit, exp_hit, act_tag, exp_tag, act_data, exp_data)
            )
        end
    endfunction

    function void write(SdtlbItem tr);
        entry_t e;

        case (tr.kind)
            SDTLB_REQ: begin
                req_cnt++;
                check_port("cam0", tr.cam0_req_en, tr.cam0_req_pa,
                           tr.cam0_hit, tr.cam0_tag, tr.cam0_data);
                check_port("cam1", tr.cam1_req_en, tr.cam1_req_pa,
                           tr.cam1_hit, tr.cam1_tag, tr.cam1_data);
            end

            SDTLB_FILL: begin
                fill_cnt++;
                e.valid       = 1'b1;
                e.pa_base     = tr.fill_pa_base;
                e.pa_up       = tr.fill_pa_up;
                e.eid         = tr.fill_eid;
                e.token_id    = tr.fill_token_id;
                e.token_value = tr.fill_token_value;
                e.s_pfn       = tr.fill_s_pfn;
                mdl[victim]   = e;
                victim        = (victim + 1) % SDTLB_ENTRIES;
            end

            SDTLB_INV: begin
                inv_cnt++;
                if (!tr.inv_en) begin
                    err_cnt++;
                    `uvm_error("SCB_INV", "置无效脉冲没有带 inv_en")
                end
                if (tr.inv_all) begin
                    foreach (mdl[i]) begin
                        mdl[i].valid = 1'b0;
                    end
                end
                if (tr.inv_sel) begin
                    foreach (mdl[i]) begin
                        // 同 RTL: inv_match 不看 valid, 无效条目也会被"清"一次
                        if (in_range_base(tr.inv_sel_pa, mdl[i])) begin
                            mdl[i].valid = 1'b0;
                        end
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
            $sformatf("req=%0d fill=%0d inv=%0d err=%0d", req_cnt, fill_cnt, inv_cnt, err_cnt),
            UVM_LOW
        )

        if (err_cnt != 0) begin
            `uvm_error("SCB", $sformatf("%0d 条比对错误", err_cnt))
        end
        else begin
            `uvm_info("SCB", "sdtlb 比对全部通过", UVM_LOW)
        end
    endfunction

endclass

`endif // _SDTLB_SCB_SV_
