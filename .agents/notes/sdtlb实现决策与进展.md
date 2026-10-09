# sdtlb 实现决策与进展

| 项目 | 内容 |
| --- | --- |
| 文档名称 | sdtlb 实现决策与进展 |
| 日期 | 2026-10-06 |
| 范围 | SDTLB (Tag 阵列 + Data 阵列 + SLA 计算) 与其单元自检 |
| 上游 | [SDecoder 设计方案](../../doc/design_plan/SDecoder设计方案/SDecoder设计方案.md), [SDecoder 接口手册](../../doc/design_plan/SDecoder接口手册/SDecoder接口手册.md) |
| 说明 | 本文件只记**决策与理由**以及进展快照. 编码规范 (命名, 大括号风格, `*.svh` 与 import 约束) 见 [CONTRIBUTING.md](../../CONTRIBUTING.md), agent 每次要遵守的约定与检查命令见 [AGENTS.md](../../AGENTS.md), 设计细节与位域见上述设计文档, 这里不复制正文 |

## 模块划分与理由

```mermaid
flowchart TB
    SDTLB["sdtlb 顶层<br/>命中优先级编码 + SLA 计算"] --> TAGARR["sdtlb_tag 阵列<br/>generate for, 内含轮转替换指针"]
    SDTLB --> DATAARR["sdtlb_data 阵列<br/>generate for, 写/读下标译码"]
    TAGARR --> TI["sdtlb_tag_item x 128<br/>CAM 比较 + 有效位 + 命中读出"]
    DATAARR --> DI["sdtlb_data_item x 128<br/>数据寄存器 + 门控读出"]
```

- **条目 → 阵列 → 顶层三层**: 条目是行为单元, 阵列管例化/译码/汇总, 顶层管编码与 SLA, 三者可各自演进. 阵列模块**不按 RAM/SRAM 形式预留接口** —— Data 段的读写选中都用 SDTLB_ENTRIES 位 one-hot (自然的全相联形式), 将来若真要换 RAM, 再改阵列模块的读写口 (把 one-hot 编成地址)
- **Tag 与 Data 分属两个阵列模块而非一个合并模块**: 二者的读语义本来就不同 (Tag 是全并行比较, Data 是按选中读出), 分开后 Tag 侧仍是 CAM 语义, 将来若改索引式 tag RAM (set-associative 口径) 只需改 `sdtlb_tag` 与它对顶层的接口
- 曾有过一版把两者合在一个 `sdtlb` 里的实现, 已弃用并留档在 [backup/rtl/sdtlb_tag.sv](../../backup/rtl/sdtlb_tag.sv) (`backup/` 不入库)

## 已定决策

