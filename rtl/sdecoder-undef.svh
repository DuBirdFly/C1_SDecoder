// 段的收尾清理: 除了清掉断言宏, 还要清掉 sdecoder_constants.svh 的守卫,
// 否则下一段再 `include "sdecoder_constants.svh" 会被守卫跳过, 宏拿不到.
`ifdef _SDECODER_CONSTANTS_SVH_
  `undef _SDECODER_CONSTANTS_SVH_
`endif

`ifdef ASSERT_MSG_LABELED
  `undef ASSERT_MSG_LABELED
`endif

`ifdef assert_clk
  `undef assert_clk
`endif

`ifdef assert_x_value
  `undef assert_x_value
`endif

// note: 这里刻意不清 _SDECODER_PKG_SVH_: package 在编译单元里只能定义一份,
//       清了守卫反而会让下一个 include 的文件重复定义 package 而报错.

