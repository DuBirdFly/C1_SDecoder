// =============================================================================
// round_robin_arbiter: 轮转选中器 (round robin)
//
// 用途: 在一组等价的候选 (如全相联 TLB 的 SDTLB_ENTRIES 个条目) 里轮转地挑一个, 让每个
//       候选项被挑中的机会均等 —— 内部只有一个指针, 每来一次 step 就转向下一项.
//
// 行为:
//   - sel 是 N 位 one-hot, 组合地指向当前指针
//   - step 置 1 的那一拍, 指针在时钟沿后转向下一项 (走到最后一项后回 0 —— 不依赖位宽回绕,
//     所以 N 不必是 2 的幂); 下一拍 sel 即指向新的一项
//   - 复位后指向 0 号
//
// 说明:
//   - 本模块只做"轮转选中", 不带请求过滤; 调用方若要"只在部分候选里挑", 在外面处理
//   - 不依赖任何具体项目的 package, 可以直接复用到别的设计里
// =============================================================================
`default_nettype none

module round_robin_arbiter #(
    parameter int unsigned N = 128      // 候选个数 (>= 1)
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         step,          // 当前选中项被用掉时置 1, 指针转向下一项
    output logic [N-1:0] sel            // 当前选中项 (one-hot)
);

    // N = 1 时不需要指针位宽 (避免 $clog2(1) = 0 的非法位宽)
    localparam int unsigned IDX_WIDTH = (N <= 1) ? 1 : $clog2(N);

    logic [IDX_WIDTH-1:0] ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= '0;
        end
        else if (step) begin
            ptr <= (ptr == N - 1) ? '0 : (ptr + 1'b1);
        end
    end

    always_comb begin
        sel = '0;
        sel[ptr] = 1'b1;
    end

endmodule

`default_nettype wire
