// sdior smoke 用例: 跑 SdiorSmokeSeq 并检查 monitor / scoreboard 的结果
class SdiorTestBase extends uvm_test;

    `uvm_component_utils(SdiorTestBase)

    SdiorEnv sdior_env;

    extern         function      new(string name = "SdiorTestBase", uvm_component parent);

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task          run_phase(uvm_phase phase);

endclass

function SdiorTestBase::new(string name = "SdiorTestBase", uvm_component parent);
    super.new(name, parent);
endfunction

function void SdiorTestBase::build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_root::get().set_timeout(1_000_000 * 3, 1);
    sdior_env = SdiorEnv::type_id::create("sdior_env", this);
endfunction

task SdiorTestBase::run_phase(uvm_phase phase);
    SdiorSmokeSeq seq;

    phase.raise_objection(this);
    uvm_top.set_timeout(100us, 0);
    $timeformat(-9, 0, "ns", 6);

    seq = SdiorSmokeSeq::type_id::create("seq");
    // 把 RAL 的寄存器句柄注入序列
    seq.IA   = sdior_env.reg_model.IA;
    seq.IS   = sdior_env.reg_model.IS;
    seq.PTBR = sdior_env.reg_model.PTBR;
    seq.start(sdior_env.agt.sqr);

    // 等最后一个事务的 monitor 采样与 scoreboard 比对完成
    #1000ns;

    // 计数与检查都在 SdiorScb 里 (check_phase 报错)
    `uvm_info("TEST", "Sdior smoke done", UVM_LOW)
    phase.drop_objection(this);
endtask
