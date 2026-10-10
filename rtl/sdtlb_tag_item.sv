// =============================================================================
// sdtlb_tag_item: SDTLB 的一个 Tag 条目, 即全相联 CAM 中的一级比较单元
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §命中判断):
//   把一次代换请求的请求地址 req_pa 与"本条目"描述的段空间做比较, 给出本条目
//   是否命中. 同时满足以下三条才算命中:
//     1. 本条目有效位 = 1;
//     2. req_pa[46:35] 与 pa_base[46:35] 相等;
//     3. req_pa[34:30] 落在闭区间 [pa_base[34:30], pa_up] 内 (pa_up 是绝对上界, 含).
//
//   页式条目满足 pa_base[34:30] = pa_up, 区间退化为一个 1GB 页, 因此段式与页式共用
//   本模块, 不需要两套比较逻辑. 区间为空 (pa_up < pa_base[34:30]) 的装填请求是非法
//   的, 由 sdtlb 的 a_fill_pa_range_valid 断言守住.
//
// 层次与约定:
//   - sdtlb 用 generate 例化 SDTLB_ENTRIES 份本模块, 再把各条目的 req_hit 做
//     优先级编码 (正常配置下同一次请求最多命中一个条目), 得到命中条目下标.
//   - 条目内容存在本模块的 tag_item 寄存器里. 装填由端口 fill_pa_vld 作写使能: 有效时
//     把 fill_pa_base / fill_pa_up / fill_pa_vld 一起写进 tag_item, 因此装填当拍比较用的
//     仍是旧值, 新值下一拍生效.
//   - 无效化按设计方案 §无效化 实现: inv_all 清全部条目的有效位; inv_en + inv_pa
//     清掉覆盖该地址的条目 (段高位域匹配 且 地址落在闭区间内). **两个入口都优先于
//     装填**, 即同一拍既刷新又装填时按刷新处理, 不会把刚清掉的条目写回去; 对本来就
//     无效的条目, 按地址清除是空操作, 但同样会挡住同拍的装填.
//   - 置无效只清有效位, 地址字段保留 (无效条目的地址字段是 don't care).
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
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

    // 装填请求
    input  logic [16:0]             fill_pa_base,
    input  logic [ 4:0]             fill_pa_up,
    input  logic                    fill_pa_vld,

    // 置无效 (刷新) 请求, 置无效全部 TLB ENTRIES
    input  logic                    inv_all,

    // 置无效 (刷新) 请求, 置无效指定 pa 范围覆盖的条目
    input  logic                    inv_en,
    input  logic [PA_WIDTH-1:0]     inv_pa

);

    // 本条目寄存器: 段空间基址 / 段空间上界(含) / 有效位 (位域见 sdecoder_pkg)
    SDTLB_TAG_ITEM_t tag_item;

    // note: 这四行必须是 wire (或 logic + assign): 用 logic 加声明初始化只会在 0 时刻
    //       赋值一次, 不是持续赋值, 比较结果会停在初始值上.
    wire [16:0] req_seg_idx     = req_pa[46:30];
    wire [ 4:0] req_page_idx    = req_pa[34:30];
    logic       req_high_hit;
    logic       req_range_hit;

    wire [16:0] inv_seg_idx     = inv_pa[46:30];
    wire [ 4:0] inv_page_idx    = inv_pa[34:30];
    logic       inv_high_hit;
    logic       inv_range_hit;

    assign req_high_hit  = (req_seg_idx[16:5] == tag_item.pa_base[16:5]);
    assign req_range_hit = (req_page_idx >= tag_item.pa_base[4:0]) &&
                           (req_page_idx <= tag_item.pa_up);

    assign inv_high_hit  = (inv_seg_idx[16:5] == tag_item.pa_base[16:5]);
    assign inv_range_hit = (inv_page_idx >= tag_item.pa_base[4:0]) &&
                           (inv_page_idx <= tag_item.pa_up);

    logic req_match;    // 请求地址命中本条目 (不含有效位)
    logic inv_match;    // 本条目被无效化地址覆盖 (不含有效位)

    assign req_match = req_high_hit && req_range_hit;
    // note: 这里刻意不带 tag_item.valid. else if 的优先级只在分支条件成立时才起作用:
    //       若把有效位并进匹配条件, 条目当前无效时 inv_match 就是 0, 清位分支根本不会
    //       被选中, 同拍的装填会照常执行, 把一条覆盖"正在被刷新的地址"的映射填进去
    //       (无效条目本就无需清位, 谈不上"写回"). 去掉有效位不影响"清哪些条目".
    assign inv_match = inv_en && inv_high_hit && inv_range_hit;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tag_item <= '0;
        end
        else if (inv_all || inv_match) begin
            tag_item.valid <= 1'b0;
        end
        else if (fill_pa_vld) begin
            tag_item <= '{pa_base: fill_pa_base, pa_up: fill_pa_up, valid: fill_pa_vld};
        end
    end

    // 命中 = "请求有效" 且 "条目有效" 且 "请求地址落在条目覆盖范围内"
    assign req_hit = req_vld && tag_item.valid && req_match;


`ifdef ASSERT_ON
    // req_pa[47] 必须为 0. 设计方案 §地址划分: SDecoder 只处理 Mem 空间 (PA[47] = 0),
    // PA[47] = 1 的 IO 空间请求应由上层按"地址非法异常"处理 (接口手册 §异常码),
    // 不该送进 Tag 阵列, 这里守住这个前提.
    // 载荷只在请求有效时可信, 故用 req_vld 限定 (复位与 rst_n 为 X 时由宏里的 disable iff 挡住).
    `assert_clk(a_req_pa_mem_space, (req_vld == 1'b0) || (req_pa[PA_WIDTH-1] == 1'b0));

    // 装填区间非空的约束 (pa_up >= pa_base[4:0], 即上界不低于基址页号) 由 sdtlb 的
    // a_fill_pa_range_valid 断言守住, 不在这里重复检查
`endif

endmodule

`default_nettype wire
