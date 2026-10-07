# CONTRIBUTING

| 项目 | 内容 |
| --- | --- |
| 文档名称 | CONTRIBUTING (编码规范) |
| 日期 | 2026-10-06 |
| 范围 | 本仓库的编码规范: SystemVerilog (UVM 使用规范待补) |
| 说明 | 人读的规范. agent 的常驻入口见 [`AGENTS.md`](AGENTS.md): 那里只放每次都要遵守的约定, 细节一律指向本文件 |

## 写 Verilog / SystemVerilog 文件

改动 `rtl/` 后, 在**仓库根目录**跑一遍编译与冒烟:

```bash
make -C simulation all
```

### 代码风格

#### 文件名

- 文件名与 `module/interface/package/class` 名一致
- package 以 `_pkg.svh` 结尾
- interface 以 `_if` 结尾
- module 推荐全小写, 下划线式 (不强制)
- `*.svh` 文件以 `ifndef` 宏保护 (避免多次 `include` 导致的重复定义)
  - rtl 里通常 `*.svh` 使用 `include` 导入
  - testbench 里 `*.svh` 可以 `include` 导入, 也可以在 filelist 里导入, 但**已被前面段处理过的
    `*.svh` 除外** (见下一条)
  - `*-undef.svh` 不使用 `include` 导入, 人工约束 `*-undef.svh` 只能在 filelist 的对应段末尾导入
  - 段末的 `*-undef.svh` 会把该段用到的 `ifndef` 守卫一并清掉 (含 `*_pkg.svh` 的守卫, 参照
    Synopsys 的口径: 段末把宏状态清干净). 因此**已被前面段处理过的 `*.svh` 不允许在后续段再
    `include`**, 后续段用 `import <pkg>::*;` 使用其中的 package —— 再 `include` 会在同一个
    编译单元里重复定义, 报 `Error-[SV-PPD] Package previously declared`

#### 文件内命名

- 类型名 (如类, 结构体, 枚举)：单个大写字母开头
- 变量名：小写字母开头
- 参数与宏: 全大写字母, 下划线式
- 多词命名
  - 类: 大驼峰式 (PascalCase)
  - 对象: 小驼峰式 (camelCase)
  - 结构体/枚举: 大写字母开头, 下划线式
  - 其他: 小写字母开头, 下划线式

#### 缩进与大括号

- `begin` 放在语句同一行的末尾，而不是另起一行
- `else` 另起一行, 与 `if` 对齐

例子

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r <= '0;
    end
    else if (valid) begin
        r <= i;
    end
end
```

#### 其他代码风格要求

- `rtl/` 下的设计代码**禁用 function / task** (不去挑战 EDA 工具)
- `testbench/` 下的验证代码可以不受限使用 Verilog / SystemVerilog 新语法特性
- `virtual interface` 使用 `_vif` 结尾
- 普通 `for` 循环的变量用 `int i/j/k`, `generative for` 的变量用 `genvar_i/j/k`
