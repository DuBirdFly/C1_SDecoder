# AGENTS.md

本文件是 agent 的常驻入口: 只写每次都要遵守的约定, 细节一律指向唯一的事实来源, 不在这里复制正文.

## 写 Markdown 文档

`doc/` 下的 Markdown 文档遵循 [`doc/md文件编写规范.md`](doc/md文件编写规范.md):
图表优先 Mermaid, 文件型图片的目录与命名, 一律使用半角标点.

改动后在**仓库根目录**执行检查 (必须显式带 `--config`: markdownlint-cli2 不向上级目录查找配置):

```bash
markdownlint-cli2 "doc/**/*.md" --config ./.config/.markdownlint.jsonc
```

文档里含 Mermaid 图时, 再按 [`doc/ubuntu_env/mermaid.md`](doc/ubuntu_env/mermaid.md) 跑一遍语法校验.

规则集与命令说明见 [`doc/ubuntu_env/markdownlint.md`](doc/ubuntu_env/markdownlint.md);
Node.js 安装见 [`doc/ubuntu_env/nodejs.md`](doc/ubuntu_env/nodejs.md).

## 写 python 文件

写完或改完 `.py` 后, 在**仓库根目录**执行检查 (必须显式带 `--config`: ruff 不会去 `.config/`
找配置, 省略后 `.config/ruff.toml` 里的豁免全部失效):

```bash
ruff check --config ./.config/ruff.toml .             # lint 全仓库
ruff format --check --config ./.config/ruff.toml .    # 只检查格式, 不落盘
```

- 新写的代码要标类型注解: 函数签名与返回, 模块常量, 以及含义不直观的局部变量, 尽可能写全
- **不要顺手格式化整个仓库**, 只格式化本次改动的文件; 要全量重排就单独提一个提交
- 检查完顺手删掉工作区里的 `.ruff_cache/` (已被 gitignore, 但不留在工作区)

规则集与命令说明见 [`doc/ubuntu_env/ruff.md`](doc/ubuntu_env/ruff.md);
按需加载的检查流程见 [`.agents/skills/python-check/SKILL.md`](.agents/skills/python-check/SKILL.md).

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
  - testbench 里 `*.svh` 可以 `include` 导入, 也可以在 filelist 里导入
  - `*-undef.svh` 不使用 `include` 导入, 人工约束 `*-undef.svh` 只能在 filelist 的对应段末尾导入

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

## 目录约定

- `doc/`: 项目文档. 设计方案放在各自的 `<文档名>/` 目录内, 图片放在同级的 `image/<文档名>/`.
- `doc/ubuntu_env/`: 本机 (Ubuntu) 环境与工具链说明, 一工具一文件: `nodejs.md`, `markdownlint.md`,
  `ruff.md`, `chromium.md`, `mermaid.md`.
- `.agents/notes/`: 只放决策与理由记录 (为什么这么定), 不放操作手册.
- `.agents/skills/`: 需要按需加载给 agent 的能力 (带 YAML frontmatter 的 `SKILL.md`).
