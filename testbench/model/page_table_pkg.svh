`ifndef _PAGE_TABLE_PKG_SVH_
`define _PAGE_TABLE_PKG_SVH_

// 通用页表 / 内存模型: SDecoder 与 SDPWU 的验证环境共用
//   - 按地址索引的稀疏内存 (未写过的地址读回 0)
//   - 按设计方案的 L1 / L2 条目布局写表
//   - expect_finish(): 按设计方案语义算出一次 Page Walk 的理想结果, 供 scoreboard 比对
package page_table_pkg;

    import sdecoder_pkg::*;

    `include "page_table_model.sv"

endpackage

`endif // _PAGE_TABLE_PKG_SVH_
