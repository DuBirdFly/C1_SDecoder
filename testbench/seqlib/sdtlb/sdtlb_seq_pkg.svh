`ifndef _SDTLB_SEQ_PKG_SVH_
`define _SDTLB_SEQ_PKG_SVH_

package sdtlb_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    `include "SdtlbItem.sv"
    `include "seq/SdtlbBaseSeq.sv"
    `include "seq/SdtlbSmokeSeq.sv"
    `include "seq/SdtlbSegSeq.sv"
    `include "seq/SdtlbInvSeq.sv"
    `include "seq/SdtlbDualSeq.sv"
    `include "seq/SdtlbRotateSeq.sv"

endpackage

`endif // _SDTLB_SEQ_PKG_SVH_
