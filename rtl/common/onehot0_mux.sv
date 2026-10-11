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
