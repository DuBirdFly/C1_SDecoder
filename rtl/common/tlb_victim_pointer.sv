`default_nettype none

module tlb_victim_pointer #(
    parameter TLB_ENTRY_NUMBER = 128   // >= 2 (拼接式轮转: N-2 >= 0)
) (
    input  logic                            clk,
    input  logic                            rst_n,

    input  logic                            step,       // 本条被替换掉, 指针转向下一条
    output logic [TLB_ENTRY_NUMBER-1:0]     victim_sel  // 当前被替换条目 ($onehot)
);

    // 宽度为 TLB_ENTRY_NUMBER 的严格 $onehot 左移循环寄存器
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            victim_sel <= {{(TLB_ENTRY_NUMBER-1){1'b0}}, 1'b1};     // 复位后指向 0 号
        end
        else if (step) begin
            victim_sel <= {victim_sel[TLB_ENTRY_NUMBER-2:0], victim_sel[TLB_ENTRY_NUMBER-1]};
        end
    end

endmodule

`default_nettype wire
