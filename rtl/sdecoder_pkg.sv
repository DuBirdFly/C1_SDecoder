package sdecoder_pkg;

    typedef struct packed {
        logic [16:0]    pa_base ;   // [22: 6], 段空间基地址, 以 1 GB 对界
        logic [ 4:0]    pa_up   ;   // [ 5: 1], 段空间上界(含), 以 1 GB 对界
        logic           valid   ;   // [ 0: 0], 段空间有效位
    } SDTLB_TAG_ITEM_t;

    typedef struct packed {
        logic [10:0]    eid     ;   // [39:29], Entity 标识
        logic [ 9:0]    token_id ;  // [28:19], 逻辑池标识
        logic [17:0]    s_pfn   ;   // [18: 1], SLA 基址, 以 1 GB 对界
        logic           grn     ;   // [ 0: 0], 粒度位, 1 表示段式, 0 表示 1GB 页式
    } SDTLB_DATA_ITEM_t;

    localparam SDTLB_ENTRIES = 128;
    localparam PA_WIDTH = 48;

endpackage