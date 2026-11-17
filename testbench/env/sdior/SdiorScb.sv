`ifndef _SDIOR_SCB_SV_
`define _SDIOR_SCB_SV_

// sdior 的 scoreboard (RAL 版)
//   期望值不再由 scb 自己维护, 全部取自 RAL 的 mirror:
//     SDIOR_RD : 读回值必须等于对应寄存器的 mirror 值 (IA 是 volatile, 按设计读回恒 0)
//     SDIOR_INV: inv_sel 那一拍的 inv_sel_pa 必须等于 IS.INV_SEL_PA 的 mirror
//     SDIOR_WR : 只计数; mirror 由 uvm_reg_predictor 根据总线事务更新
//   check_phase: 打印访问次数并汇总比对错误
class SdiorScb extends uvm_scoreboard;

    `uvm_component_utils(SdiorScb)

    uvm_analysis_imp#(SdiorItem, SdiorScb) imp;

    sdior_reg_block reg_model;      // 由 env 注入

    int wr_cnt = 0;
    int rd_cnt = 0;
    int inv_all_cnt = 0;
    int inv_sel_cnt = 0;
    int err_cnt = 0;

    function new(string name = "SdiorScb", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        imp = new("imp", this);
    endfunction

    function void write(SdiorItem tr);
        uvm_reg        rg;
        uvm_reg_data_t exp;

        case (tr.kind)
            SDIOR_WR: begin
                wr_cnt++;
                // mirror 由 uvm_reg_predictor 更新, 这里不建模
            end

            SDIOR_RD: begin
                rd_cnt++;
                rg = reg_model.default_map.get_reg_by_offset(tr.addr * (SDIOR_DATA_WIDTH / 8));
                if (rg == null) begin
                    err_cnt++;
                    `uvm_error("SCB_ADDR", $sformatf("读地址 0x%0h 在 RAL 里找不到对应寄存器", tr.addr))
                end
                else begin
                    // IA 是 volatile (写即触发, 读回恒 0); 其余寄存器和 mirror 比对
                    if (rg == reg_model.IA) begin
                        exp = 64'h0;
                    end
                    else begin
                        exp = rg.get_mirrored_value();
                    end

                    if (tr.rdata !== exp) begin
                        err_cnt++;
                        `uvm_error(
                            "SCB_RD",
                            $sformatf("%s read 0x%0h, mirror 0x%0h", rg.get_name(), tr.rdata, exp)
                        )
                    end
                end
            end

            SDIOR_INV: begin
                if (!tr.inv_en) begin
                    err_cnt++;
                    `uvm_error("SCB_INV", "置无效脉冲没有带 inv_en")
                end
                if (tr.inv_all) begin
                    inv_all_cnt++;
                end
                if (tr.inv_sel) begin
                    inv_sel_cnt++;
                    // 期望值 = IS.INV_SEL_PA 的 mirror (inv_sel_pa 就是 PA[47:30])
                    exp = reg_model.IS.get_field_by_name("INV_SEL_PA").get_mirrored_value();
                    if (tr.inv_sel_pa !== exp) begin
                        err_cnt++;
                        `uvm_error(
                            "SCB_INV_SEL_PA",
                            $sformatf("inv_sel_pa = 0x%0h, expected 0x%0h", tr.inv_sel_pa, exp)
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
            $sformatf("wr=%0d rd=%0d inv_all=%0d inv_sel=%0d err=%0d",
                      wr_cnt, rd_cnt, inv_all_cnt, inv_sel_cnt, err_cnt),
            UVM_LOW
        )

        if (err_cnt != 0) begin
            `uvm_error("SCB", $sformatf("%0d 条比对错误", err_cnt))
        end
        else begin
            `uvm_info("SCB", "sdior 比对全部通过", UVM_LOW)
        end
    endfunction

endclass

`endif // _SDIOR_SCB_SV_
