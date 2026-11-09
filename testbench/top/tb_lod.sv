`default_nettype none

`timescale 1ns/1ps

module tb_lod;

    localparam int unsigned A_WIDTH   = 8;
    localparam int unsigned ENC_WIDTH = $clog2(A_WIDTH) + 1;

    logic                 clk;
    logic [A_WIDTH-1:0]   a;
    logic [A_WIDTH-1:0]   dec;
    logic [ENC_WIDTH-1:0] enc;

    int unsigned checks = 0;
    int unsigned errors = 0;

    crg u_crg (
        .pclk    (         ),
        .presetn (         ),
        .aclk    (         ),
        .aresetn (         ),
        .clk     (clk      ),
        .rst_n   (         )
    );

    lod #(
        .A_WIDTH (A_WIDTH)
    ) u_lod (
        .a   (a),
        .dec (dec),
        .enc (enc)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_lod, "+all");
        $display("===============================================");
    end
`endif

`ifdef DUMP_SVA
    initial begin
        $display("===============================================");
        $display("Dumping FSDB SVA");
        $fsdbDumpSVA(0, tb_lod);
        $display("===============================================");
    end
`endif

    // 参考模型: 从 MSB 起第一个 0 的 one-hot; 全 1 时为 0
    function automatic logic [A_WIDTH-1:0] ref_dec(input logic [A_WIDTH-1:0] vec);
        logic found;

        ref_dec = '0;
        found   = 1'b0;
        for (int i = A_WIDTH - 1; i >= 0; i--) begin
            if (!found && !vec[i]) begin
                ref_dec[i] = 1'b1;
                found      = 1'b1;
            end
        end
    endfunction

    // 参考模型: 前导 1 的个数; 全 1 时输出全 1 哨兵
    function automatic logic [ENC_WIDTH-1:0] ref_enc(input logic [A_WIDTH-1:0] vec);
        int unsigned cnt;
        logic        found;

        cnt   = 0;
        found = 1'b0;
        for (int i = A_WIDTH - 1; i >= 0; i--) begin
            if (!found) begin
                if (vec[i]) begin
                    cnt = cnt + 1;
                end
                else begin
                    found = 1'b1;
                end
            end
        end

        if (cnt == A_WIDTH) begin
            return {ENC_WIDTH{1'b1}};
        end
        return cnt;
    endfunction

    initial begin
        a = '0;

        repeat (2) @(posedge clk);

        // 穷举所有输入组合
        for (int i = 0; i < (1 << A_WIDTH); i++) begin
            a <= i[A_WIDTH-1:0];
            @(posedge clk);

            checks = checks + 2;
            if (dec !== ref_dec(a)) begin
                errors = errors + 1;
                $display("[ERROR] @%0t: a=0b%b, dec=0b%b, 期望 0b%b", $time, a, dec, ref_dec(a));
            end
            if (enc !== ref_enc(a)) begin
                errors = errors + 1;
                $display("[ERROR] @%0t: a=0b%b, enc=0x%h, 期望 0x%h", $time, a, enc, ref_enc(a));
            end
        end

        $display("\n%0d checks, %0d errors", checks, errors);
        if (errors == 0) begin
            $display("RESULT: PASS");
        end
        else begin
            $display("RESULT: FAIL");
            $fatal(1, "lod 单元自检失败: %0d 条", errors);
        end
        $finish;
    end

endmodule

`default_nettype wire
