`ifndef _SDTLB_SEQ_PKG_SVH_
`define _SDTLB_SEQ_PKG_SVH_

package sdtlb_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    // 事务类型: 查表请求 / 装填 / 置无效 / 空等
    typedef enum {
        SDTLB_REQ,      // 查表请求 (cam0 / cam1 可同拍)
        SDTLB_FILL,     // 装填一个条目
        SDTLB_INV,      // 置无效 (inv_all 或按地址 inv_sel)
        SDTLB_WAIT      // 空等 wait_cycles 拍
    } Sdtlb_Item_Kind_e;

    `include "SdtlbItem.sv"
    `include "SdtlbBaseSeq.sv"
    `include "SdtlbSmokeSeq.sv"
    `include "SdtlbSegSeq.sv"
    `include "SdtlbInvSeq.sv"
    `include "SdtlbDualSeq.sv"
    `include "SdtlbRotateSeq.sv"

endpackage

`endif // _SDTLB_SEQ_PKG_SVH_
