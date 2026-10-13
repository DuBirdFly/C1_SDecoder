`include "sdecoder_constants.svh"
`include "sdecoder_pkg.svh"
`default_nettype none

// sdptw: 两级 Page Walk (同一 32GB 区间里段式与页式共存)
//   一级表 SDT_L1 (16B 条目) 以 PA[46:35] 索引, 条目里的 Type 位说明该区间的组织方式 (见设计方案 表3):
//     Type = 1: 该 32GB 区间有且仅有 1 个段表, 同时还有 N 个页表 -> 先判段:
//               PA 落在 [SEG_BASE, SEG_BASE + SEG_LEN] 里就按段式收工 (只读一级);
//               落在段外就走该区间的页表, 再去读二级.
//     Type = 0: 该 32GB 区间均为页表 -> 直接读二级表 SDT_L2 (8B 条目), 以 PA[34:30] 索引.
//   一级条目无效时直接收工, 不再去读二级 (L2_BASE 不可信).
//   本模块只报"读到了什么": 两个原始条目 + walk_l2_read (本次读没读二级) + 结果握手.
//   段区间判定的开闭语义, SLA 拼装, 异常码, req_id 记账都在上层.
//   注: walk_l2_read 是"过程事实", 上级靠它才能把"段式命中"与"段外且二级条目无效"分开 ——
//       这两种情况的一级 / 二级 valid 位完全一样.
//   访存: AXI4-Lite 读通道 (AR + R), 一次 walk 最多发两次 AR.
//   状态机: IDLE (收请求) -> AR_L1 -> R_L1 (判段) -> [AR_L2 -> R_L2] -> DONE (保持到被取走)
module sdptw
import sdecoder_pkg::*;
(
    input  logic                        clk,
    input  logic                        rst_n,

    // 一级表基地址 (IO 寄存器, 16B 对界)
    input  logic [PA_WIDTH-1:0]         sdt_l1_base,

    // Page Walk 请求: 一次一个, 只给 1GB 对齐的页号 PA[46:30]
    input  logic                        walk_valid,
    input  logic [PA_BASE_WIDTH-1:0]    walk_req_pa,
    output logic                        walk_ready,

    // Page Walk 结果: 保持到被 walk_rsp_ready 取走
    output logic                        walk_rsp_valid,
    input  logic                        walk_rsp_ready,
    output SDT_L1_ITEM_t                walk_sdt_l1_item,
    output SDT_L2_ITEM_t                walk_sdt_l2_item,
    output logic                        walk_l2_read,       // 本次读了二级表 (0 = 结果只看一级条目)

    // 本地存储读: AXI4-Lite 读通道 (AR + R). 读失败 (总线错误 / ECC 多错) 怎么报还没定,
    // 暂时没有这个入口, 读回什么就按什么判定
    output logic [PA_WIDTH-1:0]         tw_araddr,
    output logic                        tw_arvalid,
    input  logic                        tw_arready,

    input  logic [127:0]                tw_rdata,
    input  logic                        tw_rvalid,
    output logic                        tw_rready
);

    // PA[46:35]: 一级表索引位数
    localparam int L1_IDX_WIDTH = PA_BASE_WIDTH - PA_UP_WIDTH;      // 12

    typedef enum logic [2:0] {
        ST_IDLE,        // 空闲: 可以收 walk 请求
        ST_AR_L1,       // 发一级读的 AR, 等它被接收
        ST_R_L1,        // 收一级条目, 并判要不要读二级
        ST_AR_L2,       // 发二级读的 AR
        ST_R_L2,        // 收二级条目
        ST_DONE         // 结果已锁存, 保持到被 walk_rsp_ready 取走
    } state_e;

    state_e                     state;

    logic [PA_BASE_WIDTH-1:0]   req_pa;         // 本次 walk 的 PA[46:30]

    // 结果: 在收到条目那一拍锁存, 之后一直保持到被取走
    SDT_L1_ITEM_t               l1_item_r;
    SDT_L2_ITEM_t               l2_item_r;
    logic                       l2_read_r;

    // 读回的条目: 一级 16B, 二级取低 64 位
    SDT_L1_ITEM_t               l1_item;
    SDT_L2_ITEM_t               l2_item;
    assign l1_item = tw_rdata;
    assign l2_item = tw_rdata[63:0];

    // 一级条目地址: 表基地址 16B 对界 + PA[46:35] * 16B
    wire [PA_WIDTH-1:0]         l1_addr = {sdt_l1_base[PA_WIDTH-1:4], 4'h0} +
                                          {{(PA_WIDTH - 4 - L1_IDX_WIDTH){1'b0}},
                                            req_pa[PA_BASE_WIDTH-1:PA_UP_WIDTH], 4'h0};

    // 二级条目地址: 一级条目给的 L2_BASE[47:3] + PA[34:30] * 8B
    wire [PA_WIDTH-1:0]         l2_addr = {l1_item_r.l2_base, 3'h0} +
                                          {{(PA_WIDTH - 3 - PA_UP_WIDTH){1'b0}},
                                            req_pa[PA_UP_WIDTH-1:0], 3'h0};

    // 段区间: 闭区间 [SEG_BASE, SEG_BASE + SEG_LEN] (开 / 闭语义待定, 现在按闭区间; 只认段式条目)
    wire [PA_UP_WIDTH:0]        seg_up  = {1'b0, l1_item.seg_base} + {1'b0, l1_item.seg_len};
    wire                        seg_hit = l1_item.type_bit &&
                                          (req_pa[PA_UP_WIDTH-1:0] >= l1_item.seg_base) &&
                                          ({1'b0, req_pa[PA_UP_WIDTH-1:0]} <= seg_up);

    // 段覆盖 -> 段式收工 (只读一级); Type = 0, 或 Type = 1 但 PA 在段外 (走该区间的页表)
    // -> 去读二级; 一级条目无效也收工 (L2_BASE 不可信)
    wire                        l1_stop = !l1_item.valid || seg_hit;

    assign walk_ready       = (state == ST_IDLE);

    assign tw_arvalid       = (state == ST_AR_L1) || (state == ST_AR_L2);
    assign tw_araddr        = (state == ST_AR_L2) ? l2_addr : l1_addr;
    assign tw_rready        = (state == ST_R_L1) || (state == ST_R_L2);

    assign walk_rsp_valid   = (state == ST_DONE);
    assign walk_sdt_l1_item = l1_item_r;
    assign walk_sdt_l2_item = l2_item_r;
    assign walk_l2_read     = l2_read_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            req_pa     <= '0;
            l1_item_r  <= '0;
            l2_item_r  <= '0;
            l2_read_r  <= 1'b0;
        end
        else begin
            case (state)
                ST_IDLE: begin
                    if (walk_valid && walk_ready) begin
                        req_pa <= walk_req_pa;
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
                    if (walk_rsp_ready) begin
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
`endif

endmodule

`default_nettype wire
