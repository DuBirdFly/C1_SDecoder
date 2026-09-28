---
name: markdown-mermaid-check
description: "校验 Markdown 里 mermaid 围栏块的语法: 用本机已安装的 mermaid-check 命令逐块 parse, 不需要浏览器, 秒级返回."
whenToUse: "写完或改完含 mermaid 图的 Markdown 之后; 或用户要求验证某张 Mermaid 图是否能正常渲染时."
---

# markdown-mermaid-check

`markdown-check` 的第二项 (图语法); 第一项是排版检查 [`markdown-lint-check`](../markdown-lint-check/SKILL.md)

改动含 Mermaid 的 Markdown 后, 在仓库根执行:

```bash
git ls-files -z "*.md" | xargs -0 mermaid-check   # 已跟踪的 md 文件
mermaid-check doc/ubuntu_env/mermaid.md           # 还没 git add 的新文件直接传路径
```

- 退出码 `0` 表示全部通过, `1` 表示有块语法错误, `2` 表示有文件读不到或没给参数
- 报错形如 `FAIL <file>:<行号> -> Parse error on line N`, 按行号回到那块图去修, 修完重跑
- 它只回答"语法对不对", **不检查**节点数量, 布局可读性, 图注写法, 也不判断目标平台是否支持新语法

命令实体在 `~/.local/share/mermaid-check/` (`check-mermaid.mjs` + npm 依赖),
入口在 `~/.local/bin/mermaid-check`; 位置与原理, 换机器时的重建步骤, 以及备用方案 (`mmdc` 真渲染)
都写在 [`doc/ubuntu_env/mermaid.md`](../../../doc/ubuntu_env/mermaid.md).

图该怎么画 (形式选择, 命名, 引用格式) 以 [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准.
