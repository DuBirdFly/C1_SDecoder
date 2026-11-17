`ifndef _SDIOR_REG_BLOCK_SV_
`define _SDIOR_REG_BLOCK_SV_

// sdior 的 RAL 模型 (位域见设计方案 "可配置的寄存器")
//   SDecoder_IA   : TRIGGER     64b @ lsb 0, WO, volatile, 写即触发置无效, 读回 0
//   SDecoder_IS   : INV_SEL_PA  18b @ lsb 0, RW, 写即触发 + 存储, 可读回
//   SDecoder_PTBR : SDT_L1_BASE 44b @ lsb 4, RW
//
// 注意: 总线地址是"寄存器序号" (0 / 1 / 2), 而 RAL 的 map 偏移按字节算,
// 所以这里按 8 字节步进放寄存器, adapter 里再折算成序号.
class sdior_reg_block extends uvm_reg_block;

    `uvm_object_utils(sdior_reg_block)

    uvm_reg IA;
    uvm_reg IS;
    uvm_reg PTBR;

    function new(string name = "sdior_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        uvm_reg_field f;

        default_map = create_map("default_map", 'h0, SDIOR_DATA_WIDTH / 8, UVM_LITTLE_ENDIAN);

        // SDecoder_IA: 写即触发, 数据不参与译码 (占位 64b), 读回恒 0
        IA = new("SDecoder_IA", SDIOR_DATA_WIDTH, UVM_NO_COVERAGE);
        IA.configure(this, null, "");
        f = new("TRIGGER");
        f.configure(IA, 64, 0, "WO", 1, '0, 1, 0, 0);
        default_map.add_reg(IA, 'h0, "RW");

        // SDecoder_IS: 写即触发置无效, 同时存储 INV_SEL_PA[47:30]
        IS = new("SDecoder_IS", SDIOR_DATA_WIDTH, UVM_NO_COVERAGE);
        IS.configure(this, null, "");
        f = new("INV_SEL_PA");
        f.configure(IS, 18, 0, "RW", 0, '0, 1, 0, 0);
        default_map.add_reg(IS, SDIOR_DATA_WIDTH / 8, "RW");

        // SDecoder_PTBR: 一级表基地址, 字段 SDT_L1_BASE[47:4] 在字的 [47:4]
        PTBR = new("SDecoder_PTBR", SDIOR_DATA_WIDTH, UVM_NO_COVERAGE);
        PTBR.configure(this, null, "");
        f = new("SDT_L1_BASE");
        f.configure(PTBR, 44, SDIOR_PTBR_LSB, "RW", 0, '0, 1, 0, 0);
        default_map.add_reg(PTBR, 2 * (SDIOR_DATA_WIDTH / 8), "RW");

        lock_model();
    endfunction

endclass

`endif // _SDIOR_REG_BLOCK_SV_
