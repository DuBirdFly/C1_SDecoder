# markdownlint 安装与使用

markdownlint 用于检查 Markdown 的排版规范. 本仓库的规则集是 `.config/.markdownlint.jsonc`,
所有命令都**显式带上 `--config` 指向它** (原因见下面的「发现规则」)

**前提**: 先按 [`doc/ubuntu_env/nodejs.md`](nodejs.md) 安装 Node.js. `markdownlint-cli2` 要求 **Node >= 22**, 该文档推荐使用 Node 24 LTS

## 安装与卸载

官方仓库: <https://github.com/DavidAnson/markdownlint-cli2>

按其 README 的说明安装 (作为 global CLI):

```bash
npm install markdownlint-cli2 --global
```

*注: `node` 为系统安装时, 比如 `/usr/bin/node`, 需加 `sudo`*

安装完成后确认:

```bash
markdownlint-cli2 --help | head -1
```

输出形如:

```text
markdownlint-cli2 v0.23.3 (markdownlint v0.41.1)
```

注: 该工具没有 `--version` 选项, 查版本就用上面的方式

卸载 (同样可能需要 `sudo`):

```bash
npm uninstall markdownlint-cli2 --global
```

## 配置文件

规则集只有一份: **`.config/.markdownlint.jsonc`**, 用 `markdownlint-cli2 --config <路径>` 指定

这样做的原因见下节: 配置放在 `.config/` 时不会被自动发现, 所以不依赖自动发现, 而是每条命令都写清楚

### 发现规则 (容易踩坑)

**markdownlint-cli2 不向上级目录查找配置**: 它只看执行命令时的当前目录, 以及被检查文件所在目录及其下级.

配置放在 `.config/` 下, 既不是当前目录 (在仓库根执行时), 也不是被检查文件所在目录, 所以:

- 省略 `--config`: 退回默认规则, 会报出一堆 `MD013`/`MD033` 之类的假问题;
- 带上 `--config`: 规则集按预期生效.

因此**本仓库的约定是每条命令都带 `--config`**, 路径按当前所在目录推导:

| 执行目录 | `--config` 相对路径 |
| --- | --- |
| 仓库根 | `./.config/.markdownlint.jsonc` |
| `doc/` | `../.config/.markdownlint.jsonc` |
| `doc/ubuntu_env/` | `../../.config/.markdownlint.jsonc` |

## 使用

下面命令里的 `cd /path/to/project_root` 只是为了固定工作目录; 在别的目录执行时, 按上表换成对应的 `--config` 相对路径即可

### 检查单个文件

```bash
cd /path/to/project_root
markdownlint-cli2 "doc/ubuntu_env/markdownlint.md" --config ./.config/.markdownlint.jsonc
```

```bash
# 也可以在被检查文件所在目录执行
cd /path/to/project_root/doc/ubuntu_env
markdownlint-cli2 "markdownlint.md" --config ../../.config/.markdownlint.jsonc
```

输出形如:

```text
markdownlint-cli2 v0.23.3 (markdownlint v0.41.1)
Finding: doc/ubuntu_env/markdownlint.md
Linting: 1 file
Summary: 0 issues in 0 files
```

`Summary: 0 issues` 即通过. 若检查一个有问题的文件, 输出会逐条列出:

```text
doc/xxx.md:12:81 error MD013/line-length Line length [Expected: 80; Actual: 111]
```

格式为 `文件:行:列 级别 规则名/规则说明 详情`, 可直接据此定位

### 检查整个仓库

```bash
cd /path/to/project_root
markdownlint-cli2 "**/*.md" --config ./.config/.markdownlint.jsonc
```

### 检查某个目录

```bash
cd /path/to/project_root
markdownlint-cli2 "doc/**/*.md" --config ./.config/.markdownlint.jsonc
```

### 自动修复

```bash
cd /path/to/project_root
markdownlint-cli2 --fix "doc/ubuntu_env/markdownlint.md" --config ./.config/.markdownlint.jsonc
```

只能修可自动修复的规则 (列表标记, 空行, 围栏缩进等). 行宽这类需要人工判断的规则不会被改动

### 用于脚本或提交前检查

```bash
cd /path/to/project_root
markdownlint-cli2 "**/*.md" --config ./.config/.markdownlint.jsonc || exit 1
```

退出码: `0` 表示无问题, `1` 表示存在问题