| 决策 | 理由 |
| --- | --- |
| 未命中时读出全 0 (`hit_*` / `hit_sla` / `hit_sla_ovf` 都给 0) | 组合读出若不加门控会露出 `req_pa` 的残值;置 0 后上层直接以 `req_hit_vld` 判断有效性 |
| Data 段的读写选中用 **SDTLB_ENTRIES 位 one-hot 向量** (`fill_vld` / `hit_sel`), 不用"地址 + 有效"的 RAM 形式 | 暂不考虑 RAM 构建形式 (用户口径): 全相联下 one-hot 是最自然的形式 —— 写使能 `fill_vld` 由 Tag 段的轮转指针译码成 one-hot (`fill_sel`), 读选中 `hit_sel` 直接用 Tag 段的命中向量 (`req_hit`), 未命中时全 0 所以读出自然全 0, 连读有效位都不需要. 端口名与 `sdtlb_data_item` 的同名端口对齐. 单命中行为与"按命中下标 mux"完全一致;多命中 (按构造不应出现, 已断言守住) 时读出是各命中条目数据的**按位或** |
| 轮转替换指针放在 `sdtlb_tag` 内部, 以 `fill_sel` (one-hot) 输出 | 用户选定;写选中由 Tag 段给出, Data 段用同一根向量写入, 保证 Tag/Data 同条目 |
| 无效化只清 Tag 侧 `valid`, Data 段无有效位端口 | 设计方案的无效化只清 `Valid`;数据段的有效性由同下标 Tag 条目代表 |
| 无效化的 `inv_match` **刻意不含** `tag_item.valid` | 若含有效位, 条目当前无效时清位分支不会被选中, 同拍的装填会把覆盖"正在被刷新地址"的映射填进去. 变异测试 (把有效位加回条件) 令该用例 FAIL, 已固定为回归用例 |
| SLA 计算放在顶层 `sdtlb`, 段式与页式共用一条公式 | 设计方案 §代换结果计算;页式的 `pa_base[34:30] == pa_up` 使偏移自然为 0. 加法进位作为 `hit_sla_ovf` 给上层报地址非法 |
| `pa_up` 是**段空间绝对上界 (含)**, 不是相对偏移 | 用户口径: 区间取闭区间 `[pa_base[34:30], pa_up]`, 页式即 `pa_base[34:30] == pa_up`. 曾短暂改成"相对偏移"口径又改回, 代价见下面"关键坑"里那条 5 bit 进位的记录 |
| 装填区间须**非空**, 落成断言 `a_wr_pa_range_valid` (放 `sdtlb` 的装填入口) | 绝对上界形式下区间比较没有加法、不会进位, 唯一要守的是 `pa_up >= pa_base[4:0]`;低于基址页号的上界会让条目永远命中不了 |
| 顶层不引出 Tag 侧读出 (`hit_pa_base` / `hit_pa_up`), 且 `hit_pa_up` 整条链删除 (条目 → 阵列 → 顶层) | 上层只需 SLA;`hit_pa_base` 留着是因为 SLA 偏移要用, `hit_pa_up` 无人读, 属死信号 |
| 命中下标多命中取最小 | 设计方案 §命中判断;同时让"按命中下标读数据"有确定行为 |
| 断言拆两处: `PA[47]=0` 放 tag 条目, `$onehot0(req_hit)` 放 tag 阵列 | 各自放在"产生该约束的模块"里: 条目是请求地址的入口, 阵列是命中向量的产生者 |

## 断言与头文件机制

