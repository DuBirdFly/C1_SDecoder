`ifndef _SDIOR_REG_ADAPTER_SV_
`define _SDIOR_REG_ADAPTER_SV_

// RAL <-> sdior 总线的适配器
//   uvm_reg_bus_op 的 addr 是 map 偏移 (字节), 总线侧用寄存器序号, 这里做折算
class sdior_reg_adapter extends uvm_reg_adapter;

    `uvm_object_utils(sdior_reg_adapter)

    localparam int unsigned ADDR_UNIT = SDIOR_DATA_WIDTH / 8;   // 一个寄存器 = 8 字节

    function new(string name = "sdior_reg_adapter");
        super.new(name);
        supports_byte_enable = 0;
        provides_responses   = 1;       // driver 会 put_response, bus2reg 拿响应里的读回数据
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        SdiorItem tr;
        tr = SdiorItem::type_id::create("tr");
        tr.kind  = (rw.kind == UVM_WRITE) ? SDIOR_WR : SDIOR_RD;
        tr.addr  = rw.addr / ADDR_UNIT;
        tr.wdata = rw.data;
        return tr;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        SdiorItem tr;
        if (!$cast(tr, bus_item)) begin
            `uvm_fatal(get_type_name(), "bus2reg: $cast fail")
        end
        rw.kind   = (tr.kind == SDIOR_WR) ? UVM_WRITE : UVM_READ;
        rw.addr   = tr.addr * ADDR_UNIT;
        rw.data   = (tr.kind == SDIOR_WR) ? tr.wdata : tr.rdata;
        rw.status = UVM_IS_OK;
    endfunction

endclass

`endif // _SDIOR_REG_ADAPTER_SV_
