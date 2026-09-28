---
name: markdown-lint-check
description: "检查 Markdown 的排版规范: 用仓库自己的规则集跑 markdownlint-cli2, 可按需自动修复, 并给出退出码与问题定位."
whenToUse: "写完或改完任意 Markdown 之后; 或用户要求检查 Markdown 排版, 行宽, 标题与列表格式时."
---

# markdown-lint-check

`markdown-check` 的第一项 (排版); 第二项是图语法检查 [`markdown-mermaid-check`](../markdown-mermaid-check/SKILL.md)

在**仓库根目录**执行. `--config` 必须带: markdownlint-cli2 不向上级目录查找配置,
省略后会退回默认规则, 报出一堆 `MD013` / `MD033` 之类的假问题

```bash
markdownlint-cli2 "doc/**/*.md" --config ./.config/.markdownlint.jsonc        # 只查 doc 目录
markdownlint-cli2 "**/*.md" --config ./.config/.markdownlint.jsonc            # 整个仓库
markdownlint-cli2 "doc/ubuntu_env/ruff.md" --config ./.config/.markdownlint.jsonc   # 单个文件
```

- 退出码 `0` 表示无问题, `1` 表示存在问题; 输出格式为 `文件:行:列 级别 规则名/说明 详情`
- 能自动修的只有列表标记, 空行, 围栏缩进这类规则, 行宽等要人工判断:

  ```bash
  markdownlint-cli2 --fix "doc/**/*.md" --config ./.config/.markdownlint.jsonc
  ```

- 它**只覆盖排版**, 不检查图表形式 (该用 Mermaid 还是文件型图片), 图片目录与命名, 半角标点等约定
- 文档里含 Mermaid 时, 改完还要再跑一遍 `markdown-mermaid-check`

规则集内容与更多用法 (按执行目录推导 `--config` 相对路径等) 见
[`doc/ubuntu_env/markdownlint.md`](../../../doc/ubuntu_env/markdownlint.md);
写作约定以 [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准.
