`ifndef _SDECODER_PKG_SVH_
`define _SDECODER_PKG_SVH_

package sdecoder_pkg;

    // 1GB 即 2^30 Bytes, 1GB 的页内地址为 PA[29:0]

    typedef struct packed {
        // physical address base, 段空间基地址, 以 1 GB 对界
        // 即 PA[46:30], 不包含 PA[47] 这个 IO/MEM 空间区分位
        logic [16:0]    pa_base     ;
        // physical address up, 段空间上界(含), 即 PA[34:30] 的上界页号, 不是相对偏移.
        // 页式条目满足 pa_up = pa_base[34:30] (区间退化为一个 1GB 页);
        // 装填时要求 pa_up >= pa_base[34:30] (区间非空), 由 sdtlb 的断言守住
        logic [ 4:0]    pa_up       ;
        // valid bit, 有效位, 1 表示条目有效, 0 表示条目无效
        logic           valid       ;
    } SDTLB_TAG_ITEM_t;

    typedef struct packed {
        // Entity identifier, Entity 标识
        logic [10:0]    eid         ;
        // Token identifier, 逻辑池标识
        logic [ 9:0]    token_id    ;
        // SWLink page frame number, SLA 基址, 以 1 GB 对界
        logic [17:0]    s_pfn       ;
        // granularity bit, 粒度位, 1 表示段式, 0 表示 1GB 页式
        logic           grn         ;
    } SDTLB_DATA_ITEM_t;

    localparam PA_WIDTH = 48;
    localparam SLA_WIDTH = 48;
    localparam SDTLB_ENTRIES = 128;
    localparam SDTLB_ENTRIES_IDX_WIDTH = $clog2(SDTLB_ENTRIES);

endpackage

`endif // _SDECODER_PKG_SVH_
