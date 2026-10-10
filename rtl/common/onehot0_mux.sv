// =============================================================================
// onehot0_mux: one-hot (允许全 0) 选择器
//
// 用途: 从 N 路等宽数据里按 one-hot 选中信号挑出一路 —— 全相联结构里"命中向量的某一位
//       有效就取该条目的数据, 全 0 (未命中) 就输出全 0"这种场景.
//
// 行为:
//   - sel 是 N 位 one-hot, 也允许全 0
//   - sel 全 0 时 dout = 0: 这正是名字里那个 0 (onehot0) 的含义 —— 未命中不需要额外的
//     有效位来门控, 选择器本身就把它变成全 0
//   - sel 多于一位有效时按最高位胜出 (循环里后写的覆盖先写的); 按约定不应出现, 调用方
//     用断言守住
//
// 说明: 纯组合逻辑, 不依赖任何具体项目的 package, 可以直接复用到别的设计里
// =============================================================================
`default_nettype none

module onehot0_mux #(
    parameter int unsigned N     = 128,     // 输入路数 (>= 1)
    parameter int unsigned WIDTH = 8        // 每路数据位宽 (>= 1)
) (
    input  logic [N-1:0]        sel,        // 选中 (one-hot, 允许全 0)
    input  logic [WIDTH-1:0]    din [N],    // N 路数据
    output logic [WIDTH-1:0]    dout        // 选中那一路; sel 全 0 时输出全 0
);

    always_comb begin
        dout = '0;
        for (int i = 0; i < N; i++) begin
            if (sel[i]) begin
                dout = din[i];
            end
        end
    end

endmodule

`default_nettype wire
