# wavedrom 渲染与校验

本文件面向 **AI agent**: 写完或改完 `*.json5` 的 WaveDrom 波形描述之后, 用它确认图能渲染出来.
"能不能渲染" 用命令行确认 (`wavedrom --input`, 见 "npm 官方 CLI"); 命令行**不查**结构与标签重叠,
那部分按 "agent 自检清单" 自己核对.

波形源文件怎么写, 要不要贴进 Markdown, 以 [doc/md文件编写规范.md](../md文件编写规范.md) 的 "图表" 为准:
需要出图时导出 SVG / PNG, 按文件型图片规范命名与引用. `doc/design_plan/wavedrom_render/` 下的
json5 就是这些图的源文件.

## 为什么必须过一遍

- `json5` 语法错 CLI 会报, 但报错是 node 的栈, 要自己按末尾的 `行:列` 回源文件找
- 语法没错也可能画错: wave 里写错字符会让这条线整体错位, `data` 给多给少对不上数据格,
  `|` 空档位置不一致, 标签压到隔壁 —— **这些 CLI 一律不报错**, 退出码照样是 `0` (实测)
- 所以 "跑过命令" 只等于 "json5 解析得过", 图对不对必须看生成的 SVG, 结构按清单自己数
- 结构那几条可以一次跑完: `node .agents/skills/wavedrom-check/check-wavedrom.mjs <文件>`

## 渲染与导出方式

| 方式 | 适用场景 | 代价 |
| --- | --- | --- |
| npm 官方 CLI (`wavedrom --input`) | **已装 (3.7.0)**: 确认能不能渲染, 把 json5 转成 SVG | 只出 SVG, 结构与重叠一概不查 |
| <https://wavedrom.com/editor.html> | 要看图 / 手改试语法时 | 要人手粘贴, 版本不一定与本地一致 |

## npm 官方 CLI (已装, agent 默认用这个确认渲染)

```bash
wavedrom --input doc/design_plan/wavedrom_render/sdtlb.json5 > /tmp/sdtlb.svg
wavedrom --input doc/design_plan/wavedrom_render/sdtlb.json5 --indent 2 > /tmp/sdtlb.svg   # 带缩进
```

- 装在 `/usr/lib/node_modules/wavedrom`, 命令是 `/usr/bin/wavedrom` 的软链 (所以升 / 删都要 `sudo npm`)
- 只把 SVG 写到 stdout, **没有 `-o` 参数**, 输出路径自己用 `>` 给; 除 `--input` / `--indent` 外不收别的参数
- 退出码: `0` = 出了图; `1` = json5 语法错, 此时 stdout 为空, 报错是 node 的栈, 末尾的 `行:列` 指在原文件上
- 退出码 `0` 只代表 "json5 解析得过 + 画得出图", 结构对不对它不查, 所以下面这些仍要人工看图核对:
  - `data` 个数与数据格对不上
  - `|` 空档位置不一致
  - `edge` 引用的节点不存在
  - 标签压到隔壁
- 皮肤只带 `default` / `narrow` / `lowkey`: 写其它的不报错, 但静默回落到 `default`

## 写波形图的约定

- 源文件放在 `doc/design_plan/wavedrom_render/`, 文件名与模块同名 (如 `sdtlb.json5`);
  `example.json5` 是个现成的示例, 可当模板
- 长的信号名写进行名那一列 (`name`), 不要塞进 `data` 标签 —— 数据格只有一拍宽, 长了会压到隔壁
- 要放进 Markdown 时: 导出 SVG, 按 [文件型图片规范](../md文件编写规范.md) 命名与引用并写图注,
  正文里不要同时留 json5 源码

## agent 自检清单

改完或新增 `*.json5` 波形描述, 逐条过一遍 (结构那几条没有工具兜底, 得自己数):

- [ ] 文件名与模块同名, 放在 `doc/design_plan/wavedrom_render/`
- [ ] 跑过 `wavedrom --input <文件> > /tmp/x.svg`, 退出码为 `0`, stdout 是 `<svg ...` 开头
- [ ] 各行的拍数一致, `|` 位置一致, `data` 个数与数据格数一致
- [ ] `node` 长度与 `wave` 等长, `edge` 引用的节点都在 `node` 里出现过
- [ ] 长的名字放在行名里, `data` 标签短到不会压到隔壁
- [ ] 要贴进 Markdown 时导出 SVG 并写图注, 正文里不放 json5 源码
