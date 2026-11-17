// utility files
./testbench/utils/utils_pkg.svh
./testbench/utils/dump_wave_pkg.svh

// include directories for package includes (按 <area>/sdecoder/ 的目录组织)
+incdir+./testbench/env/sdecoder
+incdir+./testbench/seqlib/sdecoder
+incdir+./testbench/env/sdior
+incdir+./testbench/env/sdtlb
+incdir+./testbench/env/sdpwu
+incdir+./testbench/model
+incdir+./testbench/ral/sdior
+incdir+./testbench/seqlib/sdior
+incdir+./testbench/seqlib/sdtlb
+incdir+./testbench/seqlib/sdpwu
+incdir+./testbench/test
+incdir+./testbench/test/sdecoder
+incdir+./testbench/test/sdtlb
+incdir+./testbench/test/sdpwu

// interface files
./testbench/top/interface/sdtlb_if.sv
./testbench/top/interface/sdtlb_if_probe.sv
./testbench/top/interface/sdpwu_if.sv
./testbench/top/interface/sdior_if.sv
./testbench/top/interface/sdecoder_if.sv
./testbench/top/interface/age_matrix_if.sv

// Testbench wrapper files
./testbench/top/wrapper/wrapper_sdtlb.sv
./testbench/top/interface/sdtlb_if_probe_bind.sv
./testbench/top/wrapper/wrapper_sdior.sv

// UVM files
./testbench/inc/uvm_header.svh
./testbench/seqlib/sdecoder/sdecoder_seq_pkg.svh
./testbench/seqlib/sdior/sdior_seq_pkg.svh
./testbench/model/page_table_pkg.svh
./testbench/seqlib/sdtlb/sdtlb_seq_pkg.svh
./testbench/seqlib/sdpwu/sdpwu_seq_pkg.svh
./testbench/env/sdecoder/sdecoder_env_pkg.svh
./testbench/ral/sdior/sdior_ral_pkg.svh
./testbench/env/sdior/sdior_env_pkg.svh
./testbench/env/sdtlb/sdtlb_env_pkg.svh
./testbench/env/sdpwu/sdpwu_env_pkg.svh
./testbench/test/test_pkg.svh

// Testbench top files
./testbench/top/crg.sv
./testbench/top/tb_sdtlb.sv
./testbench/top/tb_sdpwu_top.sv
./testbench/top/tb_sdecoder.sv
./testbench/top/tb_sdtlb_tag_item.sv
./testbench/top/tb_sdior.sv
./testbench/top/tb_age_matrix.sv
