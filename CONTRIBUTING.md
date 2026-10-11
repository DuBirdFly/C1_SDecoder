# CONTRIBUTING

## 写 Markdown 文档

Markdown 文档遵循 [`doc/md文件编写规范.md`](doc/md文件编写规范.md):
图表优先 Mermaid, 文件型图片的目录与命名, 一律使用半角标点.

### markdownlint 检查

改动后在**仓库根目录**执行检查 (必须显式带 `--config`: markdownlint-cli2 不向上级目录查找配置):

```bash
markdownlint-cli2 "doc/**/*.md" --config ./.config/.markdownlint.jsonc
```

规则集与命令说明见 [`doc/ubuntu_env/markdownlint.md`](doc/ubuntu_env/markdownlint.md);

### Mermaid 检查

文档里含 Mermaid 图时, 再按 [`doc/ubuntu_env/mermaid.md`](doc/ubuntu_env/mermaid.md) 跑一遍语法校验.

## 写 python 文件

### ruff 检查

写完或改完 `.py` 后, 在**仓库根目录**执行检查:

```bash
ruff check --config ./.config/ruff.toml .             # lint 全仓库
ruff format --check --config ./.config/ruff.toml .    # 只检查格式, 不落盘
```

注: 必须显式带 `--config`: ruff 不会去 `.config/` 找配置, 省略后 `.config/ruff.toml` 里的豁免全部失效

- 新写的代码要标类型注解: 函数签名与返回, 模块常量, 以及含义不直观的局部变量, 尽可能写全
- 检查完顺手删掉工作区里的 `.ruff_cache/` (已被 gitignore, 但不留在工作区)

规则集与命令说明见 [`doc/ubuntu_env/ruff.md`](doc/ubuntu_env/ruff.md);
按需加载的检查流程见 [`.agents/skills/python-check/SKILL.md`](.agents/skills/python-check/SKILL.md).

## 写 Verilog / SystemVerilog 文件

改动 Verilog / SystemVerilog 后, 在**仓库根目录**跑一遍编译与冒烟:

```bash
make -C simulation_agent all
```

仿真流程 (变量 / 目标 / 判定口径 / 产物与波形) 见 [`simulation/README.md`](simulation/README.md).

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
- 方向前缀按信号类别取 (不用 `wr_*` / `rd_*`):
  - 查表请求: `req_*`;命中读出的数据: `hit_*`;装填: `fill_*`;置无效 (刷新): `inv_*`
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
