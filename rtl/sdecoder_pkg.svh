`ifndef _SDECODER_PKG_SVH_
`define _SDECODER_PKG_SVH_

package sdecoder_pkg;

    // PA[47:30] 的位宽, 1GB 对界.
    // 注: PA[47] = 1 是 IO 空间, SDecoder 只处理 Mem 空间, 请求侧 (req_pa / sdt_l1_base /
    //     inv_pa 等) 都断言该位为 0; 字段里保留该位只为维持 48 位地址口径 —— 这样 SDTLB 的
    //     Tag 是 24 位, Data 是 39 位, 合计 63 位, 不强行凑 64 位 (见设计方案 SDTLB 表项格式)
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
    } SDTLB_DATA_ITEM_t;

    localparam SDTLB_TAG_ITEM_WIDTH = $bits(SDTLB_TAG_ITEM_t);
    localparam SDTLB_DATA_ITEM_WIDTH = $bits(SDTLB_DATA_ITEM_t);

    localparam PA_WIDTH = 48;
    localparam REQ_ID_WIDTH = 8;
    localparam SLA_WIDTH = 48;

    // 响应包: id + fcode + eid + token_id + sla
    typedef struct packed {
        logic [REQ_ID_WIDTH-1:0]    id;
        logic [2:0]                 fcode;
        logic [EID_WIDTH-1:0]       eid;
        logic [TOKEN_ID_WIDTH-1:0]  token_id;
        logic [SLA_WIDTH-1:0]       sla;
    } SDT_RSP_t;

    // 整条 PA[47:0] 上的字段坐标 (端口收整条 PA, 切片时用这两个常量, 不用手写 30/35)
    localparam PA_BASE_LSB = PA_WIDTH - PA_BASE_WIDTH;      // 30: PA[47:30] 的 LSB (也是 PA[34:30] 的 LSB)
    localparam PA_HIGH_LSB = PA_BASE_LSB + PA_UP_WIDTH;     // 35: PA[47:35] 的 LSB

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

    // IOR (sdior) 的寄存器地址与字格式: 首版不做 APB 从口, 这里用寄存器序号 (而不是接口手册的
    // 字节偏移), 见设计方案 IOR 列表 / 接口手册 寄存器列表
    // 寄存器字宽 64: 地址类寄存器把整条 PA 填在低 PA_WIDTH 位 (即 PA[47:0]); W1P 触发位在字里
    // 的位置各不相同 (IA 是 bit 0, IS 是 bit 63), 其余位保留
    localparam SDIOR_ADDR_WIDTH = 2;
    localparam SDIOR_DATA_WIDTH = 64;
    localparam SDIOR_IA_W1P_BIT = 0;    // SDecoder_IA: 这一位写 1 才产生 inv_all 脉冲
    localparam SDIOR_IS_W1P_BIT = 63;   // SDecoder_IS: 这一位写 1 才产生 inv_en 脉冲
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDECODER_IA = 2'd0;   // W1P: 置无效全部条目
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDECODER_IS = 2'd1;   // W1P: 置无效指定 PA 的条目
    localparam logic [SDIOR_ADDR_WIDTH-1:0] ADDR_SDT_L1_BASE = 2'd2;   // RW: 一级表基地址

endpackage

`endif // _SDECODER_PKG_SVH_
