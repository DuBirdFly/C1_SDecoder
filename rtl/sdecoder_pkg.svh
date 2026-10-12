`ifndef _SDECODER_PKG_SVH_
`define _SDECODER_PKG_SVH_

package sdecoder_pkg;

    localparam PA_BASE_WIDTH = 17; // PA[46:30] 的位宽, 1GB 对界
    localparam PA_UP_WIDTH   = 5;  // PA[34:30]

    typedef struct packed {
        logic [PA_BASE_WIDTH-1:0]   pa_base;
        logic [PA_UP_WIDTH-1:0]     pa_up;
        logic                       valid;
    } SDTLB_TAG_ITEM_t;

    localparam EID_WIDTH = 11;
    localparam TOKEN_ID_WIDTH = 10;
    localparam S_PFN_WIDTH = 18;

    typedef struct packed {
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [S_PFN_WIDTH-1:0]     s_pfn;
        logic                       grn;
    } SDTLB_DATA_ITEM_t;

    localparam SDTLB_TAG_ITEM_WIDTH = $bits(SDTLB_TAG_ITEM_t);
    localparam SDTLB_DATA_ITEM_WIDTH = $bits(SDTLB_DATA_ITEM_t);

    localparam PA_WIDTH = 48;
    localparam SLA_WIDTH = 48;

    // PA 分段 (见设计方案 地址划分)
    localparam PA_OFFSET_WIDTH = 30;                        // PA[29:0] 页内偏移, 原样进 SLA
    localparam PA_L1_IDX_WIDTH = 12;                        // PA[46:35] 一级表索引
    localparam PA_L1_IDX_LSB   = PA_OFFSET_WIDTH + PA_UP_WIDTH;         // 35
    localparam PA_L1_IDX_MSB   = PA_OFFSET_WIDTH + PA_BASE_WIDTH - 1;   // 46
    localparam PA_UP_LSB       = PA_OFFSET_WIDTH;                       // 30
    localparam PA_UP_MSB       = PA_OFFSET_WIDTH + PA_UP_WIDTH - 1;     // 34

    localparam REQ_ID_WIDTH = 8;

    // 未命中队列 (同时按请求顺序排队)
    localparam SDEC_REQ_FIFO_DEPTH = 4;

    // 异常码 (rsp_fcode 与 SDEC_ERRINFO.FCODE 共用, 见接口手册 异常码)
    localparam FCODE_WIDTH = 3;
    localparam [FCODE_WIDTH-1:0] FCODE_NONE         = 3'b000;   // 无异常
    localparam [FCODE_WIDTH-1:0] FCODE_ADDR_ILLEGAL = 3'b001;   // 地址非法
    localparam [FCODE_WIDTH-1:0] FCODE_UNCORRECT    = 3'b010;   // 不可纠错 (报 MCHK)
    localparam [FCODE_WIDTH-1:0] FCODE_WALK_CTRL    = 3'b011;   // Page Walk 控制错 (报 MCHK)

    // SDT_L1 条目 (16B), 位域见设计方案 一级表条目格式
    typedef struct packed {
        logic [31:0]                rsvd;
        logic [44:0]                l2_base;        // L2_BASE[47:3]
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [S_PFN_WIDTH-1:0]     s_pfn;
        logic [4:0]                 seg_len;
        logic [4:0]                 seg_base;
        logic                       type_bit;       // 1: 该 32GB 区间有段式映射
        logic                       valid;
    } SDT_L1_ITEM_t;

    // SDT_L2 条目 (8B), 位域见设计方案 二级表条目格式
    typedef struct packed {
        logic [23:0]                rsvd;
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [S_PFN_WIDTH-1:0]     s_pfn;
        logic                       valid;
    } SDT_L2_ITEM_t;

    // 未命中队列条目: 地址 48 + rw 1 + req_id 8 = 57 bit
    typedef struct packed {
        logic [PA_WIDTH-1:0]        pa;
        logic                       rw;
        logic [REQ_ID_WIDTH-1:0]    req_id;
    } SDEC_REQ_t;

    // 一条代换响应 (SMD 或异常)
    typedef struct packed {
        logic [REQ_ID_WIDTH-1:0]    req_id;
        logic                       fault;
        logic [FCODE_WIDTH-1:0]     fcode;
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [SLA_WIDTH-1:0]       sla;
    } SDEC_RSP_t;

    localparam SDEC_REQ_WIDTH = $bits(SDEC_REQ_t);
    localparam SDEC_RSP_WIDTH = $bits(SDEC_RSP_t);

    localparam SDTLB_ENTRIES = 128;
    // localparam SDTLB_ENTRIES_IDX_WIDTH = $clog2(SDTLB_ENTRIES);

endpackage

`endif // _SDECODER_PKG_SVH_
