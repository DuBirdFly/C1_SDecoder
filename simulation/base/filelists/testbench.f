// utility files
./testbench/utils/utils_pkg.svh
./testbench/utils/dump_wave_pkg.svh

// UVM files
./testbench/inc/uvm_header.sv

// interface files
./testbench/top/interface/sdtlb_if.sv
./testbench/top/interface/sdecoder_if.sv

// sequence library
./testbench/test/seqlib/sdecoder_seq_lib.sv

// environment
./testbench/env/sdecoder_sqr.sv
./testbench/env/sdecoder_drv.sv
./testbench/env/sdecoder_mon.sv
./testbench/env/sdecoder_agt.sv
./testbench/env/sdecoder_env.sv

// tests
./testbench/test/smoke/TestBase.sv
./testbench/test/regress/TestRegress.sv

// Testbench top files
./testbench/top/crg.sv
./testbench/top/tb_sdecoder.sv
./testbench/top/tb_sdtlb.sv
./testbench/top/tb_sdptw.sv
./testbench/top/tb_sdior.sv
./testbench/top/tb_syn_fifo.sv
