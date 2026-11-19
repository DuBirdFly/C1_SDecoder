`include "sdecoder_constants.svh"
`default_nettype none

// SDTLB 的装填目标指针 (见设计方案 "装填指针"):
//   1. 有空闲条目时, 指向最低位的空闲条目;
//   2. 没有空闲条目时, 指向轮转指针的当前位置, 并在本次装填后左移一格
//      (设计方案里的 "伪随机指针" 在早期开发阶段先用轮转 $onehot 指针代替).
//
// 空闲位置由 tlb_entry_valid 当拍组合找首 0, 直接给 TLB 做 fill_en_vector:
//   free_exists = ~&tlb_entry_valid
//   fill_sel    = free_exists ? find_first_zero(tlb_entry_valid) : shift_onehot_q
//
// 注: ~&tlb_entry_valid 的性能可能比 |first_free_vec 更好 (在不考虑综合器优化的情况下)
//     因为 |first_free_vec 是对找到的首 0 的组合逻辑结果再加组合运算, 而 tlb_entry_valid
//     直接就来自于 TLB 的 FF 输出

module tlb_fill_pointer #(
    parameter TLB_ENTRY_NUMBER = 128   // >= 2 (拼接式轮转: N-2 >= 0)
) (
    input  logic                            clk,
    input  logic                            rst_n,

    input  logic                            fill_en,            // 装填条目使能
    input  logic [TLB_ENTRY_NUMBER-1:0]     tlb_entry_valid,    // 各条目的有效位
    output logic [TLB_ENTRY_NUMBER-1:0]     fill_sel            // 本拍装填目标
);

    // 轮转指针: 只在 "满表装填 (即必须淘汰一个 TLB Entry)" 时步进
    logic [TLB_ENTRY_NUMBER-1:0] shift_onehot_q;

    // 最低位的空闲条目 (valid 为 0 的最低一位); 全满时 first_free_vec = 0
    logic [TLB_ENTRY_NUMBER-1:0] first_free_vec;

    // 是否有空闲条目
    wire free_exists = ~&tlb_entry_valid;

    find_first_zero #(
        .A_WIDTH (TLB_ENTRY_NUMBER)
    ) u_find_first_zero (
        .a          (tlb_entry_valid),
        .direction  (1'b0),               // LSB2MSB: 从低位往高位找
        .dec        (first_free_vec),
        .enc        ()
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_onehot_q <= {{(TLB_ENTRY_NUMBER-1){1'b0}}, 1'b1};
        end
        else if (fill_en && !free_exists) begin
            shift_onehot_q <= {shift_onehot_q[TLB_ENTRY_NUMBER-2:0], shift_onehot_q[TLB_ENTRY_NUMBER-1]};
        end
    end

    // 空闲优先, 否则用轮转指针
    assign fill_sel = free_exists ? first_free_vec : shift_onehot_q;

`ifdef ASSERT_ON
    // 装填目标必须是严格 one-hot (否则这次装填会漏填 / 多填条目)
    `assert_clk(a_fill_sel_onehot, (fill_en |-> $onehot(fill_sel)))

    // 有空闲条目时, 目标必须是空闲的
    `assert_clk(a_fill_sel_free, ((fill_en && free_exists) |-> !(fill_sel & tlb_entry_valid)))
`endif

endmodule

`default_nettype wire
