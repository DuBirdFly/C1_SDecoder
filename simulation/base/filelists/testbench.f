// utility files
./testbench/utils/utils_pkg.svh
./testbench/utils/dump_wave_pkg.svh

// include directories for package includes
+incdir+./testbench/env
+incdir+./testbench/test
+incdir+./testbench/seqlib

// interface files
./testbench/top/interface/sdtlb_if.sv
./testbench/top/interface/sdecoder_if.sv

// UVM files
./testbench/inc/uvm_header.svh
./testbench/seqlib/sdecoder_seq_pkg.svh
./testbench/env/sdecoder_env_pkg.svh
./testbench/test/test_pkg.svh

// Testbench top files
./testbench/top/crg.sv
./testbench/top/tb_sdecoder.sv
./testbench/top/tb_sdtlb.sv
./testbench/top/tb_sdptw.sv
