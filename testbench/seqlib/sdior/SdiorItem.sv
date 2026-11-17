`ifndef _SDIOR_ITEM_SV_
`define _SDIOR_ITEM_SV_

// sdior 的寄存器访问事务
//   SDIOR_WR: 写 cfg_addr / cfg_wdata
//   SDIOR_RD: 读 cfg_addr, 读回值放在 rdata
//   SDIOR_WAIT: 空等 wait_cycles 拍
//   SDIOR_INV:  monitor 观测到的置无效脉冲 (inv_all / inv_sel / inv_sel_pa)
class SdiorItem extends uvm_sequence_item;

    `uvm_object_utils_begin(SdiorItem)
        `uvm_field_enum(Sdior_Item_Kind_e, kind,       UVM_ALL_ON)
        `uvm_field_int (addr,                          UVM_ALL_ON)
        `uvm_field_int (wdata,                         UVM_ALL_ON)
        `uvm_field_int (rdata,                         UVM_ALL_ON)
        `uvm_field_int (wait_cycles,                   UVM_ALL_ON)
        `uvm_field_int (inv_all,                       UVM_ALL_ON)
        `uvm_field_int (inv_sel,                       UVM_ALL_ON)
        `uvm_field_int (inv_sel_pa,                    UVM_ALL_ON)
    `uvm_object_utils_end

    rand Sdior_Item_Kind_e              kind;

    // 读写
    rand logic [SDIOR_ADDR_WIDTH-1:0]   addr;
    rand logic [SDIOR_DATA_WIDTH-1:0]   wdata;
    logic [SDIOR_DATA_WIDTH-1:0]        rdata;      // 读回值 (driver / monitor 回填)

    // 置无效
    logic                               inv_all;
    logic                               inv_sel;
    logic [PA_BASE_WIDTH-1:0]           inv_sel_pa;

    // 等待
    rand int unsigned                   wait_cycles;

    function new(string name = "SdiorItem");
        super.new(name);
    endfunction

endclass

`endif // _SDIOR_ITEM_SV_
