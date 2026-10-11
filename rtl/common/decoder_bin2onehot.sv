`default_nettype none

module decoder_bin2onehot #(
    parameter   BIN_WIDTH = 3,
    localparam  ONEHOT_WIDTH = 1 << BIN_WIDTH
) (
    input  logic [BIN_WIDTH-1:0]    bin,
    input  logic                    en,
    output logic [ONEHOT_WIDTH-1:0] onehot
);

    always_comb begin
        onehot = '0;
        if (en) begin
            onehot[bin] = 1'b1;
        end
    end

endmodule

`default_nettype wire
