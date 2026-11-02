`default_nettype none

`timescale 1ns/1ps

module tb_age_matrix_8x8;

    localparam int unsigned ITEM_DEPTH = sdecoder_pkg::SDMQ_DEPTH;

    logic clk;

    // 影子: 记录 tb 已经申请到的条目. 背靠背申请时 uif.item_valid / mon_cb 都还看不到
    // 上一拍刚写进去的位, 所以空闲位置和判满都基于这个影子累加
    logic [ITEM_DEPTH-1:0] valid_shadow = '0;

    crg u_crg (
        .pclk    (         ),
        .presetn (         ),
        .aclk    (         ),
        .aresetn (         ),
        .clk     (clk      ),
        .rst_n   (         )
    );

    age_matrix_8x8_if uif (clk);

    age_matrix_8x8 u_age_matrix_8x8 (
        .clk        (uif.clk),
        .req_pos_1  (uif.req_pos_1),
        .req_pos_2  (uif.req_pos_2),
        .item_valid (uif.item_valid),
        .oldest_vec (uif.oldest_vec)
    );

`ifdef DUMP_FSDB
    initial begin
        $display("===============================================");
        $display("Dumping FSDB waveforms");
        $fsdbAutoSwitchDumpfile(dump_wave_pkg::FSDB_LIMIT_SIZE, dump_wave_pkg::FSDB_FILENAME, dump_wave_pkg::FSDB_FILE_AMOUNT);
        $fsdbDumpvars(0, tb_age_matrix_8x8, "+all");
        $display("===============================================");
    end
`endif

    // 找第 1 个 0 的位置, 没有则返回 -1
    // direction: 0, LSB2MSB; 1, MSB2LSB
    function automatic int find_first_zero(input logic [ITEM_DEPTH-1:0] vec, bit direction);
        int idx;

        for (int i = 0; i < ITEM_DEPTH; i++) begin
            idx = direction ? (ITEM_DEPTH - 1 - i) : i;
            if (vec[idx] == 1'b0) begin
                return idx;
            end
        end
        return -1;
    endfunction

    // 1. 向年龄矩阵申请条目 (如果有足够空闲条目数量), 最多一拍 2 个请求
    //    req[0] = 1'b1 表示发起 0 号请求
    //    req[1] = 1'b1 表示发起 1 号请求
    // 2. 不允许指定请求申请条目的具体 onehot 位置, 只允许发起请求脉冲 (支持多拍连续背靠背),
    //    0 号请求总是申请 LSB2MSB 的第一个空闲条目,
    //    1 号请求总是申请 MSB2LSB 的第一个空闲条目
    task automatic req_item(input bit [1:0] req);

        logic [ITEM_DEPTH-1:0] req_pos_1;
        logic [ITEM_DEPTH-1:0] req_pos_2;

        // item 条目将满时不允许再有请求到达
        // 建议 rtl 设计的时候维护一个 valid_cnt, 这应该比用组合逻辑算划算 (参数化通用性也更好)
        if ($countbits(valid_shadow, 0) <= 1) begin
            $display("[ERROR] @%0t: 空闲条目数不足, 申请失败", $realtime);
            $display("        req = 0b%b, item_valid = 0b%b", req, valid_shadow);
            return;
        end

        req_pos_1 = req[0] ? ITEM_DEPTH'(1) << find_first_zero(valid_shadow, 1'b0) : '0;   // LSB2MSB
        req_pos_2 = req[1] ? ITEM_DEPTH'(1) << find_first_zero(valid_shadow, 1'b1) : '0;   // MSB2LSB

        valid_shadow = valid_shadow | req_pos_1 | req_pos_2;

        uif.drv_cb.req_pos_1 <= req_pos_1;
        uif.drv_cb.req_pos_2 <= req_pos_2;
        @(uif.drv_cb);

        uif.drv_cb.req_pos_1 <= '0;
        uif.drv_cb.req_pos_2 <= '0;

        // valid 滞后 req_pos 一拍, 与 RTL 注释的口径一致
        uif.drv_cb.item_valid <= valid_shadow;

    endtask


    initial begin
        uif.req_pos_1 = '0;
        uif.req_pos_2 = '0;
        uif.item_valid = '0;

        repeat(10) @(uif.drv_cb);

        req_item(.req(2'b11));
        req_item(.req(2'b11));
        req_item(.req(2'b11));
        req_item(.req(2'b11));
        req_item(.req(2'b11));
        req_item(.req(2'b11));


        repeat(100) @(posedge clk);
        $finish;
    end

endmodule

`default_nettype wire
