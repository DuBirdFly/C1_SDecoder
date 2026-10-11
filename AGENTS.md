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
make -C simulation_agent all
```

`simulation_agent/` 是给 agent 用的仿真目录 (`Makefile` 与 `base` 都是指向 `simulation/` 的软链,
只有运行目录 `run_*_testcase/` 独立), 用法与 `simulation/` 完全一样. **`simulation/` 是人自己的
仿真目录, agent 不要往里写** —— 避免两边互相覆盖日志与波形.

编码规范 (文件名与 `*.svh` 的导入约束, 命名, 缩进与大括号, 其他要求) 见
[`CONTRIBUTING.md`](CONTRIBUTING.md)

## 目录约定

- `rtl/common/`: 可复用的通用 RTL 模块 (不依赖本项目 package 的独立 module, 如 `inc_arbiter` / `decoder_bin2onehot` / `encoder_onehot2bin` / `onehot0_mux`).
- `doc/`: 项目文档. 设计方案放在各自的 `<文档名>/` 目录内, 图片放在同级的 `image/<文档名>/`.
- `doc/ubuntu_env/`: 本机 (Ubuntu) 环境与工具链说明, 一工具一文件: `nodejs.md`, `markdownlint.md`,
  `ruff.md`, `chromium.md`, `mermaid.md`.
- `.agents/notes/`: 只放决策与理由记录 (为什么这么定), 不放操作手册.
- `.agents/skills/`: 需要按需加载给 agent 的能力 (带 YAML frontmatter 的 `SKILL.md`).
