# SDPWU 仿真问题记录

本文记录 `tb_sdpwu_top` (SDPWU_TOP 的 UVM 环境) 在调试过程中遇到的问题、根因与修法.

## 复现方式

```bash
make -C simulation_agent TB_TOP=tb_sdpwu_top all
```

运行目录: `simulation_agent/run_single_testcase/tb_sdpwu_top.SdpwuTestBase/`.

## 问题 1: driver 兼任"外部存储器"导致采样不一致

最初 `SdpwuDrv` 在 `run_phase` 里 `fork` 了两个角色: SDMQ (发 start 请求) 和外部存储器
(响应访存读). 存储器角色用 driver 的 clocking block 采 `pw_mem_raddr_valid`, 和 monitor 用
`vif.mon` 采到的结果不一致:

```text
DBG_R @3000 raddr_v=0 rdy=0
DBG_R @4000 raddr_v=0 rdy=0      ← monitor 在 4000 已经计数了 mem_rd
```

结果单次 Page Walk 观察不到 finish (`start=1 mem_rd=1 finish=0`): SDPWU 卡在 `S_L1_RD_DATA`.

根因: 同一个信号既用 clocking 输出驱动又用直接赋值驱动, 且 driver 在同一个 process 里
"采样 + 立刻驱动", 相位和 monitor 的 clocking block 不一致.

**修法**: 把存储器角色从 driver 里彻底拿掉, 做成仿真用的 RTL 风格模块
`testbench/top/model/sdpwu_mem_model.sv`:

- 写端口 `pw_mem_wen / pw_mem_waddr / pw_mem_wdata`: 一拍写入一个 16B 条目, tb 用它布置页表;
- 读地址通道: 收到 `pw_mem_raddr_valid` 后随机等 0..`LAT_MAX` 拍再给 `pw_mem_raddr_ready`;
- 读数据通道: 握手后下一拍返回条目 (按 `pw_mem_raddr_id` 带回), 未写的地址读回 0;
- 模块内部不带 `l1_base`: 页表基地址是软件配置, DUT 侧由 tb 给, 模型只按绝对地址存取.

driver 只保留 SDMQ 的 start 请求和"布置页表"的写口.

## 问题 2: 多次 Page Walk 时 VCS 段错误

问题 1 未修时, 发两次以上 Page Walk 会在第 2 个请求的访存读之后崩溃:

```text
DBG_MON @3000 publish START pa=000100000000 idx=0
DBG_SCB @3000 kind=SDPWU_START_SEEN
DBG_SCB @4000 kind=SDPWU_MEM_RD
DBG_MON @12000 publish START pa=0009c0000000 idx=1
DBG_SCB @13000 kind=SDPWU_MEM_RD
Child process exited with status 127: .../cbug-gdb-64/bin/gdb ...
```

本机没有 VCS 自带的 gdb, 拿不到堆栈. 问题 1 修掉后 (driver 不再直接驱动/采样访存通道,
也不再混用 clocking 输出与直接赋值) 崩溃消失.

## 排查过程中修掉的其他问题

表: 其他修复

| 问题 | 修法 |
| --- | --- |
| CTRL 没请求时也给 SDPWU 发 start, 空闲 SDPWU 会把 X 当成请求 | `pwu_start_valid = {PWU_NUM{sdmq_pw_valid}} & grant` |
| `pwu_start_item [PWU_NUM]` 这类 struct 非合并数组端口 | 改成 packed 数组 |
| `SdpwuItem` 对 packed struct 用 `uvm_field_int` | 去掉, 改用一个 packed 副本字段 |
| 运行目录残留 FSDB 锁 / 旧 output | 清 `output/` `log/` 后重跑 |

## 现状

```text
UVM_INFO ... [SCB] start=7 mem_rd=10 finish=7 err=0
UVM_INFO ... [SCB] sdpwu 比对全部通过
UVM_ERROR : 0 / UVM_FATAL : 0
```

覆盖: 段式命中 / 页式命中 / 一级表缺页 / 一级表 malformed / 二级表缺页 / 两个请求并行.
scoreboard 从存储器写口 (`pw_mem_wen/waddr/wdata`) 重建同一张页表, 在内部按设计方案语义
算期望值后与 finish sideband 比对 (不再依赖 class 版页表模型).
