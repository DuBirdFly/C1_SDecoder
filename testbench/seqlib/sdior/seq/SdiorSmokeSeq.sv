`ifndef _SDIOR_SMOKE_SEQ_SV_
`define _SDIOR_SMOKE_SEQ_SV_

class SdiorSmokeSeq extends uvm_sequence#(SdiorItem);

    `uvm_object_utils(SdiorSmokeSeq)

    // RAL 寄存器句柄 (由 test 注入)
    uvm_reg IA;
    uvm_reg IS;
    uvm_reg PTBR;

    function new(string name = "SdiorSmokeSeq");
        super.new(name);
    endfunction

    task wr(uvm_reg rg, uvm_reg_data_t val);
        uvm_status_e status;
        rg.write(status, val, .parent(this));
        if (status != UVM_IS_OK) begin
            `uvm_error("SEQ_WR", $sformatf("%s write failed: %s", rg.get_name(), status.name()))
        end
    endtask

    task rd(uvm_reg rg, output uvm_reg_data_t val);
        uvm_status_e status;
        rg.read(status, val, .parent(this));
        if (status != UVM_IS_OK) begin
            `uvm_error("SEQ_RD", $sformatf("%s read failed: %s", rg.get_name(), status.name()))
        end
    endtask

    task body();
        uvm_reg_data_t rdata;

        // 复位后 PTBR = 0
        rd(PTBR, rdata);

        // IA 是 volatile, IS 复位后读回 0
        rd(IA, rdata);

        // PTBR 可读写: 字段 SDT_L1_BASE[47:4]
        wr(PTBR, 64'h0000_0000_0000_3000);
        rd(PTBR, rdata);
        if (rdata !== 64'h0000_0000_0000_3000) begin
            `uvm_error("SEQ_PTBR", $sformatf("PTBR 读回 0x%0h, 期望 0x3000", rdata))
        end

        // PTBR 低 4 位不属于字段, 写入后应被压掉
        wr(PTBR, 64'h0000_0000_0000_3011);
        rd(PTBR, rdata);
        if (rdata !== 64'h0000_0000_0000_3010) begin
            `uvm_error("SEQ_PTBR", $sformatf("PTBR 读回 0x%0h, 期望 0x3010 (低 4 位被压掉)", rdata))
        end

        // IA: 写任意值即触发
        wr(IA, 64'h0);

        // IS: 写 INV_SEL_PA = 18'h10, 触发 inv_sel 且存储下来
        wr(IS, 18'h10);

        // IS 读回 INV_SEL_PA 原值; IA 读回 0 (volatile)
        rd(IS, rdata);
        if (rdata !== 64'h10) begin
            `uvm_error("SEQ_IS", $sformatf("IS 读回 0x%0h, 期望 0x10", rdata))
        end
        rd(IA, rdata);
        if (rdata !== 64'h0) begin
            `uvm_error("SEQ_IA", $sformatf("IA 是 volatile, 期望读回 0, 实际 0x%0h", rdata))
        end

        // PTBR 不受置无效操作影响
        rd(PTBR, rdata);
    endtask

endclass

`endif // _SDIOR_SMOKE_SEQ_SV_
