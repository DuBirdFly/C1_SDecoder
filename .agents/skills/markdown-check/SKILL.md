---
name: markdown-check
description: "Markdown 改完后的总检查入口: 先跑排版检查 (markdownlint), 文档含 Mermaid 时再跑图语法检查 (mermaid-check), 两项都过才算完成."
whenToUse: "写完或改完任意 Markdown 之后; 或不确定该跑哪项 Markdown 检查时先用这个."
---

# markdown-check

Markdown 改完后的总入口: 第一项每次跑, 第二项只在文档含 mermaid 围栏块时跑.

```bash
script/ci/check.sh md          # 排版 (markdownlint), 规则集 .config/.markdownlint.jsonc
script/ci/check.sh mermaid     # 图语法, 没有 mermaid 块时自动跳过
```

两项都要退出码 `0` 才算过; 只查部分文件或 `--fix` 见 `script/ci/check.sh -h`,
规则与报错格式见 [`script/ci/check_markdown_lint.sh`](../../../script/ci/check_markdown_lint.sh) 与
[`script/ci/check_markdown_mermaid.sh`](../../../script/ci/check_markdown_mermaid.sh) 的 `-h`.

`mermaid-check` 装在 `~/.local/share/mermaid-check/` (入口 `~/.local/bin/mermaid-check`),
换机器时按该目录的 `package.json` 重装.

写作约定 (图表形式选择, 图片命名与引用, 半角标点) 以
[`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准.
