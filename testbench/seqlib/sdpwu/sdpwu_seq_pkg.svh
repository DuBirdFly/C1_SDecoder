`ifndef _SDPWU_SEQ_PKG_SVH_
`define _SDPWU_SEQ_PKG_SVH_

package sdpwu_seq_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;

    // 事务类型
    typedef enum {
        SDPWU_PW_START,     // 发一次 Page Walk 请求 (driver 用)
        SDPWU_WAIT,         // 空等
        SDPWU_MEM_WR,       // 往存储器模型写一个条目 (布置页表)
        SDPWU_START_SEEN,   // monitor 观测到一次 start 握手
        SDPWU_MEM_RD,       // monitor 观测到一次访存读请求
        SDPWU_FINISH        // monitor 观测到 Page Walk 结束
    } Sdpwu_Item_Kind_e;

    `include "SdpwuItem.sv"
    `include "seq/SdpwuBaseSeq.sv"
    `include "seq/SdpwuSmokeSeq.sv"
    `include "seq/SdpwuTableSeq.sv"

endpackage

`endif // _SDPWU_SEQ_PKG_SVH_
