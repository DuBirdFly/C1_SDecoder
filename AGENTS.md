# AGENTS.md

本文件是 agent 的常驻入口: 只写每次都要遵守的约定, 细节一律指向唯一的事实来源, 不在这里复制正文.

## 写 Markdown 文档

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

注: 不要主动把 mermaid 图渲染成图片来核对 (AI 读图慢), 图的效果由用户看; agent 只跑 `script/ci/check.sh mermaid` 做语法检查, 需要核对渲染效果时明确说明并请用户确认

## 写 python 文件

见 [`CONTRIBUTING.md`](CONTRIBUTING.md)

注: 不要顺手格式化整个仓库, 只格式化本次改动的文件; 要全量重排就单独提一个提交.

## 写 Verilog / SystemVerilog 文件

见 [`doc/sv 编写规范.md`](doc/sv%20编写规范.md)

注: AGENTS 应该使用 `simulation_agent` 作为仿真入口, 而不是 `simulation`

注: 手搓 `vcs` 验证 SV 语法 / 语义的一次性探针, 放仓库根的 `.probe/` 下 (已 gitignore); 验证设计与 tb 仍然只用 `simulation_agent`

注: 在 `.probe/` 下跑一次性探针时要带 `cd .probe &&`, 让 `vcs` 在 `.probe/` 里执行 (否则 `csrc/` 等生成物会落在当前目录); 需要复用仓库的 filelist 就在 `.probe/` 里生成一份带 `../rtl` 前缀的副本, 不要回到仓库根目录跑

注: 验证只跑当次改动相关的 tb, 不要全量跑 (太慢); 需要全量 / 回归时用 `-j` 之类的并行方式跑.

注: UVM testbench 的编写约定另见 [`doc/uvm 编写规范.md`](doc/uvm%20编写规范.md)

## 提交

注: 用户没有明确说 "git" / "git commit" 时, 不要自己提交; 改完就停在工作区, 由用户决定何时提交.

