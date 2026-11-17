`ifndef _SDECODER_SEQ_PKG_SVH_
`define _SDECODER_SEQ_PKG_SVH_

package sdecoder_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    typedef enum {
        SDIOR_WR,
        SDIOR_RD,
        SDTLB_CAM0_REQ,
        SDTLB_CAM1_REQ,
        SDECODER_WAIT
    } Sdecoder_Item_Kind_e;

    `include "SdecoderItem.sv"
    `include "seq/SdecoderSmokeSeq.sv"

endpackage

`endif // _SDECODER_SEQ_PKG_SVH_
