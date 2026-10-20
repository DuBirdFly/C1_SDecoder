class TestSamePa extends uvm_test;

    `uvm_component_utils(TestSamePa)

    SdecoderEnv sdecoder_env;

    extern         function      new(string name = "TestSamePa", uvm_component parent);

    extern virtual function void build_phase(uvm_phase phase);
    extern virtual task          run_phase(uvm_phase phase);

endclass

function TestSamePa::new(string name = "TestSamePa", uvm_component parent);
    super.new(name, parent);
endfunction

function void TestSamePa::build_phase(uvm_phase phase);
    super.build_phase(phase);

    uvm_root::get().set_timeout(1_000_000 * 3, 1);

    sdecoder_env = SdecoderEnv::type_id::create("sdecoder_env", this);
endfunction

task TestSamePa::run_phase(uvm_phase phase);
    SdecoderSamePaSeq seq;

    phase.raise_objection(this);
    uvm_top.set_timeout(100us, 0);
    $timeformat(-9, 0, "ns", 6);

    seq = SdecoderSamePaSeq::type_id::create("seq");
    seq.start(sdecoder_env.agt.sqr);

    #20000ns;

    if (sdecoder_env.agt.mon.rsp_count != 5) begin
        `uvm_error("RSP_COUNT",
                   $sformatf("got %0d responses, expected 5", sdecoder_env.agt.mon.rsp_count))
    end
    if (sdecoder_env.agt.mon.err_count != 0) begin
        `uvm_error("RSP_ERROR", $sformatf("%0d response check errors", sdecoder_env.agt.mon.err_count))
    end
    // 4 次 page miss, 每次 L1+L2 两次 AR, 共 8 次; 第 5 个应在 fill 后命中, 不再发 AR
    if (sdecoder_env.page_table_model.ar_count != 8) begin
        `uvm_error("AR_COUNT",
                   $sformatf("got %0d table ARs, expected 8", sdecoder_env.page_table_model.ar_count))
    end

    `uvm_info("TEST", "Sdecoder same-PA done", UVM_LOW)
    phase.drop_objection(this);
endtask
