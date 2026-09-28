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

## 目录约定

- `doc/`: 项目文档. 设计方案放在各自的 `<文档名>/` 目录内, 图片放在同级的 `image/<文档名>/`.
- `doc/ubuntu_env/`: 本机 (Ubuntu) 环境与工具链说明, 一工具一文件: `nodejs.md`, `markdownlint.md`,
  `ruff.md`, `chromium.md`, `mermaid.md`.
- `.agents/notes/`: 只放决策与理由记录 (为什么这么定), 不放操作手册.
- `.agents/skills/`: 需要按需加载给 agent 的能力 (带 YAML frontmatter 的 `SKILL.md`).
