class TestBase extends uvm_test;

    `uvm_component_utils(TestBase)

    // virtual apb_if apb_vif;
    // virtual axi_if axi_vif;

    // ApbEnv apbEnv;
    // ApbSeq apbSeq;

    extern         function      new(string name = "testBase", uvm_component parent);

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual function void start_of_simulation_phase(uvm_phase phase);
    extern virtual task          run_phase(uvm_phase phase);

endclass

function TestBase::new(string name = "testBase", uvm_component parent);
    super.new(name, parent);
endfunction

function void TestBase::build_phase(uvm_phase phase);
    super.build_phase(phase);

    // set_timeout(time timeout, bit overridable = 1)
    // Specifies the timeout for the simulation. Default is <`UVM_DEFAULT_TIMEOUT>
    uvm_root::get().set_timeout(1_000_000 * 3, 1);

    // if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb", apb_vif))
    //     `uvm_fatal("NOVIF", "No Interface Specified")

    // if (!uvm_config_db#(virtual axi_if)::get(this, "", "axi", axi_vif))
    //     `uvm_fatal("NOVIF", "No Interface Specified")

    // apbEnv = ApbEnv::type_id::create("apbEnv", this);
    // apbSeq = ApbSeq::type_id::create("apbSeq", this);

endfunction

function void TestBase::start_of_simulation_phase(uvm_phase phase);

    // 配置 uvm_info 可见性
    // apbEnv.axiSlvRef.set_report_verbosity_level(UVM_INFO);

    // 打印注册到 uvm_factory 的类信息 (没有 type names 的不会被打印)
    uvm_pkg::uvm_factory::get().print();

    // 打印注册到 uvm_factory 的对象/变量 (hierarchy)
    uvm_root::get().print_topology();
endfunction

task TestBase::run_phase(uvm_phase phase);
    phase.raise_objection(this);
    uvm_top.set_timeout(100us, 0);
    $timeformat(-9, 0, "ns", 6);
    $display("Running test...");

    for (int i = 0; i < 10; i++) begin
        #10ns;
        $display("@%0t: i = %0d", $time(), i);
    end

    $display("Test completed.");
    phase.drop_objection(this);
endtask
