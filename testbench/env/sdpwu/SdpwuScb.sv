`ifndef _SDPWU_SCB_SV_
`define _SDPWU_SCB_SV_

// SDPWU_TOP 的 scoreboard: 用 page_table_model 算 Page Walk 的理想结果并比对
class SdpwuScb extends uvm_scoreboard;

    `uvm_component_utils(SdpwuScb)

    uvm_analysis_imp#(SdpwuItem, SdpwuScb) imp;

    page_table_model            pt_model;       // 由 env 注入
    logic [PA_WIDTH-1:0]        l1_base;        // 由 env 注入

    // sdmq_idx -> 本次 Page Walk 的 PA (start 握手时记录)
    logic [PA_WIDTH-1:0]        pa_of_idx [logic [SDMQ_IDX_WIDTH-1:0]];

    int start_cnt = 0;
    int mem_rd_cnt = 0;
    int finish_cnt = 0;
    int err_cnt = 0;

    function new(string name = "SdpwuScb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    function void write(SdpwuItem tr);
        SDPWU_FINISH_t exp;

        case (tr.kind)
            SDPWU_START_SEEN: begin
                start_cnt++;
                pa_of_idx[tr.sdmq_idx] = tr.pa;
            end

            SDPWU_MEM_RD: begin
                mem_rd_cnt++;
            end

            SDPWU_FINISH: begin
                finish_cnt++;
                if (!pa_of_idx.exists(tr.sdmq_idx)) begin
                    err_cnt++;
                    `uvm_error(
                        "SCB_IDX",
                        $sformatf("finish 的 sdmq_idx=%0d 没有对应的 start", tr.sdmq_idx)
                    )
                end
                else begin
                    exp = pt_model.expect_finish(l1_base, pa_of_idx[tr.sdmq_idx], tr.sdmq_idx);
                    if (tr.finish_item !== exp) begin
                        err_cnt++;
                        `uvm_error(
                            "SCB_FINISH",
                            $sformatf("sdmq_idx=%0d: got hit=%0b eid=%h tok=%h tokv=%h pfn=%h err=%b, exp hit=%0b eid=%h tok=%h tokv=%h pfn=%h err=%b",
                                      tr.sdmq_idx,
                                      tr.finish_item.hit, tr.finish_item.eid,
                                      tr.finish_item.token_id, tr.finish_item.token_value,
                                      tr.finish_item.s_pfn, tr.finish_item.err,
                                      exp.hit, exp.eid, exp.token_id, exp.token_value,
                                      exp.s_pfn, exp.err)
                        )
                    end
                end
            end

            default: begin
                err_cnt++;
                `uvm_error("SCB_KIND", $sformatf("unexpected item kind: %s", tr.kind.name()))
            end
        endcase
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);

        `uvm_info(
            "SCB",
            $sformatf("start=%0d mem_rd=%0d finish=%0d err=%0d",
                      start_cnt, mem_rd_cnt, finish_cnt, err_cnt),
            UVM_LOW
        )

        if (err_cnt != 0) begin
            `uvm_error("SCB", $sformatf("%0d 条比对错误", err_cnt))
        end
        else begin
            `uvm_info("SCB", "sdpwu 比对全部通过", UVM_LOW)
        end
    endfunction

endclass

`endif // _SDPWU_SCB_SV_
