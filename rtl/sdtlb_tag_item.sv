// =============================================================================
// sdtlb_tag_item: SDTLB 的一个 Tag 条目, 即全相联 CAM 中的一级比较单元
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §命中判断):
//   把一次代换请求的请求地址 Req_PA 与"本条目"描述的段空间做比较, 给出本条目
//   是否命中. 同时满足以下三条才算命中:
//     1. 本条目有效位 = 1;
//     2. Req_PA[46:35] 与 PA_Base[46:35] 相等;
//     3. Req_PA[34:30] 落在闭区间 [PA_Base[34:30], PA_Up[34:30]] 内.
//
//   页式条目满足 PA_Base[34:30] = PA_Up[34:30], 区间退化为一个 1GB 页, 因此
//   段式与页式共用本模块, 不需要两套比较逻辑.
//
// 层次与约定:
//   - sdtlb_tag 用 generate 例化 SDTLB_ENTRIES 份本模块, 再把各条目的 req_hit 做
//     优先级编码 (正常配置下同一次请求最多命中一个条目), 得到命中条目下标.
//   - 条目内容存在本模块的 tag_item 寄存器里. 装入由端口 valid 作写使能: valid
//     有效时把 pa_base / pa_up / valid 一起写进 tag_item, 因此装填当拍比较用的
//     仍是旧值, 新值下一拍生效.
//   - 无效化按设计方案 §无效化 实现: inv_all 清全部条目的有效位; inv_en + inv_pa
//     清掉覆盖该地址的条目 (段高位域匹配 且 地址落在闭区间内). 两个入口都优先于
//     装入, 即同一拍既刷新又装填时按刷新处理, 不会把刚清掉的条目写回去; 对本来就
//     无效的条目, 按地址清除是空操作, 但同样会挡住同拍的装入.
//   - 置无效只清有效位, 地址字段保留 (无效条目的地址字段是 don't care).
//   - 复位后 tag_item 清 0, 即所有条目上电为无效.
// =============================================================================
`default_nettype none

module sdtlb_tag_item
import sdecoder_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,

    // 代换请求
    input  logic                    req_vld,
    input  logic [PA_WIDTH-1:0]     req_pa,
    output logic                    req_hit,

    // 本条目装入端口
    input  logic [16:0]             wr_pa_base, // 段空间基地址, 以 1 GB 对界
    input  logic [ 4:0]             wr_pa_up,   // 段空间上界(含), 以 1 GB 对界
    input  logic                    wr_pa_vld,  // 写使能, 同时作为写入的有效位

    // 无效化 (刷新) 端口, 优先于装入
    input  logic                    inv_all,    // 置无效全部 TLB ENTRIES
    input  logic                    inv_en,     // 按地址置无效使能
    input  logic [PA_WIDTH-1:0]     inv_pa      // 按地址置无效的地址

);

    // 本条目寄存器: 段空间基址 / 上界 / 有效位 (位域见 sdecoder_pkg)
    SDTLB_TAG_ITEM_t tag_item;

    // -------------------------------------------------------------------------
    // 地址与本条目的匹配关系 (设计方案 §命中判断 / §无效化):
    //   段高位域相等 且 段内 1GB 下标落在闭区间内.
    //   字段对齐: tag_item.pa_base[16:0] 对应 PA[46:30], bit 0 对齐 PA[30],
    //   因此 [16:5] 是段高位域 PA[46:35], [4:0] 是段内 1GB 下标 PA[34:30].
    // 请求地址与无效化地址各用一套信号, RTL 不用 function (工具兼容优先).
    // -------------------------------------------------------------------------
    logic [16:0] req_seg;           // Req_PA[46:30], 请求的段空间索引
    logic [16:0] inv_seg;           // Inv_PA[46:30], 无效化地址的段空间索引
    logic [ 4:0] req_1g_idx;        // Req_PA[34:30], 请求的段内 1GB 下标
    logic [ 4:0] inv_1g_idx;        // Inv_PA[34:30], 无效化地址的段内 1GB 下标
    logic        req_high_hit;      // 请求段高位域与本条目相等
    logic        inv_high_hit;      // 无效化地址段高位域与本条目相等
    logic        req_range_hit;     // 请求段内下标落在本条目闭区间内
    logic        inv_range_hit;     // 无效化地址段内下标落在本条目闭区间内

    assign req_seg     = req_pa[46:30];
    assign inv_seg     = inv_pa[46:30];
    assign req_1g_idx  = req_pa[34:30];
    assign inv_1g_idx  = inv_pa[34:30];

    assign req_high_hit  = (req_seg[16:5] == tag_item.pa_base[16:5]);
    assign req_range_hit = (req_1g_idx >= tag_item.pa_base[4:0]) &&
                           (req_1g_idx <= tag_item.pa_up);

    assign inv_high_hit  = (inv_seg[16:5] == tag_item.pa_base[16:5]);
    assign inv_range_hit = (inv_1g_idx >= tag_item.pa_base[4:0]) &&
                           (inv_1g_idx <= tag_item.pa_up);

    logic req_match;    // 请求地址命中本条目 (不含有效位)
    logic inv_match;    // 本条目被无效化地址覆盖 (不含有效位)

    assign req_match = req_high_hit && req_range_hit;
    // note: 这里刻意不带 tag_item.valid. 设计方案要求无效化优先于装入, 若带上有效位,
    //       则条目当前无效时 inv_match 为 0, 同一拍的装入就会把刚被刷新的条目写回去.
    //       对于本来就无效的条目, 清位是空操作, 所以去掉有效位不影响"清哪些条目"的结果.
    assign inv_match = inv_en && inv_high_hit && inv_range_hit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_item <= '0;
        end
        else if (inv_all || inv_match) begin
            tag_item.valid <= 1'b0;     // 刷新优先: 只清有效位, 地址字段保留
        end
        else if (wr_pa_vld) begin
            tag_item <= '{pa_base: wr_pa_base, pa_up: wr_pa_up, valid: wr_pa_vld};
        end
    end

    // 命中 = "请求有效" 且 "条目有效" 且 "请求地址落在条目覆盖范围内"
    assign req_hit = req_vld && tag_item.valid && req_match;

endmodule

`default_nettype wire
