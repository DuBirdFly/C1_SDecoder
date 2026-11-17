`ifndef _SDTLB_BASE_SEQ_SV_
`define _SDTLB_BASE_SEQ_SV_

// SDTLB 序列基类: 提供 req / fill / inv / wait 的封装, 以及地址拼装的小工具
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

    // 单端口 (cam0) 查表请求
    task req0(input logic [PA_WIDTH-1:0] pa);
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDTLB_REQ;
        tr.cam0_req_en = 1'b1;
        tr.cam0_req_pa = pa;
        tr.cam1_req_en = 1'b0;
        tr.cam1_req_pa = '0;
        finish_item(tr);
    endtask

    // 单端口 (cam1) 查表请求
    task req1(input logic [PA_WIDTH-1:0] pa);
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDTLB_REQ;
        tr.cam0_req_en = 1'b0;
        tr.cam0_req_pa = '0;
        tr.cam1_req_en = 1'b1;
        tr.cam1_req_pa = pa;
        finish_item(tr);
    endtask

    // 两端口同拍查表
    task req2(input logic [PA_WIDTH-1:0] pa0, input logic [PA_WIDTH-1:0] pa1);
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDTLB_REQ;
        tr.cam0_req_en = 1'b1;
        tr.cam0_req_pa = pa0;
        tr.cam1_req_en = 1'b1;
        tr.cam1_req_pa = pa1;
        finish_item(tr);
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
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind             = SDTLB_FILL;
        tr.fill_en          = 1'b1;
        tr.fill_pa_base     = base;
        tr.fill_pa_up       = up;
        tr.fill_eid         = eid;
        tr.fill_token_id    = tok;
        tr.fill_token_value = tokv;
        tr.fill_s_pfn       = pfn;
        finish_item(tr);
    endtask

    // 同一拍: 装填 + 置无效全部 (验证置无效优先)
    task fill_and_inv_all(
        input logic [PA_BASE_WIDTH-1:0]              base,
        input logic [PA_UP_WIDTH-1:0]                up,
        input logic [EID_WIDTH-1:0]                  eid,
        input logic [TOKEN_ID_WIDTH-1:0]             tok,
        input logic [TOKEN_VALUE_WIDTH-1:0]          tokv,
        input logic [S_PFN_WIDTH-1:0]                pfn
    );
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind             = SDTLB_FILL;
        tr.fill_en          = 1'b1;
        tr.fill_pa_base     = base;
        tr.fill_pa_up       = up;
        tr.fill_eid         = eid;
        tr.fill_token_id    = tok;
        tr.fill_token_value = tokv;
        tr.fill_s_pfn       = pfn;
        tr.inv_all          = 1'b1;
        finish_item(tr);
    endtask

    task inv_sel(input logic [PA_BASE_WIDTH-1:0] pa);
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind       = SDTLB_INV;
        tr.inv_sel    = 1'b1;
        tr.inv_sel_pa = pa;
        finish_item(tr);
    endtask

    task inv_all();
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind    = SDTLB_INV;
        tr.inv_all = 1'b1;
        finish_item(tr);
    endtask

    task wait_cycles(input int unsigned n);
        SdtlbItem tr;
        tr = SdtlbItem::type_id::create("tr");
        start_item(tr);
        tr.kind        = SDTLB_WAIT;
        tr.wait_cycles = n;
        finish_item(tr);
    endtask

endclass

`endif // _SDTLB_BASE_SEQ_SV_
