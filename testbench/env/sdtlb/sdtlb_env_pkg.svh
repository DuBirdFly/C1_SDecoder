`ifndef _SDTLB_ENV_PKG_SVH_
`define _SDTLB_ENV_PKG_SVH_

package sdtlb_env_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;
    import sdtlb_seq_pkg::*;

    `include "SdtlbSqr.sv"
    `include "SdtlbDrv.sv"
    `include "SdtlbMon.sv"
    `include "SdtlbScb.sv"
    `include "SdtlbAgt.sv"
    `include "SdtlbEnv.sv"

endpackage

`endif // _SDTLB_ENV_PKG_SVH_
