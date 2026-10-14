`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdptw: 两级 Page Walk (同一 32GB 区间里段式与页式共存)
//   一级表 SDT_L1 (16B 条目) 以 PA[47:35] 索引 (PA[47] 断言为 0), 条目里的 Type 位说明该区间的组织方式
//   (见设计方案 表3):
//     Type = 1: 该 32GB 区间有且仅有 1 个段表, 同时还有 N 个页表 -> 先判段:
//               PA 落在 [SEG_BASE, SEG_BASE + SEG_LEN] 里就按段式收工 (只读一级);
//               落在段外就走该区间的页表, 再去读二级.
//     Type = 0: 该 32GB 区间均为页表 -> 直接读二级表 SDT_L2 (8B 条目), 以 PA[34:30] 索引.
//   一级条目无效时直接收工, 不再去读二级 (L2_BASE 不可信).
//   本模块只报"读到了什么": 两个原始条目 + rsp_sdt_l2_read (本次读没读二级) + 结果握手.
//   段区间判定的开闭语义, SLA 拼装, 异常码, req_id 记账都在上层.
//   注: rsp_sdt_l2_read 是"过程事实", 上级靠它才能把"段式命中"与"段外且二级条目无效"分开 ——
//       这两种情况的一级 / 二级 valid 位完全一样.
//   访存: AXI4-Lite 读通道 (AR + R), 一次 walk 最多发两次 AR: 一级读整 16B 条目;
//         二级读 8B 条目, 取 16B 总线上由 AR 地址 bit[3] 选出的那一半
//   状态机: IDLE (收请求) -> AR_L1 -> R_L1 (判段) -> [AR_L2 -> R_L2] -> DONE (保持到被取走)
module sdptw
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 一级表基地址 (IO 寄存器, 16B 对界)
    input  logic [PA_WIDTH-1:0]         sdt_l1_base,

    // Page Walk 请求: 一次一个, 只给 1GB 对齐的页号 PA[47:30] (PA[47] 断言为 0)
    input  logic [PA_BASE_WIDTH-1:0]    req_pa,
    input  logic                        req_valid,
    output logic                        req_ready,

    // Page Walk 结果: 保持到被 rsp_ready 取走
    output logic                        rsp_valid,
    input  logic                        rsp_ready,
    output SDT_L1_ITEM_t                rsp_sdt_l1_item,
    output SDT_L2_ITEM_t                rsp_sdt_l2_item,
    output logic                        rsp_sdt_l2_read,       // 本次读了二级表 (0 = 只读了一级条目)

    // 读本地 memory
    // AXI4-Lite 读通道 (AR + R) 类似物, 暂不含 rresp
    // tw_* 即 table_walk_*
    output logic [PA_WIDTH-1:0]         tw_araddr,
    output logic                        tw_arvalid,
    input  logic                        tw_arready,

    input  logic [127:0]                tw_rdata,
    input  logic                        tw_rvalid,
    output logic                        tw_rready
);

    // PA[47:35]: 一级表索引位数 (PA[47] 断言为 0, 故高半区不可达)
    localparam int L1_IDX_WIDTH = PA_BASE_WIDTH - PA_UP_WIDTH;      // 13

    typedef enum logic [2:0] {
        ST_IDLE,        // 空闲: 可以收 walk 请求
        ST_AR_L1,       // 发一级读的 AR, 等它被接收
        ST_R_L1,        // 收一级条目, 并判要不要读二级
        ST_AR_L2,       // 发二级读的 AR
        ST_R_L2,        // 收二级条目
        ST_DONE         // 结果已锁存, 保持到被 rsp_ready 取走
    } state_e;

    state_e                     state;

    logic [PA_BASE_WIDTH-1:0]   req_pa_r;       // 本次 walk 的 PA[47:30] (锁存)

    // 结果: 在收到条目那一拍锁存, 之后一直保持到被取走
    SDT_L1_ITEM_t               l1_item_r;
    SDT_L2_ITEM_t               l2_item_r;
    logic                       l2_read_r;

    // 一级条目地址: 表基地址 16B 对界 + PA[47:35] * 16B
    wire [PA_WIDTH-1:0]         l1_addr = {sdt_l1_base[PA_WIDTH-1:4], 4'h0} +
                                          {{(PA_WIDTH - 4 - L1_IDX_WIDTH){1'b0}},
                                            req_pa_r[PA_BASE_WIDTH-1:PA_UP_WIDTH], 4'h0};

    // 二级条目地址: 一级条目给的 L2_BASE[47:3] + PA[34:30] * 8B
    wire [PA_WIDTH-1:0]         l2_addr = {l1_item_r.l2_base, 3'h0} +
                                          {{(PA_WIDTH - 3 - PA_UP_WIDTH){1'b0}},
                                            req_pa_r[PA_UP_WIDTH-1:0], 3'h0};

    // 读回的条目: 一级是整 16B (地址 16B 对界, 16B 总线的两个 8B lane 都有效), 直接取整条;
    // 二级只读 8B, 按标准 AXI 单拍 (AXI-Lite 相当于突发长度为 1) 的 lane 规则, 这 8B 落在
    // 16B 总线的哪一半由 AR 地址的 bit[3] 决定: araddr[3] = 0 -> rdata[63:0]
    // 注: 这里必须用 net 声明 (wire) 或 assign: module 级"变量"的声明处初始化只执行一次
    //     (time 0 赋一次就不再跟随), 写成 SDT_L1_ITEM_t l1_item = tw_rdata; 会静默读错条目
    wire SDT_L1_ITEM_t          l1_item = tw_rdata;
    wire SDT_L2_ITEM_t          l2_item = l2_addr[3] ? tw_rdata[127:64] : tw_rdata[63:0];

    // 段区间: 闭区间 [SEG_BASE, SEG_BASE + SEG_LEN]
    wire [PA_UP_WIDTH:0]        seg_up  = {1'b0, l1_item.seg_base} + {1'b0, l1_item.seg_len};
    wire                        seg_hit = l1_item.type_bit &&
                                          (req_pa_r[PA_UP_WIDTH-1:0] >= l1_item.seg_base) &&
                                          ({1'b0, req_pa_r[PA_UP_WIDTH-1:0]} <= seg_up);

    // 段覆盖 -> 段式收工 (只读一级); Type = 0, 或 Type = 1 但 PA 在段外 (走该区间的页表)
    // -> 去读二级; 一级条目无效也收工 (L2_BASE 不可信)
    wire                        l1_stop = !l1_item.valid || seg_hit;

    assign req_ready        = (state == ST_IDLE);

    assign tw_arvalid       = (state == ST_AR_L1) || (state == ST_AR_L2);
    assign tw_araddr        = (state == ST_AR_L2) ? l2_addr : l1_addr;
    assign tw_rready        = (state == ST_R_L1) || (state == ST_R_L2);

    assign rsp_valid        = (state == ST_DONE);
    assign rsp_sdt_l1_item  = l1_item_r;
    assign rsp_sdt_l2_item  = l2_item_r;
    assign rsp_sdt_l2_read  = l2_read_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            req_pa_r   <= '0;
            l1_item_r  <= '0;
            l2_item_r  <= '0;
            l2_read_r  <= 1'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        req_pa_r <= req_pa;
                        state  <= ST_AR_L1;
                    end
                end

                ST_AR_L1: begin
                    if (tw_arvalid && tw_arready) begin
                        state <= ST_R_L1;
                    end
                end

                ST_R_L1: begin
                    if (tw_rvalid && tw_rready) begin
                        l1_item_r <= l1_item;
                        if (l1_stop) begin
                            // 段式命中 (或一级条目无效): 没读二级, 二级条目输出清 0
                            l2_item_r <= '0;
                            l2_read_r <= 1'b0;
                            state     <= ST_DONE;
                        end
                        else begin
                            state <= ST_AR_L2;
                        end
                    end
                end

                ST_AR_L2: begin
                    if (tw_arvalid && tw_arready) begin
                        state <= ST_R_L2;
                    end
                end

                ST_R_L2: begin
                    if (tw_rvalid && tw_rready) begin
                        l2_item_r <= l2_item;
                        l2_read_r <= 1'b1;
                        state     <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    if (rsp_ready) begin
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

`ifdef ASSERT_ON
    // 软件约束: 段必须落在本条目所属的 32GB 区间内 (SEG_BASE + SEG_LEN <= 31)
    `assert_clk(a_seg_range_valid,
                (((state == ST_R_L1) && tw_rvalid && tw_rready &&
                  l1_item.valid && l1_item.type_bit) |-> (seg_up <= 31)))

    // SDecoder 只处理 Mem 空间 (PA[47] = 1 是 IO 空间): 请求 PA / 一级表基地址 / 二级表
    // 基地址的 PA[47] 都必须为 0. 字段里保留这一位只为维持 48 位地址口径, 见 sdecoder_pkg
    `assert_clk(a_req_pa47_zero,
                ((req_valid && req_ready) |-> !req_pa[PA_BASE_WIDTH-1]))
    `assert_clk(a_sdt_l1_base47_zero,
                (!sdt_l1_base[PA_WIDTH-1]))
    `assert_clk(a_l2_base47_zero,
                (((state == ST_R_L1) && tw_rvalid && tw_rready && !l1_stop)
                 |-> !l1_item.l2_base[L2_BASE_WIDTH-1]))
`endif

endmodule

`default_nettype wire
