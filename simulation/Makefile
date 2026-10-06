######################################################
# USER CONFIG (single test case)
TB_TOP ?= tb_top
TESTNAME ?= TestBase
DUMP_WAVE ?= 0

######################################################
# GLOBAL CONFIG
REPO_ROOT = ../../..
RUN_DIR_NAME ?= run_single_testcase
RUN_DIR ?= $(RUN_DIR_NAME)/$(TB_TOP).$(TESTNAME)

######################################################
.PHONY: base vcs simv simv_only verdi all clean

######################################################
base:
	@echo "创建仿真专属文件夹: $(RUN_DIR)"
	@mkdir -p $(RUN_DIR)
	@mkdir -p $(RUN_DIR)
	@mkdir -p $(RUN_DIR)/log
	@mkdir -p $(RUN_DIR)/output
	@mkdir -p $(RUN_DIR)/output/wave
	@cd $(RUN_DIR) && ln -sf $(REPO_ROOT)/simulation/base
	@cd $(RUN_DIR) && ln -sf $(REPO_ROOT)/rtl
	@cd $(RUN_DIR) && ln -sf $(REPO_ROOT)/testbench
	@python3 ../script/merge_all_filelist.py \
		-src_filelist_dir ./base/filelists \
		-src_filelist_name all.f \
		-dst_merged_filelist_path $(RUN_DIR)/output/merged.f \
		-log $(RUN_DIR)/log/merge_all_filelist/merge.log

######################################################
# note: 指定 -o 包括了 simv 和 simv.daidir
# note: 指定 -Mdir 包括了 csrc 和 vc_hdrs.h

# VCS  = vcs -full64 -LDFLAGS -Wl,--no-as-needed
VCS  = vcs -full64
VCS += -file ./base/option/compile_base.f
VCS += -file ./base/option/compile_define.f
VCS += -file ./base/option/compile_uvm.f
VCS += -file ./output/merged.f
VCS += +optconfigfile+./base/option/vcs.cfg
VCS += -l ./log/vcs.log
VCS += -o ./output/simv
VCS += -Mdir=./output/csrc
VCS += -top $(TB_TOP)

ifeq ($(DUMP_WAVE), 1)
	VCS += +define+DUMP_FSDB
endif

vcs: base
	cd $(RUN_DIR) && $(VCS)

######################################################
SIMV  = ./output/simv +UVM_TESTNAME=$(TESTNAME)
SIMV += -f ./base/option/simulate_base.f
SIMV += -l ./log/simv.log
SIMV += -k ./output/ucli.key

simv_only:
	cd $(RUN_DIR) && $(SIMV)

simv: vcs
	$(MAKE) simv_only

######################################################
clean:
	cd $(RUN_DIR) && find . -maxdepth 1 -type l -delete

######################################################
all: simv
	$(MAKE) clean

######################################################
VERDI  = verdi
VERDI += -ssf $(abspath $(RUN_DIR)/output/wave/novas.vf)
VERDI += -dbdir ./output/simv.daidir
VERDI += -logdir ./log/verdiLog
VERDI += -rcFile $(REPO_ROOT)/simulation/base/novas/novas.rc
VERDI += -guiConf $(REPO_ROOT)/simulation/base/novas/novas.conf

verdi:
	@mkdir -p $(RUN_DIR)
	cd $(RUN_DIR) && $(VERDI) &
