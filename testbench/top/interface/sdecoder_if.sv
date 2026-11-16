// SDecoder 顶层接口 (占位)
//
// SDecoder 顶层还没实现, 旧接口 (单路 req_* / rsp_* + AXI 风格 tw_* 读表 + cfg) 已经和现在的
// 设计方案对不上, 所以这里只留 clk / rst_n 与两个 clocking 骨架.
//
// TODO: 按设计方案 "接口信号" 一节补端口信号:
//   cam0 / cam1 请求 (req_en / req_pa) 与响应 (hit / sla / eid / token_id / token_value / err)
//   sdmq_rsp (valid / ready / id / eid / token_id / token_value / sla / err / flushed)
//   pw_mem_raddr / pw_mem_rdata (Page Walk 访存, id / addr / data / err)
//   ior (wen / waddr / wdata / raddr / rdata) 与异常统计输出
interface sdecoder_if
import sdecoder_pkg::*;
(
    input  logic clk,
    input  logic rst_n
);

    timeunit      1ps;
    timeprecision 1ps;

    // TODO: 端口信号待补

    clocking drv @(posedge clk);
        default input #1 output #1;
    endclocking

    clocking mon @(posedge clk);
        default input #1step;
    endclocking

endinterface
