
package test_pkg;

    import uvm_pkg::*;
    import sdecoder_pkg::*;
    import sdecoder_seq_pkg::*;
    import sdecoder_env_pkg::*;
    import sdior_seq_pkg::*;
    import sdior_env_pkg::*;
    import sdtlb_seq_pkg::*;
    import sdtlb_env_pkg::*;
    import sdpwu_seq_pkg::*;
    import sdpwu_env_pkg::*;

    `include "sdecoder/SDecoderTestBase.sv"
    `include "sdior/SdiorTestBase.sv"
    `include "sdtlb/SdtlbTestBase.sv"
    `include "sdpwu/SdpwuTestBase.sv"

endpackage
