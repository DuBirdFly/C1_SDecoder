`ifndef _SDECODER_PKG_SVH_
`define _SDECODER_PKG_SVH_

package sdecoder_pkg;

    // PA[47:30] 的位宽, 1GB 对界.
    // 注: PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间, 请求侧 (req_pa / sdt_l1_base /
    //     inv_pa 等) 都断言该位为 0; 字段里保留该位只为维持 48 位地址口径 —— 这样 SDTLB 的
    //     Tag 是 24 位, 与 40 位 Data 正好凑成 64 位条目 (见设计方案 表5 的注)
    localparam PA_BASE_WIDTH = 18;
    localparam PA_UP_WIDTH   = 5;  // PA[34:30]
    localparam L2_BASE_WIDTH = 45; // L2_BASE[47:3]

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
        logic [L2_BASE_WIDTH-1:0]   l2_base;        // L2_BASE[47:3]
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [S_PFN_WIDTH-1:0]     s_pfn;
        logic [4:0]                 seg_len;
        logic [4:0]                 seg_base;
        // 0: 该 32GB 区间均为页表
        // 1: 该 32GB 区间有且仅有 1 个段表 (+N个页表)
        logic                       type_bit;
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
