# ruff 安装与使用

ruff 是用 Rust 写的 Python 代码检查 (lint) 与格式化 (format) 工具, 一个二进制覆盖了
flake8, isort, pyupgrade, black 等常用工具的职责. 本仓库用它统一 `*.py` 的代码规范

**前提**: 无. ruff 是独立的静态二进制, 不需要 `node.js`, 也不需要本机预装 Python

## 安装与卸载

官方文档: <https://docs.astral.sh/ruff/>

官方安装脚本 (Linux / macOS, 装到 `~/.local/bin`):

```bash
curl -LsSf https://astral.sh/ruff/install.sh | sh
```

安装完成后确认:

```bash
which ruff
ruff --version
```

输出形如:

```text
ruff 0.16.8
```

其它安装方式 (任选其一):

| 方式 | 命令 |
| --- | --- |
| pipx | `pipx install ruff` |
| uv | `uv tool install ruff` |
| pip | `pip install ruff` (建议装在虚拟环境里) |

卸载:

```bash
# 官方脚本安装
rm -f ~/.local/bin/ruff

# 其它方式
pipx uninstall ruff
uv tool uninstall ruff
pip uninstall ruff
```

## 配置文件

规则集只有一份: **`.config/ruff.toml`**, 用 `--config <路径>` 指定

- 内容: 沿用 ruff 内置默认规则集, 只追加一条 `[lint] ignore = ["F541"]`
  (F541 是 "无占位符的 f-string", 本仓库已有代码把它当书写习惯, 不报错)
- 编辑器: `.vscode/settings.json` 的 `ruff.configuration` 指向同一个文件

### 发现规则 (容易踩坑)

**ruff 不会去 `.config/` 找配置**: 它只在被检查文件所在目录及其上级目录里查找
`ruff.toml`, `.ruff.toml` 或 `pyproject.toml`. 配置放在 `.config/` 下, 因此:

- 省略 `--config`: 退回内置默认规则, `[lint] ignore` 失效, 会误报 F541;
  更麻烦的是 `ruff check --fix` 会按默认规则**真的去改代码** (删掉那些多余的 `f` 前缀);
- 带上 `--config`: 规则集按预期生效.

因此本仓库的约定是**每条命令都带 `--config`** (与 [markdownlint](../markdownlint/README.md) 的处理方式一致),
路径按当前所在目录推导:

| 执行目录 | `--config` 相对路径 |
| --- | --- |
| 仓库根 | `./.config/ruff.toml` |
| `doc/script/` | `../../.config/ruff.toml` |
| `simulation/base/filelists/merge_all_filelist/` | `../../../../.config/ruff.toml` |

`--config` 放在子命令前面或后面都可以:

```bash
ruff check --config ./.config/ruff.toml .
ruff --config ./.config/ruff.toml check .
```

两条命令等价

## 使用

以下命令都在**仓库根目录**执行

### 检查整个仓库

```bash
cd /path/to/project_root
ruff check --config ./.config/ruff.toml .
```

通过时输出:

```text
All checks passed!
```

有问题时逐条列出, 并提示哪些能自动修复:

```text
F541 [*] f-string without any placeholders
   --> simulation/base/filelists/merge_all_filelist/merge_all_filelist.py:120:17
    |
120 |         f.write(f"// 包含以下 .f 文件:\n")
    |                 ^^^^^^^^^^^^^^^^^^^^^^^^^

Found 2 errors.
[*] 2 fixable with the `--fix` option.
```

格式为 `规则码 [*] 说明` + `--> 文件:行:列`, 行首的 `[*]` 表示该问题可自动修复

### 检查单个文件或某个目录

```bash
cd /path/to/project_root
ruff check --config ./.config/ruff.toml doc/script/.docx2md.py
ruff check --config ./.config/ruff.toml doc/
```

### 自动修复

```bash
cd /path/to/project_root
ruff check --fix --config ./.config/ruff.toml .
```

**不要漏掉 `--config`**: 否则会按默认规则改动代码. 想先看会改什么, 用 `--diff` 只预览不落盘:

```bash
cd /path/to/project_root
ruff check --diff --config ./.config/ruff.toml .
```

### 格式化

```bash
cd /path/to/project_root
ruff format --check --config ./.config/ruff.toml .   # 只检查, 不改文件
ruff format --config ./.config/ruff.toml .           # 实际改写
```

注: `[lint]` 段不参与格式化, 所以 `ruff format` 加不加 `--config` 结果相同; 仍然统一带上, 少记一条规则

当前仓库 `ruff format --check` 有 1 个文件待重排:
`simulation/base/filelists/merge_all_filelist/merge_all_filelist.py`.
建议单独提一次纯格式化提交, 或者只格式化新写的文件, 避免把格式化 diff 混进功能改动

### 用于脚本或提交前检查

```bash
cd /path/to/project_root
ruff check --config ./.config/ruff.toml . || exit 1
```

退出码: `0` 表示无问题, `1` 表示存在问题 (`ruff format --check` 同理)

## 缓存与扫描范围

- ruff 会在**执行命令的目录**下生成 `.ruff_cache/`, `.gitignore` 里的 `.ruff_cache/` 在任意层级都匹配,
  不需要手工清理
- 扫描范围默认尊重 `.gitignore`, 只处理 `*.py`. 本仓库当前命中两个文件:
  `doc/script/.docx2md.py` 与
  `simulation/base/filelists/merge_all_filelist/merge_all_filelist.py`
