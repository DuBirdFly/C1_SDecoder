// =============================================================================
// sdtlb: SDTLB (SDecoder 代换快表), 全相联结构, SDTLB_ENTRIES 个条目
//
// 职责 (见 doc/design_plan/SDecoder设计方案/SDecoder设计方案.md §SDTLB 设计):
//   每个条目 = 一份 Tag (段空间基址 / 上界 / 有效位, 存于 CAM) + 一份 Data
//   (EID / TokenID / S_PFN / Grn). 本模块把两个阵列放在一起:
//   1. 查表: 请求地址广播给全部 Tag 条目并行比较, 得到的命中向量同时作为同下标 Data
//      条目的读选中, 于是 rd_* 直接就是命中条目的数据 (未命中时全 0).
//   2. 装填: 接收 sdptw 在 DONE 状态给出的 Page Walk 结果, 由内部轮转替换指针选址,
//      同下标地写 Tag 与 Data (设计方案 §条目填充 / §替换策略).
//   3. 置无效: 广播给全部 Tag 条目 (Data 段没有有效位, 见设计方案 §无效化).
//
// 层次与约定:
//   - 条目内容一律由硬件在 Page Walk 完成后装填, 软件只能置无效 (设计方案 §设计原则 4):
//     本模块没有软件写口, wr_* 只接 sdptw 的结果.
//   - 命中下标是优先级编码: 正常配置下最多命中一个条目, 多命中时取索引最小
//     (§命中判断). 按构造不该出现多命中, 故 ASSERT_ON 下断言命中向量为 $onehot0
//   - 替换策略: 轮转指针只在装填时使用, 指向最久没有被填充过的条目; 该条目若仍有效就被
//     直接覆盖 (由条目内的写入逻辑完成, 无需先清位).
//   - 无效化与装填的竞争: 同一条目同一拍既刷新又装填时, 条目内部让刷新优先;
//     "无效化期间禁止回填" 的全局阻塞由上层按 cfg_inv_busy 做 (设计方案 §与 SDTLB 的配合).
//   - 本模块到 "命中条目的 tag 比较结果 + data 内容" 为止: SLA 计算与 SMD 组装, 以及
//     未命中后的未命中队列 / Page Walk 流程, 由上层负责.
// =============================================================================
`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

module sdtlb
import sdecoder_pkg::*;
(
    input  logic                                clk,
    input  logic                                rst_n,

    // 代换请求: 查表 (组合逻辑)
    input  logic                                req_vld,
    input  logic [PA_WIDTH-1:0]                 req_pa,
    output logic                                req_hit_vld,
    output logic [SDTLB_ENTRIES_IDX_WIDTH-1:0]  req_hit_idx,   // 命中条目下标, 多命中取最小

    // 命中条目的数据 (Data 阵列读出; 未命中时为 0)
    output logic [10:0]                         rd_eid,
    output logic [ 9:0]                         rd_token_id,
    output logic [17:0]                         rd_s_pfn,
    output logic                                rd_grn,

    // 装填: 接 sdptw 在 DONE 状态给出的 Page Walk 结果, 一次填一个条目
    input  logic                                wr_vld,
    input  logic [16:0]                         wr_pa_base,     // Tag: 段空间基地址, 以 1 GB 对界
    input  logic [ 4:0]                         wr_pa_up,       // Tag: 段空间上界 (含)
    input  logic [10:0]                         wr_eid,         // Data: Entity 标识
    input  logic [ 9:0]                         wr_token_id,    // Data: 逻辑池标识
    input  logic [17:0]                         wr_s_pfn,       // Data: SLA 基址, 以 1 GB 对界
    input  logic                                wr_grn,         // Data: 粒度位, 1 段式 0 页式

    // 置无效 (刷新): 只作用于 Tag 侧的有效位
    input  logic                                inv_all,
    input  logic                                inv_en,
    input  logic [PA_WIDTH-1:0]                 inv_pa
);

    // 命中向量: 每个 Tag 条目的比较结果, 同时作为同下标 Data 条目的读选中
    logic [SDTLB_ENTRIES-1:0] req_hit;

    // 每个 Data 条目的读出 (未选中时为 0), 汇总后就是命中条目的数据
    logic [10:0] rd_eid_item      [SDTLB_ENTRIES];
    logic [ 9:0] rd_token_id_item [SDTLB_ENTRIES];
    logic [17:0] rd_s_pfn_item    [SDTLB_ENTRIES];
    logic        rd_grn_item      [SDTLB_ENTRIES];

    // 轮转替换指针: 指向最久没有被填充过的条目, 只在装填时自增 (位宽自然回绕)
    logic [SDTLB_ENTRIES_IDX_WIDTH-1:0] fill_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fill_ptr <= '0;
        end
        else if (wr_vld) begin
            fill_ptr <= fill_ptr + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // SDTLB_ENTRIES 个条目: 请求与刷新广播, 装填按 fill_ptr 译码后 Tag/Data 同写一条
    // -------------------------------------------------------------------------
    genvar genvar_i;
    generate
        for (genvar_i = 0; genvar_i < SDTLB_ENTRIES; genvar_i++) begin : genvar_item
            // Tag 段: 比较与有效位
            sdtlb_tag_item u_tag_item (
                .clk        (clk),
                .rst_n      (rst_n),
                .req_vld    (req_vld),
                .req_pa     (req_pa),
                .req_hit    (req_hit[genvar_i]),
                .wr_pa_base (wr_pa_base),
                .wr_pa_up   (wr_pa_up),
                .wr_pa_vld  (wr_vld && (fill_ptr == genvar_i)),
                .inv_all    (inv_all),
                .inv_en     (inv_en),
                .inv_pa     (inv_pa)
            );

            // Data 段: 无有效位, 写使能与 Tag 同源, 读出由同下标 Tag 段 hit 结果选中
            sdtlb_data_item u_data_item (
                .clk         (clk),
                .rst_n       (rst_n),
                .wr_vld      (wr_vld && (fill_ptr == genvar_i)),
                .wr_eid      (wr_eid),
                .wr_token_id (wr_token_id),
                .wr_s_pfn    (wr_s_pfn),
                .wr_grn      (wr_grn),
                .rd_sel      (req_hit[genvar_i]),
                .rd_eid      (rd_eid_item[genvar_i]),
                .rd_token_id (rd_token_id_item[genvar_i]),
                .rd_s_pfn    (rd_s_pfn_item[genvar_i]),
                .rd_grn      (rd_grn_item[genvar_i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 命中数据汇总: 每个 Data 条目未选中时输出 0, 因此逐位 OR 起来即为命中条目的数据
    // -------------------------------------------------------------------------
    always_comb begin
        rd_eid      = '0;
        rd_token_id = '0;
        rd_s_pfn    = '0;
        rd_grn      = 1'b0;
        for (int i = 0; i < SDTLB_ENTRIES; i++) begin
            rd_eid      = rd_eid      | rd_eid_item[i];
            rd_token_id = rd_token_id | rd_token_id_item[i];
            rd_s_pfn    = rd_s_pfn    | rd_s_pfn_item[i];
            rd_grn      = rd_grn      | rd_grn_item[i];
        end
    end

    // -------------------------------------------------------------------------
    // 命中下标: 从最高下标往低扫, 低下标最后赋值, 于是多命中时取索引最小的条目
    // -------------------------------------------------------------------------
    assign req_hit_vld = |req_hit;

    always_comb begin
        req_hit_idx = '0;       // 未命中时给 0, 上层以 req_hit_vld 判断是否有效
        for (int i = SDTLB_ENTRIES - 1; i >= 0; i--) begin
            if (req_hit[i]) begin
                req_hit_idx = i[SDTLB_ENTRIES_IDX_WIDTH-1:0];
            end
        end
    end

`ifdef ASSERT_ON
    // 按构造同一次请求最多命中一个条目 (设计方案 §命中判断), 这里守住这个前提:
    // 命中向量应为宽松独热码 (全 0 即未命中, 也算合法).
    `assert_clk(a_req_hit_onehot0, $onehot0(req_hit));
`endif

endmodule

`default_nettype wire
