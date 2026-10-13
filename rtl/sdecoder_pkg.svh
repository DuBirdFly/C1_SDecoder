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

    localparam SDTLB_ENTRIES = 128;
    // localparam SDTLB_ENTRIES_IDX_WIDTH = $clog2(SDTLB_ENTRIES);

endpackage

`endif // _SDECODER_PKG_SVH_