- 断言宏 (`assert_clk` / `assert_x_value`) 与总开关 `ASSERT_ON` 放在 [rtl/sdecoder_constants.svh](../../rtl/sdecoder_constants.svh);`ASSERT_ON` 由 [simulation/base/option/compile_define.f](../../simulation/base/option/compile_define.f) 默认打开
- `rtl/sdecoder-undef.svh` 作为 filelist 中该段的**末行**做清理, 把该段用到的 `ifndef` 守卫**全部**清掉, 含 `_SDECODER_PKG_SVH_` (参照 Synopsys 的口径: 段末把宏状态清干净). 常量头守卫必须清, 否则下一段再 `include` 常量头会被守卫跳过而拿不到宏 (实测不补 => `Error-[UM] Undefined macro`)
- **由此定下的硬约束**: 已被前面段处理过的 `*.svh` 不允许在后续段再 `include`. testbench 侧要用包里的名字, 靠 `import sdecoder_pkg::*;` (参见 [sdtlb_if.sv](../../testbench/top/interface/sdtlb_if.sv) 把 import 放在接口头), 不要再写 `` `include "sdecoder_pkg.svh" `` —— 守卫已清, 再 include 就是把 `package` 声明读第二遍, 同一编译单元里重复定义 (实测 => `Error-[SV-PPD] Package previously declared`)
- 代价 (已知并接受): testbench 环境不能再 `include` DUT 段已经处理过的 `*.svh`, 自包含性靠 `import` 维持;这条口径已写入 [CONTRIBUTING.md](../../CONTRIBUTING.md) 的 `*.svh` 小节
- `*.svh` 一律带 `ifndef` 守卫的理由: 同一段内包/常量头会被多个文件 include, 守卫是防重复定义的第一道闸

## 关键坑与结论 (供后来人避雷)

| 现象 | 结论 |
| --- | --- |
| `logic [16:0] x = expr;` 后仿真里 `hit` 全是 X | 变量声明初始化只在 0 时刻赋一次, 不是持续赋值;组合信号要么 `wire x = expr;` 要么 `logic x; assign x = expr;` |
| 断言宏展开后报错落在 `endmodule` | 常量头里两个宏的正文末尾**没有分号**, 调用点必须自己补 `;` (定义处已注明) |
| 接口里 `timeunit` 报 `Error-[SV-MTU] Misplaced timeunit` | `timeunit`/`timeprecision` 必须是接口体里最前面的声明, 放在 `import` 之后即报错 |
| 既用 clocking block 又裸赋值写同一信号 | clocking block 的 `output` 会被该块持续驱动 (内部变量初值 X), 二者混用会出现多驱动/被 X 覆盖;驱动只能走一条路 |
| `make` 退出码为 0 但自检失败 | VCS 即使 `$fatal` 退出码也是 0;判定必须看 `log/simv.log` 里的 `RESULT: PASS\|FAIL` 行 |
| 无守卫的包头被多个文件 include | `Error-[SV-PPD] Package previously declared` |
| 清了包头守卫后又去 `include` 包头 | 同样报 `Error-[SV-PPD]`: `undef` 删的是**宏**, 已声明的 package 不会消失, 所以包里的名字仍可用 (`import`), 但文本不能再来一遍 |
| 把 `pa_up` 当"相对偏移"实现时, `pa_base[4:0] + pa_up` 是 **5 bit** 加法 | 求和会回绕: 跨 32 页边界的段整段静默失效 (实测 base[4:0]=16 / up=20 时连基址页都不命中, 且断言不报). 现已改回绝对上界口径;若将来仍要偏移口径, 比较必须放到 17 bit 上做 (`req_seg_idx` 与 `pa_base` / `pa_base + pa_up` 单调比较), 并且不再要求 PA[46:35] 相等 |

## 自检(testbench)决策

- **单时钟域 → 无 `#NUM`**: 时钟与复位一律由 [testbench/top/crg.sv](../../testbench/top/crg.sv) 生成;同步等时钟块事件 `@(sdtlb_if.drv)`;驱动与读出之间隔一个事件, 组合逻辑早已稳定, 所以不需要延时
- **单条目不再单独建 tb**: 原 `tb_sdtlb_tag_item.sv` 已删除 —— 它的用例是按旧的"绝对上界"口径写的, 与新口径冲突;条目行为改由 `tb_sdtlb` 覆盖 |
- **接口 + 时钟块**: [testbench/top/interface/sdtlb_if.sv](../../testbench/top/interface/sdtlb_if.sv) 打包信号并给出 `drv` (驱动 + 回读) 与 `mon` (只采样) 两个时钟块;命中/数据/SLA 是同拍组合量, 因此**直接读裸接口信号**, 不走时钟块采样 (时钟块只在沿上取值, 不适合同拍组合量)
- **agent 与人工仿真分开**: agent 一律用 [simulation_agent/](../../simulation_agent) (其 `Makefile` / `base` 是指向 `simulation/` 的软链, 只有 `run_*_testcase/` 独立), 不往 `simulation/` 写运行产物 —— 避免两边互相覆盖日志与波形;`make -C simulation_agent all` 与 `make -C simulation all` 用法完全一样
- **波形默认出**: Makefile 的 `DUMP_WAVE` 默认 1 (目前 tb 体量小, 不认为会拖慢仿真;要关掉传 `DUMP_WAVE=0`);回归脚本仍显式 `DUMP_WAVE=0`, 排查问题按单测跑并开波形;单元自检的波形文件名与 `tb_top` 共用 `test_pkg` 里的常量

## 进展快照

- RTL: `sdecoder_pkg.svh` / `sdecoder_constants.svh` / `sdecoder-undef.svh` / 两个条目 / 两个阵列 / `sdtlb` 顶层
- 自检: 只剩 `tb_sdtlb` (接口 + `drv` + crg, 无 `#NUM`), 当前**只剩 9 条在用**(空表 3 条 + 页式条目 6 条);段式偏移、按地址置无效、轮转指针、SLA 溢出、多命中这 5 类用例被整段注释掉, 标注为 `[TODO] 以下测试是以前留的, 不再使用` (暂不处理)
- 验证结论: `make -C simulation all` 与各模块 elaborate 均 0 error / 0 warning;`tb_sdtlb` 9 条 PASS;新断言 `a_wr_pa_range_valid` 在临时用例里验过 —— 合法装填 (base[4:0]=16, up=20) 不报, 区间为空的装填 (base[4:0]=16, up=5) 报出

## 待决策

