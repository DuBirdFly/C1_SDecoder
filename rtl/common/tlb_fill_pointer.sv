`include "sdecoder_constants.svh"
`default_nettype none

// SDTLB 的装填目标指针 (见设计方案 "装填指针"):
//
//   1. 有空闲条目时, 指向最低位的空闲条目;
//   2. 没有空闲条目时, 指向轮转指针的当前位置, 并在本次装填后左移一格
//      (设计方案里的 "伪随机指针" 在早期开发阶段先用轮转 $onehot 指针代替).
//
// 空闲位置由 "拍前" 的有效位决定, 但为了不把 128 位前缀与 (LOD) 放在通往 128 个
// Latch 写使能的路径上, 这里把它寄存一拍, 存的是 **下一拍** 的最低空闲条目:
//
//   valid_next    = (tlb_entry_valid | 本拍装填目标) & ~tlb_entry_clear
//   free_onehot_q <= ffz(valid_next)
//   fill_sel      = |free_onehot_q ? free_onehot_q : rotate_onehot_q
//
// 下一拍的 valid 在本拍就完全可算 (装填目标 + 置无效清位都是本拍的信号), 所以这样做
// 语义不变: free_onehot_q 里存的正好是"这一拍"的空闲位图, 装填仍然在本拍作用到阵列.
// 使能路径只剩 "FF -> 2:1 mux -> 与门": LOD 和 "有没有空闲" 的归约都落在寄存器的
// setup 路径上 (free_exists 也寄存成一位, 否则那根 128 位归约又会变成 mux 的选择端).
//
// 注意: tlb_entry_clear 必须是条目真正清 valid 的那个条件 (含 inv_en), 否则
//       前瞻算出的下一拍位图会和阵列分叉.
module tlb_fill_pointer #(
    parameter TLB_ENTRY_NUMBER = 128   // >= 2 (拼接式轮转: N-2 >= 0)
) (
    input  logic                            clk,
    input  logic                            rst_n,

    input  logic                            fill_en,            // 本拍装填一个条目
    input  logic [TLB_ENTRY_NUMBER-1:0]     tlb_entry_valid,    // 各条目的有效位 (拍前)
    input  logic [TLB_ENTRY_NUMBER-1:0]     tlb_entry_clear,    // 本拍各条目被置无效清位
    output logic [TLB_ENTRY_NUMBER-1:0]     fill_sel            // 本拍装填目标 ($onehot)
);

    // 轮转指针: 只在 "满表装填" 时步进, 复位指向 0 号
    logic [TLB_ENTRY_NUMBER-1:0] rotate_onehot_q;

    // 下一拍的最低空闲条目 ($onehot, 全满时全 0)
    logic [TLB_ENTRY_NUMBER-1:0] free_onehot_q;
    // 下一拍是否有空闲条目 (单独寄存一位, 免得太 mux 的选择端挂 128 位归约)
    logic                        free_exists_q;

    // 下一拍的有效位图: 本拍装填的条目置位, 本拍被置无效的条目清位 (置无效优先)
    wire [TLB_ENTRY_NUMBER-1:0] fill_onehot = fill_en ? fill_sel : '0;
    wire [TLB_ENTRY_NUMBER-1:0] valid_next  = (tlb_entry_valid | fill_onehot) & ~tlb_entry_clear;

    logic [TLB_ENTRY_NUMBER-1:0] free_next;

    find_first_zero #(
        .A_WIDTH (TLB_ENTRY_NUMBER)
    ) u_find_first_zero (
        .a          (valid_next),
        .direction  (1'b0),               // LSB2MSB: 从低位往高位找
        .dec        (free_next),
        .enc        ()
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rotate_onehot_q <= {{(TLB_ENTRY_NUMBER-1){1'b0}}, 1'b1};
            free_onehot_q   <= {{(TLB_ENTRY_NUMBER-1){1'b0}}, 1'b1};   // 复位后全空闲, 指向 0 号
            free_exists_q   <= 1'b1;
        end
        else begin
            free_onehot_q <= free_next;
            free_exists_q <= |free_next;

            if (fill_en && !free_exists_q) begin
                rotate_onehot_q <= {rotate_onehot_q[TLB_ENTRY_NUMBER-2:0], rotate_onehot_q[TLB_ENTRY_NUMBER-1]};
            end
        end
    end

    // 空闲优先, 否则用轮转指针: 三个输入都是 FF, 这里只是一个 mux
    assign fill_sel = free_exists_q ? free_onehot_q : rotate_onehot_q;

`ifdef ASSERT_ON
    // 装填目标必须是严格 one-hot (否则这次装填会漏填 / 多填条目)
    `assert_clk(a_fill_sel_onehot, (fill_en |-> $onehot(fill_sel)))

    // 有空闲条目时, 目标必须是空闲的
    `assert_clk(a_fill_sel_free, ((fill_en && free_exists_q) |-> !(fill_sel & tlb_entry_valid)))

    // 一位的 "有没有空闲" 与 one-hot 指针必须同拍一致
    `assert_clk(a_free_exists_track, (free_exists_q == (|free_onehot_q)))

    // 指向的条目不能是有效条目
    `assert_clk(a_free_onehot_free, (!(free_onehot_q & tlb_entry_valid)))

    // 这一拍没有装填 / 置无效时, 位图不变, 寄存的指针必须和即时算出来的一致
    // (防止前瞻公式和阵列的真实清位条件分叉)
    `assert_clk(a_free_onehot_track, ((!fill_en && (tlb_entry_clear == '0)) |-> (free_onehot_q == free_next)))
`endif

endmodule

`default_nettype wire
