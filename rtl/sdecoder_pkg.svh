`ifndef _SDECODER_PKG_SVH_
`define _SDECODER_PKG_SVH_

package sdecoder_pkg;

    localparam PA_WIDTH      = 48; // PA[47:0]
    localparam PA_BASE_WIDTH = 18; // PA[47:30]
    localparam PA_UP_WIDTH   = 5;  // PA[34:30]
    localparam L2_BASE_WIDTH = 45; // SDecoder_PTBR_L2 [47:3]

    localparam PA_BASE_LSB = PA_WIDTH - PA_BASE_WIDTH;      // 30: PA[47:30] 的 LSB (也是 PA[34:30] 的 LSB)
    localparam PA_HIGH_LSB = PA_BASE_LSB + PA_UP_WIDTH;     // 35: PA[47:35] 的 LSB

    // 条目 Tag 段的内容; 有效位单独由 sdtlb_tag_item 的 tag_valid 给出
    typedef struct packed {
        logic [PA_BASE_WIDTH-1:0]   pa_base;
        logic [PA_UP_WIDTH-1:0]     pa_up;
    } SDTLB_TAG_ITEM_t;

    localparam EID_WIDTH = 11;
    localparam TOKEN_ID_WIDTH = 11;
    localparam TOKEN_VALUE_WIDTH = 10;
    localparam S_PFN_WIDTH = 23;    // S_PFN[52:30]

    typedef struct packed {
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [S_PFN_WIDTH-1:0]         s_pfn;
    } SDTLB_DATA_ITEM_t;

    localparam SDTLB_TAG_ITEM_WIDTH = $bits(SDTLB_TAG_ITEM_t);
    localparam SDTLB_DATA_ITEM_WIDTH = $bits(SDTLB_DATA_ITEM_t);

    localparam REQ_ID_WIDTH = 8;
    localparam SLA_WIDTH = 53;
    localparam CAM_RSP_ERR_WIDTH = 1;

    // 响应包: id + eid + token_id + token_value + sla + err (见设计方案 "响应接口 (CAM)")
    typedef struct packed {
        logic [REQ_ID_WIDTH-1:0]        id;
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [SLA_WIDTH-1:0]           sla;
        logic [CAM_RSP_ERR_WIDTH-1:0]   err;
    } SDT_RSP_t;

    // SDT_L1 条目 (16B), 位域见设计方案 一级表条目格式
    typedef struct packed {
        logic [15:0]                    rsvd;
        logic [L2_BASE_WIDTH-1:0]       l2_base;        // L2_BASE[47:3]
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [S_PFN_WIDTH-1:0]         s_pfn;
        logic [4:0]                     seg_len;
        logic [4:0]                     seg_base;
        // 0: 该 32GB 区间均为页表
        // 1: 该 32GB 区间有且仅有 1 个段表 (+N个页表)
        logic                           type_bit;
        logic                           valid;
    } SDT_L1_ITEM_t;

    // SDT_L2 条目 (8B), 位域见设计方案 二级表条目格式
    typedef struct packed {
        logic [7:0]                     rsvd;
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [S_PFN_WIDTH-1:0]         s_pfn;
        logic                           valid;
    } SDT_L2_ITEM_t;

    localparam SDTLB_ENTRIES = 128;
    // localparam SDTLB_ENTRIES_IDX_WIDTH = $clog2(SDTLB_ENTRIES);

    // IOR (sdior) 的寄存器地址与字格式: 首版不做 APB 从口, 这里用寄存器序号 (而不是接口手册的
    // 字节偏移), 见设计方案 IOR 列表 / 接口手册 寄存器列表
    // 寄存器字宽 64: 各寄存器的字段位置见设计方案 "可配置的寄存器" 一节
    // 地址按设计方案的序号排: 0 IA, 1 IS, 2 PTBR; 其余寄存器暂未实现 (ES / Perf / 计数器)
    localparam SDIOR_ADDR_WIDTH = 4;
    localparam SDIOR_DATA_WIDTH = 64;
    localparam SDIOR_IS_PA_LSB   = 0;   // SDecoder_IS.INV_SEL_PA[47:30] 在寄存器字里的 lsb
    localparam SDIOR_PTBR_LSB    = 4;   // SDecoder_PTBR.SDT_L1_BASE[47:4] 在寄存器字里的 lsb
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDECODER_IA = 4'd0;   // 写即触发: 置无效全部条目
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDECODER_IS = 4'd1;   // 写即触发: 置无效 INV_SEL_PA 的条目
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDECODER_PTBR = 4'd2;   // RW: 一级表基地址


    localparam SDMQ_DEPTH = 16;
    localparam SDMQ_IDX_WIDTH = $clog2(SDMQ_DEPTH);     // SDMQ 条目号

    // ------------------------------------------------------------------
    // SDPWU (Page Walk Unit)
    // ------------------------------------------------------------------
    localparam SDPWU_NUM = 2;                           // 并行 Page Walk 的个数
    localparam PW_ID_WIDTH = (SDPWU_NUM > 1) ? $clog2(SDPWU_NUM) : 1;   // 访存请求/响应的来源标记
    localparam PW_RDATA_WIDTH = 128;                    // 一次读回最多 16B (一级表条目)
    localparam PW_RDATA_ERR_WIDTH = 3;                  // [2] ctrl [1] ecc [0] oob
    localparam SDMQ_RSP_ERR_WIDTH = 5;                  // [4] ctrl [3] ecc [2] oob [1] malformed [0] page_fault

    // 错误位 (访存接口 / SDMQ 响应 / Page Walk sideband 共用同一套含义)
    localparam PW_RDATA_ERR_CTRL_BIT  = 2;
    localparam PW_RDATA_ERR_ECC_BIT   = 1;
    localparam PW_RDATA_ERR_OOB_BIT   = 0;

    localparam SDMQ_RSP_ERR_CTRL_BIT  = 4;
    localparam SDMQ_RSP_ERR_ECC_BIT   = 3;
    localparam SDMQ_RSP_ERR_OOB_BIT   = 2;
    localparam SDMQ_RSP_ERR_MALFORMED_BIT = 1;
    localparam SDMQ_RSP_ERR_PAGE_FAULT_BIT = 0;

    // 一级表条目 (128 bit) 的字段位置, 见设计方案 "一级表条目" 表
    localparam L1_L2_BASE_LSB     = 67;     // [111:67] PTE.SDT_L2_BASE[47:3]
    localparam L1_EID_LSB         = 56;     // [66:56]  EID[10:0]
    localparam L1_TOKEN_ID_LSB    = 45;     // [55:45]  TokenID[10:0]
    localparam L1_TOKEN_VALUE_LSB = 35;     // [44:35]  TokenValue[9:0]
    localparam L1_S_PFN_LSB       = 12;     // [34:12]  S_PFN[52:30]
    localparam L1_SEG_LEN_LSB     = 7;      // [11:7]   SEG_LEN[34:30]
    localparam L1_SEG_BASE_LSB    = 2;      // [6:2]    SEG_BASE[34:30]
    localparam L1_TYPE_BIT        = 1;
    localparam L1_VALID_BIT       = 0;

    // 二级表条目 (64 bit) 的字段位置, 见设计方案 "二级表条目" 表
    localparam L2_EID_LSB         = 45;     // [55:45]
    localparam L2_TOKEN_ID_LSB    = 34;     // [44:34]
    localparam L2_TOKEN_VALUE_LSB = 24;     // [33:24]
    localparam L2_S_PFN_LSB       = 1;      // [23:1]
    localparam L2_VALID_BIT       = 0;

    // SDMQ -> SDPWU_CTRL 的 Page Walk 请求
    typedef struct packed {
        logic [PA_WIDTH-1:0]        pa;
        logic [SDMQ_IDX_WIDTH-1:0]  sdmq_idx;
    } SDPWU_START_t;

    // SDPWU -> SDMQ 的 Page Walk 结果 (sideband)
    typedef struct packed {
        logic [SDMQ_IDX_WIDTH-1:0]      sdmq_idx;
        logic                           hit;
        logic [EID_WIDTH-1:0]           eid;
        logic [TOKEN_ID_WIDTH-1:0]      token_id;
        logic [TOKEN_VALUE_WIDTH-1:0]   token_value;
        logic [S_PFN_WIDTH-1:0]         s_pfn;
        logic [SDMQ_RSP_ERR_WIDTH-1:0]  err;
    } SDPWU_FINISH_t;

    typedef struct packed {
        logic                       valid;
        logic                       flushed;
        logic                       page_walking;
        logic                       responsed;
        logic [REQ_ID_WIDTH-1:0]    id;
        logic [PA_WIDTH-1:0]        pa;
    } SDMQ_ITEM_t;


endpackage

`endif // _SDECODER_PKG_SVH_
