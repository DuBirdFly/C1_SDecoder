`ifndef _SDIOR_SEQ_PKG_SVH_
`define _SDIOR_SEQ_PKG_SVH_

package sdior_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    typedef enum {
        SDIOR_WR,
        SDIOR_RD,
        SDIOR_WAIT,
        SDIOR_INV       // monitor 观测到的置无效脉冲, 只由 monitor 发, driver 不会用到
    } Sdior_Item_Kind_e;

    `include "SdiorItem.sv"
    `include "SdiorSmokeSeq.sv"

endpackage

`endif // _SDIOR_SEQ_PKG_SVH_
