`ifndef _SDTLB_BASE_SEQ_SV_
`define _SDTLB_BASE_SEQ_SV_

// SDTLB 序列基类: 提供 req / fill / inv / wait 的封装, 以及地址拼装的小工具
//   事务不再用 kind 区分, 而是由各端口使能描述: 一个 item 可以同时开多个使能
//   (如查表 + 置无效同拍), 由 driver 用 fork-join 并行驱动
class SdtlbBaseSeq extends uvm_sequence#(SdtlbItem);

    `uvm_object_utils(SdtlbBaseSeq)

    function new(string name = "SdtlbBaseSeq");
        super.new(name);
    endfunction

    // gen_pa: 拼查表地址 {段高位 PA[47:35], 段内页号 PA[34:30], 页内偏移 PA[29:0]}
    // 只打 PA[47] = 0 的地址 (SDecoder 只处理 Mem 空间)
    function automatic logic [PA_WIDTH-1:0] gen_pa(
        input logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0]  high,
        input logic [PA_UP_WIDTH-1:0]                idx,
        input logic [PA_WIDTH-PA_BASE_WIDTH-1:0]     offset = '0
    );
        return {high, idx, offset};
    endfunction

    // gen_pa_base: 装填用的段基地址 PA[47:30] = {高位, 页号}
    function automatic logic [PA_BASE_WIDTH-1:0] gen_pa_base(
        input logic [PA_BASE_WIDTH-PA_UP_WIDTH-1:0]  high,
        input logic [PA_UP_WIDTH-1:0]                idx
    );
        return {high, idx};
    endfunction

    // ----------------------------------------------------------------
    // 通用用法: 先 new_item(), 再用 set_* 配置本次要发的端口 (可任意组合),
    // 最后 send() 提交. 单类型 / 常用双类型另有下面的短封装, 但新增组合不需要新 task.
    // ----------------------------------------------------------------

    // 新建一个 item: 使能和载荷全部清 0
    // 载荷也要清, 否则没用到的字段是 X, 会被 driver 原样打进 DUT
    protected function SdtlbItem new_item();
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        tr.cam0_req_en      = 1'b0;
        tr.cam0_req_pa      = '0;
        tr.cam1_req_en      = 1'b0;
        tr.cam1_req_pa      = '0;
        tr.fill_en          = 1'b0;
        tr.fill_pa_base     = '0;
        tr.fill_pa_up       = '0;
        tr.fill_eid         = '0;
        tr.fill_token_id    = '0;
        tr.fill_token_value = '0;
        tr.fill_s_pfn       = '0;
        tr.inv_en           = 1'b0;
        tr.inv_all          = 1'b0;
        tr.inv_sel          = 1'b0;
        tr.inv_sel_pa       = '0;
        tr.wait_cycles_en   = 1'b0;
        tr.wait_cycles      = 0;
        return tr;
    endfunction

    function void set_cam0(SdtlbItem tr, input logic [PA_WIDTH-1:0] pa);
        tr.cam0_req_en = 1'b1;
        tr.cam0_req_pa = pa;
    endfunction

    function void set_cam1(SdtlbItem tr, input logic [PA_WIDTH-1:0] pa);
        tr.cam1_req_en = 1'b1;
        tr.cam1_req_pa = pa;
    endfunction

    function void set_fill(
        SdtlbItem tr,
        input logic [PA_BASE_WIDTH-1:0]              base,
        input logic [PA_UP_WIDTH-1:0]                up,
        input logic [EID_WIDTH-1:0]                  eid,
        input logic [TOKEN_ID_WIDTH-1:0]             tok,
        input logic [TOKEN_VALUE_WIDTH-1:0]          tokv,
        input logic [S_PFN_WIDTH-1:0]                pfn
    );
        tr.fill_en          = 1'b1;
        tr.fill_pa_base     = base;
        tr.fill_pa_up       = up;
        tr.fill_eid         = eid;
        tr.fill_token_id    = tok;
        tr.fill_token_value = tokv;
        tr.fill_s_pfn       = pfn;
    endfunction

    function void set_inv_sel(SdtlbItem tr, input logic [PA_BASE_WIDTH-1:0] inv_pa);
        tr.inv_en     = 1'b1;
        tr.inv_all    = 1'b0;
        tr.inv_sel    = 1'b1;
        tr.inv_sel_pa = inv_pa;
    endfunction

    function void set_inv_all(SdtlbItem tr);
        tr.inv_en     = 1'b1;
        tr.inv_all    = 1'b1;
        tr.inv_sel    = 1'b0;
        tr.inv_sel_pa = '0;
    endfunction

    function void set_wait(SdtlbItem tr, input int unsigned n);
        tr.wait_cycles_en = 1'b1;
        tr.wait_cycles    = n;
    endfunction

    // 提交 item (start_item / finish_item)
    task send(SdtlbItem tr);
        start_item(tr);
        finish_item(tr);
    endtask

    // ----------------------------------------------------------------
    // 常用组合的短封装 (内部与 set_* + send 等价)
    // ----------------------------------------------------------------

    // 查表请求: 两个端口各自带使能, 可以只发一个端口, 也可以同拍发两个
    task cam_req(
        input bit                  cam0_en = 1'b0,
        input logic [PA_WIDTH-1:0] cam0_pa = '0,
        input bit                  cam1_en = 1'b0,
        input logic [PA_WIDTH-1:0] cam1_pa = '0
    );
        SdtlbItem tr;
        tr = new_item();
        if (cam0_en) begin
            set_cam0(tr, cam0_pa);
        end
        if (cam1_en) begin
            set_cam1(tr, cam1_pa);
        end
        send(tr);
    endtask

    task fill(
        input logic [PA_BASE_WIDTH-1:0]              base,
        input logic [PA_UP_WIDTH-1:0]                up,
        input logic [EID_WIDTH-1:0]                  eid,
        input logic [TOKEN_ID_WIDTH-1:0]             tok,
        input logic [TOKEN_VALUE_WIDTH-1:0]          tokv,
        input logic [S_PFN_WIDTH-1:0]                pfn
    );
        SdtlbItem tr;
        tr = new_item();
        set_fill(tr, base, up, eid, tok, tokv, pfn);
        send(tr);
    endtask

    task inv_sel(input logic [PA_BASE_WIDTH-1:0] pa);
        SdtlbItem tr;
        tr = new_item();
        set_inv_sel(tr, pa);
        send(tr);
    endtask

    task inv_all();
        SdtlbItem tr;
        tr = new_item();
        set_inv_all(tr);
        send(tr);
    endtask

    task wait_cycles(input int unsigned n);
        SdtlbItem tr;
        tr = new_item();
        set_wait(tr, n);
        send(tr);
    endtask

endclass

`endif // _SDTLB_BASE_SEQ_SV_
