`ifndef _SDPWU_ENV_PKG_SVH_
`define _SDPWU_ENV_PKG_SVH_

package sdpwu_env_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;
    import page_table_pkg::*;
    import sdpwu_seq_pkg::*;

    `include "SdpwuSqr.sv"
    `include "SdpwuDrv.sv"
    `include "SdpwuMon.sv"
    `include "SdpwuScb.sv"
    `include "SdpwuAgt.sv"
    `include "SdpwuEnv.sv"

endpackage

`endif // _SDPWU_ENV_PKG_SVH_
