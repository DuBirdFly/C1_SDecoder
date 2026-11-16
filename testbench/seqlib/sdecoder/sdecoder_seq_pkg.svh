`ifndef _SDECODER_SEQ_PKG_SVH_
`define _SDECODER_SEQ_PKG_SVH_

package sdecoder_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    typedef enum {
        SDEC_CFG_WR,
        SDEC_REQ,
        SDEC_RSP_READY,
        SDEC_WAIT
    } Sdecoder_Item_Kind_e;

    `include "SdecoderItem.sv"
    `include "SdecoderSmokeSeq.sv"

endpackage

`endif // _SDECODER_SEQ_PKG_SVH_
