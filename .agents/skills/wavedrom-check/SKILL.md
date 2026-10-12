---
name: wavedrom-check
description: "校验 WaveDrom 波形描述 (*.json5): 复用 VSCode 扩展自带的 wavedrom 无头渲染一遍, 并检查各行拍数 / data / node / edge 结构与同拍标签重叠, 给出退出码与定位."
whenToUse: "写完或改完 doc/**/wavedrom_render/*.json5 之后; 或用户要求确认某张波形图能不能渲染, 有没有压字, 想导出 SVG 时."
---

# wavedrom-check

在**仓库根目录**执行:

```bash
wavedrom-check doc/design_plan/wavedrom_render/sdtlb.json5     # 单个文件
git ls-files -z "*.json5" | xargs -0 wavedrom-check            # 已跟踪的全部

# 顺带把渲染结果导成 SVG (要贴进文档时用)
wavedrom-check -o /tmp/sdtlb.svg doc/design_plan/wavedrom_render/sdtlb.json5
```

- 通过时每个文件一行 `ok <文件> (<拍数> 拍, <行数> 行)`, 退出码 `0`
- 有问题时退出码 `1`, 输出形如 `FAIL <文件> -> <原因>`: 渲染报错 (语法 / 语义),
  各行 wave 长度不一致, `|` 空档位置各行不一样, `data` 个数与数据格数对不上,
  `edge` 引用了不存在的节点, 同一行相邻标签重叠
- 文件读不到, 参数不对, 或找不到 `wavedrom.min.js` 时退出码 `2`
- 它复用 VSCode 扩展 `bmpenuelas.waveform-render` 自带的 `wavedrom.min.js`, 用 node 补
  `document` / `DOMParser` 垫片走扩展同一条路径, 不需要浏览器与网络; 找不到扩展时用
  `WAVEDROM_JS=/path/to/wavedrom.min.js` 指一份
- 它只回答 "能不能渲染 + 结构自洽 + 标签不打架", **不判断**波形语义 (请求拍 / 响应拍画对没有,
  数据画对没有), 也不判断布局好不好看; 标签重叠是按字数估算的

命令实体在 `~/.local/share/wavedrom-check/`, 入口 `~/.local/bin/wavedrom-check`:
位置, 原理, 完整源码与重建步骤见 [`doc/ubuntu_env/wavedrom_render.md`](../../../doc/ubuntu_env/wavedrom_render.md).

波形图放哪, 注释写什么, 怎么放进文档 (导出 SVG, 不要把 json5 贴进 Markdown) 见同一份文档;
图表形式选择以 [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md) 为准.
