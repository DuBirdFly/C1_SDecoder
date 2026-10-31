---
name: wavedrom-check
description: "校验 WaveDrom 波形描述 (*.json5): 用已装的 wavedrom 命令行渲染一遍, 再检查各行拍数 / data / node / edge 结构与同拍标签重叠, 给出退出码与定位."
whenToUse: "写完或改完 doc/design_plan/wavedrom_render/**/*.json5 之后; 或用户要求确认某张波形图能不能渲染, 有没有压字, 想导出 SVG 时."
---

# wavedrom-check

WaveDrom 描述 (`*.json5`) 检查: 渲染 + 结构自洽 + 标签重叠.

```bash
script/ci/check_wavedrom.sh          # 全部跟踪的 json5
script/ci/check_wavedrom.sh doc/design_plan/wavedrom_render/sdtlb/sdtlb_1.json5

# 导出 SVG (贴进文档用, 只能配一个文件)
node script/ci/check-wavedrom.mjs -o /tmp/sdtlb.svg <file.json5>
```

退出码 `0` 才算过, 失败项是 `FAIL <文件> -> <原因>`. 判据与写法约定 (波形 `wave` 怎么续电平,
位域 `reg` 与波形的区别) 见 [`script/ci/check-wavedrom.mjs`](../../../script/ci/check-wavedrom.mjs) 头注释.

波形放哪, 怎么放进文档见 [`doc/md文件编写规范.md`](../../../doc/md文件编写规范.md).
