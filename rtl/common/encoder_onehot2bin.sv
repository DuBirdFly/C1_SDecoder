`default_nettype none

module encoder_onehot2bin #(
    parameter   ONEHOT_WIDTH = 8,
    localparam  BIN_WIDTH = $clog2(ONEHOT_WIDTH)
) (
    input  logic [ONEHOT_WIDTH-1:0] onehot,
    input  logic                    en,
    output logic [BIN_WIDTH-1:0]    bin
);

    always_comb begin
        bin = '0;
        if (en) begin
            for (int i = 0; i < ONEHOT_WIDTH; i++) begin
                if (onehot[i]) begin
                    bin = i;
                end
            end
        end
    end

endmodule

`default_nettype wire
