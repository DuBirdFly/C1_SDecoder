// SDecoder smoke 用例 (骨架)
//   旧版的响应计数 (rsp_count == 11) 等硬编码检查已删除, 这里只留 build / run 框架
class SDecoderTestBase extends uvm_test;

    `uvm_component_utils(SDecoderTestBase)

    SdecoderEnv sdecoder_env;

    extern         function      new(string name = "SDecoderTestBase", uvm_component parent);

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void start_of_simulation_phase(uvm_phase phase);
    extern virtual task          run_phase(uvm_phase phase);

endclass

function SDecoderTestBase::new(string name = "SDecoderTestBase", uvm_component parent);
    super.new(name, parent);
endfunction

function void SDecoderTestBase::build_phase(uvm_phase phase);
    super.build_phase(phase);

    // set_timeout(time timeout, bit overridable = 1)
    // Specifies the timeout for the simulation. Default is <`UVM_DEFAULT_TIMEOUT>
    uvm_root::get().set_timeout(1_000_000 * 3, 1);

    sdecoder_env = SdecoderEnv::type_id::create("sdecoder_env", this);
endfunction

function void SDecoderTestBase::start_of_simulation_phase(uvm_phase phase);

    // 打印注册到 uvm_factory 的类信息 (没有 type names 的不会被打印)
    uvm_pkg::uvm_factory::get().print();

    // 打印注册到 uvm_factory 的对象/变量 (hierarchy)
    uvm_root::get().print_topology();
endfunction

task SDecoderTestBase::run_phase(uvm_phase phase);
    phase.raise_objection(this);
    uvm_top.set_timeout(100us, 0);
    $timeformat(-9, 0, "ns", 6);

    // TODO: sdecoder_if 与 env 定稿后, 在这里启动 smoke 序列并检查结果
    `uvm_info("TEST", "Sdecoder smoke skeleton: TODO", UVM_LOW)

    phase.drop_objection(this);
endtask
