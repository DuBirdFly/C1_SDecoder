package sdecoder_pkg;

    typedef struct packed {
        // [22: 6], physical address base, 段空间基地址, 以 1 GB 对界
        logic [16:0]    pa_base     ;
        // [ 5: 1], physical address up, 段空间上界(含), 以 1 GB 对界
        logic [ 4:0]    pa_up       ;
        // [ 0: 0], valid bit, 有效位, 1 表示条目有效, 0 表示条目无效
        logic           valid       ;
    } SDTLB_TAG_ITEM_t;

    typedef struct packed {
        // [39:29], Entity identifier, Entity 标识
        logic [10:0]    eid         ;
        // [28:19], Token identifier, 逻辑池标识
        logic [ 9:0]    token_id    ;
        // [18: 1], SWLink page frame number, SLA 基址, 以 1 GB 对界
        logic [17:0]    s_pfn       ;
        // [ 0: 0], granularity bit, 粒度位, 1 表示段式, 0 表示 1GB 页式
        logic           grn         ;
    } SDTLB_DATA_ITEM_t;

    localparam SDTLB_ENTRIES = 128;
    localparam PA_WIDTH = 48;
    // SDTLB 条目下标位宽, 由条目数推出, 供 sdtlb_tag / sdtlb_data 与顶层共用
    localparam IDX_WIDTH = $clog2(SDTLB_ENTRIES);

endpackage