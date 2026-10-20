`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// slmd_calc: SLMD 计算
//   把 SDTLB 命中结果或 SDPTW 的一级/二级条目组装成响应:
//     - 命中: 用 SDTLB tag/data + 请求 PA 算 SLA
//     - 未命中: 先判段, 再判页; 段取一级条目, 页取二级条目
//     - 产生 rsp_fcode, 成功时给出 SDTLB 装填字段
//   本模块只做组合计算, 不处理响应 FIFO 仲裁; 回填 valid 由顶层按 push_miss 门控.
module slmd_calc
import sdecoder_pkg::*;
(
    // 命中输入 (SDTLB hit)
    input  logic                        hit_valid,
    input  logic [PA_WIDTH-1:0]         hit_pa,
    input  logic [REQ_ID_WIDTH-1:0]     hit_id,
    input  SDTLB_TAG_ITEM_t             hit_tag,
    input  SDTLB_DATA_ITEM_t            hit_data,
    output SDT_RSP_t                    hit_rsp,

    // 未命中输入 (SDPTW 原始条目)
    input  logic                        miss_valid,
    input  logic [PA_WIDTH-1:0]         miss_pa,
    input  logic [REQ_ID_WIDTH-1:0]     miss_id,
    input  SDT_L1_ITEM_t                l1_item,
    input  SDT_L2_ITEM_t                l2_item,
    input  logic                        l2_read,
    output SDT_RSP_t                    miss_rsp,

    // 未命中结果: 回填 SDTLB 的字段; 只有 miss_ok 为 1 时才有效
    output logic                        miss_ok,
    output logic [PA_BASE_WIDTH-1:0]    miss_fill_pa_base,
    output logic [PA_UP_WIDTH-1:0]      miss_fill_pa_up,
    output logic [EID_WIDTH-1:0]        miss_fill_eid,
    output logic [TOKEN_ID_WIDTH-1:0]   miss_fill_token_id,
    output logic [S_PFN_WIDTH-1:0]      miss_fill_s_pfn
);

    // 命中: 段/页在 SDTLB 里统一表示为 PA_Base + PA_Up, 偏移为 PA[34:30] - pa_base[4:0]
    logic [PA_UP_WIDTH-1:0]     hit_offset;
    logic [18:0]                hit_sla_sum;
    logic                       hit_sla_err;
    logic [SLA_WIDTH-1:0]       hit_sla;
    logic [2:0]                 hit_fcode;

    assign hit_offset  = hit_pa[PA_BASE_LSB +: PA_UP_WIDTH] - hit_tag.pa_base[PA_UP_WIDTH-1:0];
    assign hit_sla_sum = {1'b0, hit_data.s_pfn} + {14'b0, hit_offset};
    assign hit_sla_err = hit_sla_sum[18] || hit_sla_sum[17];
    assign hit_sla     = {hit_sla_sum[17:0], hit_pa[PA_BASE_LSB-1:0]};
    assign hit_fcode   = (hit_valid && !hit_sla_err) ? 3'b000 : 3'b001;

    always_comb begin
        hit_rsp = '0;
        hit_rsp.id    = hit_id;
        hit_rsp.fcode = hit_fcode;
        if (hit_valid && !hit_sla_err) begin
            hit_rsp.eid      = hit_data.eid;
            hit_rsp.token_id = hit_data.token_id;
            hit_rsp.sla      = hit_sla;
        end
    end

    // 未命中: 先判段, 再判页
    logic [PA_UP_WIDTH-1:0]     pa_up;
    logic [5:0]                 seg_up;
    logic                       seg_hit;
    logic                       seg_len_bad;
    logic [PA_UP_WIDTH-1:0]     seg_offset;
    logic [18:0]                seg_sla_sum;
    logic                       seg_sla_err;
    logic [SLA_WIDTH-1:0]       seg_sla;
    logic [SLA_WIDTH-1:0]       page_sla;
    logic                       page_sla_err;
    logic                       miss_seg;
    logic [2:0]                 miss_fcode;
    logic [EID_WIDTH-1:0]       miss_eid;
    logic [TOKEN_ID_WIDTH-1:0]  miss_token_id;
    logic [S_PFN_WIDTH-1:0]     miss_s_pfn;
    logic [SLA_WIDTH-1:0]       miss_sla;

    assign seg_up      = {1'b0, l1_item.seg_base} + {1'b0, l1_item.seg_len};
    assign pa_up       = miss_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    assign seg_hit     = l1_item.valid && l1_item.type_bit &&
                         (pa_up >= l1_item.seg_base) &&
                         ({1'b0, pa_up} <= seg_up);
    assign seg_len_bad = l1_item.valid && l1_item.type_bit && (seg_up > 6'd31);

    assign seg_offset  = pa_up - l1_item.seg_base;
    assign seg_sla_sum = {1'b0, l1_item.s_pfn} + {14'b0, seg_offset};
    assign seg_sla_err = seg_sla_sum[18] || seg_sla_sum[17];
    assign seg_sla     = {seg_sla_sum[17:0], miss_pa[PA_BASE_LSB-1:0]};

    assign page_sla     = {l2_item.s_pfn, miss_pa[PA_BASE_LSB-1:0]};
    assign page_sla_err = l2_item.s_pfn[17];

    assign miss_ok = miss_valid && l1_item.valid && !seg_len_bad &&
                     ((l1_item.type_bit && seg_hit && !seg_sla_err) ||
                      (!seg_hit && l2_read && l2_item.valid && !page_sla_err));

    assign miss_seg      = miss_ok && l1_item.type_bit && seg_hit;
    assign miss_fcode    = miss_ok ? 3'b000 : 3'b001;
    assign miss_eid      = miss_seg ? l1_item.eid      : l2_item.eid;
    assign miss_token_id = miss_seg ? l1_item.token_id : l2_item.token_id;
    assign miss_s_pfn    = miss_seg ? l1_item.s_pfn    : l2_item.s_pfn;
    assign miss_sla      = miss_seg ? seg_sla          : page_sla;

    assign miss_fill_pa_base = miss_seg ?
        {miss_pa[PA_WIDTH-1:PA_HIGH_LSB], l1_item.seg_base} :
        miss_pa[PA_WIDTH-1:PA_BASE_LSB];
    assign miss_fill_pa_up = miss_seg ?
        seg_up[PA_UP_WIDTH-1:0] :
        miss_pa[PA_BASE_LSB +: PA_UP_WIDTH];
    assign miss_fill_eid      = miss_eid;
    assign miss_fill_token_id = miss_token_id;
    assign miss_fill_s_pfn    = miss_s_pfn;

    always_comb begin
        miss_rsp = '0;
        miss_rsp.id    = miss_id;
        miss_rsp.fcode = miss_fcode;
        if (miss_ok) begin
            miss_rsp.eid      = miss_eid;
            miss_rsp.token_id = miss_token_id;
            miss_rsp.sla      = miss_sla;
        end
    end

endmodule

`default_nettype wire
