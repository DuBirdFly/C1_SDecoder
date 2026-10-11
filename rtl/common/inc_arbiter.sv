`default_nettype none

module inc_arbiter #(
    parameter int unsigned N = 128      // 候选个数 (>= 1)
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         step,          // 当前选中项被用掉时置 1, 指针转向下一项
    output logic [N-1:0] sel            // 当前选中项 (one-hot)
);

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

    decoder_bin2onehot #(
        .BIN_WIDTH(IDX_WIDTH)
    ) u_decoder_bin2onehot (
        .bin(ptr),
        .en(1'b1),
        .onehot(sel)
    );

endmodule

`default_nettype wire