1. 替换策略: 轮转 (现状) 还是伪随机 (参考 CORE 内 TLB);影响是否要引入命中下标驱动的状态更新
2. 条目用 FF 还是 RAM 实现 (直接决定阵列模块内部怎么写)
3. `req_hit_idx` 是否作为顶层端口保留 (现仅内部用于读数据);`hit_sla_ovf` 的命名与异常上报形式
4. `grn` 目前不参与 SLA 计算 (与设计一致), 后续 SMD 组装是否要用;`一些思考.md` 里已记为"感觉没有意义"
5. `tb_sdtlb` 里被注释掉的那批用例是否按新口径补回 (段式偏移 / 按地址置无效 / 轮转 / 溢出 / 多命中)

## 尚未开始

未命中队列 + SDPTW Page Walk 状态机 (`tw_*` 主端口);`rsp_*` 响应与 SMD 三元组组装、异常码上报;`cfg_*` 配置与刷新接口 (`cfg_inv_busy`、刷新期间阻塞回填);`PA[47] = 1` 的 IO 空间请求在顶层的异常通路 (目前只有 tag 条目里那条断言守着这个前提).

## 变更记录

| 日期 | 说明 |
| --- | --- |
| 2026-10-06 | 首版: 汇总 SDTLB 已定决策, 关键坑与结论, 自检决策, 进展快照与待决策项 |
| 2026-10-06 | 头文件口径定为 P1: 段末 `*-undef.svh` 连包头守卫一起清 (Synopsys 口径), 后续段不得再 `include` 已处理过的 `*.svh`, 改用 `import`;修正首版里"刻意不清包头守卫"的错误说法, 并写入 CONTRIBUTING.md |
| 2026-10-06 | 波形口径改为**默认出**: Makefile 的 `DUMP_WAVE` 默认 1, 理由是目前 tb 体量小、不认为拖慢仿真;同步修正首版"波形默认关"的说法与两个 tb 里对应的注释 |
| 2026-10-06 | `pa_up` 口径定为**相对偏移** (页数 - 1, 0 = 页式);段不允许跨 32 页边界的约束落成 `sdtlb` 里的 `a_wr_pa_no_cross_page` 断言(实测跨界装填会报);顶层去掉 `rd_pa_base` / `rd_pa_up` 并删除 `rd_pa_up` 整条死链;删除 `tb_sdtlb_tag_item`(旧绝对口径, 且条目行为改由 `tb_sdtlb` 覆盖);设计方案与 pkg 注释按新口径统一 |
| 2026-10-06 | `pa_up` 口径**改回绝对上界 (含)**: 闭区间 `[pa_base[34:30], pa_up]`, 页式 `pa_base[34:30] == pa_up`. 上一笔记的"相对偏移"口径与其 6 bit 求和的不跨界断言一并撤销, 换成守住区间非空的 `a_wr_pa_range_valid`;RTL 注释、pkg 注释、设计方案 7 处、tb 的页式装填值 (`up` 由 0 改为 `base[4:0]`) 同步 |
| 2026-10-06 | 新增 agent 专用仿真入口 `simulation_agent/` (软链 `Makefile` / `base`, 独立运行目录), agent 不再往 `simulation/` 写产物;AGENTS.md 与 CONTRIBUTING.md 的命令与说明同步 |
| 2026-10-06 | `sdtlb_data` 的读写口由"地址 + 有效"(`wr_idx`、`rd_vld`/`rd_idx`) 改为 **128 位 one-hot 向量** (`wr_vld`/`rd_sel`, 与条目端口同名), 因为暂不考虑 RAM 构建形式;`sdtlb_tag` 的 `fill_idx` 随之改为 `fill_sel` (one-hot), 顶层把 `req_hit` 直接接给 Data 段的 `rd_sel` —— 顺带省掉了读侧的 `rd_vld` 门控 |
| 2026-10-06 | 端口/信号按类别改名: 装填类 `wr_*` -> `fill_*`, 命中读出类 `rd_*` -> `hit_*` (`rd_eid`/`rd_s_pfn`/`rd_grn`/`rd_token_id` -> `hit_*`, `rd_sla`/`rd_sla_ovf` -> `hit_sla`/`hit_sla_ovf`, `rd_sel` -> `hit_sel`, `rd_pa_base` -> `hit_pa_base`);断言名 `a_wr_pa_range_valid` -> `a_fill_pa_range_valid`;接口与 tb 同步 |
