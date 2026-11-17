// 把探针接口绑到 sdtlb 模块上: 每个 sdtlb 实例内部会多出 u_sdtlb_if_probe_bind
// (tb_sdtlb 里路径是 dut.u_sdtlb.u_sdtlb_if_probe_bind; 以后 SDecoder 里是它自己实例化路径 + .u_sdtlb_if_probe_bind)
//
// 只做观测, 不影响 RTL.
bind sdtlb sdtlb_if_probe u_sdtlb_if_probe_bind (
    .clk                (clk),
    .rst_n              (rst_n),

    .cam0_req_en        (cam0_req_en),
    .cam0_req_pa        (cam0_req_pa),
    .cam0_hit           (cam0_hit),
    .cam0_hit_tag_item  (cam0_hit_tag_item),
    .cam0_hit_data_item (cam0_hit_data_item),

    .cam1_req_en        (cam1_req_en),
    .cam1_req_pa        (cam1_req_pa),
    .cam1_hit           (cam1_hit),
    .cam1_hit_tag_item  (cam1_hit_tag_item),
    .cam1_hit_data_item (cam1_hit_data_item),

    .fill_en            (fill_en),
    .fill_pa_base       (fill_pa_base),
    .fill_pa_up         (fill_pa_up),
    .fill_eid           (fill_eid),
    .fill_token_id      (fill_token_id),
    .fill_token_value   (fill_token_value),
    .fill_s_pfn         (fill_s_pfn),

    .inv_en             (inv_en),
    .inv_all            (inv_all),
    .inv_sel            (inv_sel),
    .inv_sel_pa         (inv_sel_pa)
);
