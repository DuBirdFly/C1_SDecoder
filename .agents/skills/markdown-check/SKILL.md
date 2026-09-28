---
name: markdown-check
description: "Markdown 改完后的总检查入口: 先跑排版检查 (markdownlint), 文档含 Mermaid 时再跑图语法检查 (mermaid-check), 两项都过才算完成."
whenToUse: "写完或改完任意 Markdown 之后; 或不确定该跑哪项 Markdown 检查时先用这个."
---

# markdown-check

Markdown 改完后的总入口: 第一项**每次都跑**, 第二项只在文档含 mermaid 围栏块时跑.
两条命令都在仓库根目录执行, 且都必须带 `--config` (markdownlint-cli2 不向上级目录查找配置)

```bash
# 1. 排版检查 (markdownlint): 标题, 空行, 列表, 围栏, 行宽等
markdownlint-cli2 "doc/**/*.md" --config ./.config/.markdownlint.jsonc

# 2. 图语法检查 (mermaid): 只在文档含 mermaid 围栏块时需要
git ls-files -z "*.md" | xargs -0 mermaid-check
mermaid-check doc/ubuntu_env/mermaid.md     # 还没 git add 的新文件直接传路径
```

- 两项都要退出码 `0` 才算过: markdownlint 报 `文件:行:列 级别 规则名/说明 详情`,
  mermaid-check 报 `FAIL <文件>:<行号> -> Parse error on line N`
- 排版问题能用 `--fix` 自动修一部分; 图语法错误只能回文档改源码
- 细节, 边界与坑分在两个子 skill 里:
  [`markdown-lint-check`](../markdown-lint-check/SKILL.md) 管排版,
  [`markdown-mermaid-check`](../markdown-mermaid-check/SKILL.md) 管图语法
- 写作约定 (图表形式选择, 图片命名与引用, 半角标点) 以
  [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准
