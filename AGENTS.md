# AGENTS.md

本文件是 agent 的常驻入口: 只写每次都要遵守的约定, 细节一律指向唯一的事实来源, 不在这里复制正文.

## 写 Markdown 文档

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

## 写 python 文件

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

注: 不要顺手格式化整个仓库, 只格式化本次改动的文件; 要全量重排就单独提一个提交.

## 写 Verilog / SystemVerilog 文件

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

注: AGENTS 应该使用 `simulation_agent` 作为仿真入口, 而不是 `simulation`

注: 手搓 `vcs` 验证 SV 语法 / 语义的一次性探针, 放仓库根的 `.probe/` 下 (已 gitignore); 验证设计与 tb 仍然只用 `simulation_agent`

## 提交

注: 用户没有明确说 "git" / "git commit" 时, 不要自己提交; 改完就停在工作区, 由用户决定何时提交.

