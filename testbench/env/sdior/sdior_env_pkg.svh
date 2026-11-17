`ifndef _SDIOR_ENV_PKG_SVH_
`define _SDIOR_ENV_PKG_SVH_

package sdior_env_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;
    import sdior_seq_pkg::*;
    import sdior_ral_pkg::*;

    `include "SdiorSqr.sv"
    `include "SdiorDrv.sv"
    `include "SdiorMon.sv"
    `include "SdiorScb.sv"
    `include "SdiorAgt.sv"
    `include "SdiorEnv.sv"

endpackage

`endif // _SDIOR_ENV_PKG_SVH_
