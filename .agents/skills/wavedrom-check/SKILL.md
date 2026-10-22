---
name: wavedrom-check
description: "校验 WaveDrom 波形描述 (*.json5): 用已装的 wavedrom 命令行渲染一遍, 再检查各行拍数 / data / node / edge 结构与同拍标签重叠, 给出退出码与定位."
whenToUse: "写完或改完 doc/design_plan/wavedrom_render/*.json5 之后; 或用户要求确认某张波形图能不能渲染, 有没有压字, 想导出 SVG 时."
---

# wavedrom-check

在**仓库根目录**执行:

```bash
node .agents/skills/wavedrom-check/check-wavedrom.mjs doc/design_plan/wavedrom_render/sdtlb.json5   # 单个
git ls-files -z "*.json5" | xargs -0 node .agents/skills/wavedrom-check/check-wavedrom.mjs          # 已跟踪的全部

# 顺带把渲染结果导成 SVG (贴进文档时用; 只能配一个文件)
node .agents/skills/wavedrom-check/check-wavedrom.mjs -o /tmp/sdtlb.svg doc/design_plan/wavedrom_render/sdtlb.json5
```

- 通过时每个文件一行 `ok <文件> (<拍数> 拍, <行数> 行)`, 退出码 `0`
- 有问题时退出码 `1`, 输出形如 `FAIL <文件> -> <原因>`: 渲染报错 (json5 语法错会带 `行:列`),
  各行 wave 长度不一致, `|` 空档位置各行不一样, `data` 个数与数据格对不上,
  `edge` 引用了不存在的节点, 相邻两拍写了同一个电平 (`00` / `11`), 同一行相邻标签重叠
- **电平不要连着写**: 要延续 `0` / `1` 用 `.` (`0.` / `1.`); 写成 `00` / `11` 时 wavedrom 会用
  `0m0` / `1m1` 这两个字形, 在拍的中间画一个半高的三角凸起 —— 就是毛刺. 相邻的不同电平 (`01` / `10`)
  不算问题, 那是真的跳变
- 文件读不到, 参数不对, 或找不到 `wavedrom` 命令时退出码 `2`
- 渲染交给已装的 `wavedrom` 命令行 (npm 包 3.7.0); 要换一份就 `WAVEDROM=/path/to/wavedrom node ...`
- **别只跑 `wavedrom --input` 就收工**: 它只在 json5 解析失败时给非 `0`,
  毛刺 / 各行拍数不齐 / `data` 给多给少 / `edge` 指向不存在的节点 / 标签压到一起, 它一律退 `0`,
  这些正是本脚本补的部分
- 它只回答 "能不能渲染 + 结构自洽 + 标签不打架": 波形语义对不对 (请求拍 / 响应拍, 数据画错)
  与布局好不好看, 都不判断; 标签宽度按字数估 (CJK 15px, 其它 8px), 边界情况以人看图为准
- 结构检查是**本仓库的约定** (各行等长, `|` 对齐, `data` 与数据格一一对应, 电平用 `.` 续接),
  不是 wavedrom 的语法要求; 毛刺那条只查 `0` / `1` —— `hh` / `ll` 重复是时钟标记, `22` 重复是
  两个数据格, 语义不同, 不在此列

波形图放哪, 注释写什么, 怎么放进文档 (导出 SVG, 不要把 json5 贴进 Markdown) 见
[`doc/ubuntu_env/wavedrom_render.md`](../../../doc/ubuntu_env/wavedrom_render.md);
图表形式选择以 [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准.
