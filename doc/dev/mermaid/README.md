# mermaid 校验

本文件面向 **AI agent**: 写完或改完含 Mermaid 的 Markdown 之后, 用它确认图能通过语法校验.
人看图、把 md 转 pdf/docx 各有各的办法, 不需要命令行, 本文件不涉及那部分.

哪些图该用 Mermaid, 哪些该改用文件型图片, 图的命名与引用格式, 都以
[doc/md文件编写规范.md](../../md文件编写规范.md) 的 "一. 图表" 为准

## 为什么必须校验

- 图写错了, 平台上的表现往往是**整块空白**或退化成代码块, 不会明确报错, 很容易被忽略
- 各平台内置的 mermaid 版本滞后于最新语法, 新语法可能在目标平台不认
- 语法正确只是底线: 节点太多, 节点里塞长句这类问题, parse 查不出来, 得按规范自己数

需要确认某平台的渲染版本时, 在文档里临时插一个 `info` 块, 预览会显示渲染器用的 mermaid 版本, 确认完删掉:

```mermaid
info
```

## 校验方法

| 方式 | 适用场景 | 代价 |
| --- | --- | --- |
| `mermaid-check` 命令 | **agent 默认用这个**: 本机已装好 | 无额外成本, 秒级, 不需要浏览器 |
| <https://mermaid.live> | 人工快速试语法 | 要人手粘贴, 不能批量 |
| `mmdc` 真渲染 | 需要最接近最终产物的确认 | 需要 Chromium (可 snap 安装, 见 [chromium 文档](../chromium/README.md)), 不作为 agent 的常规手段 |

### mermaid-check (推荐)

原理: 用 mermaid 自己的解析器 `mermaid.parse()` 逐块过一遍 mermaid 围栏块, 语法错误会抛异常.
mermaid 需要一个 DOM, 用 `jsdom` 顶上, 所以**不需要浏览器**, 离线也能跑

用法 (在仓库根执行):

```bash
git ls-files -z "*.md" | xargs -0 mermaid-check   # 已跟踪的 md 文件

# 还没 git add 的新文件不在 ls-files 里, 直接传路径
mermaid-check doc/dev/mermaid/README.md
```

输出形如:

```text
ok   doc/md文件编写规范.md:38
ok   doc/内存池化SDecoder和SMMU部件设计方案2.6/内存池化SDecoder和SMMU部件设计方案v2.6.md:53

9 个块, 0 个失败 (mermaid 12.0.0)
```

退出码:

| 退出码 | 含义 | 输出 |
| --- | --- | --- |
| `0` | 全部通过 | 每块一行 `ok`, 末行给块数与 mermaid 版本 |
| `1` | 有块语法错误 | `FAIL <文件>:<行号> -> Parse error on line N` |
| `2` | 有文件读不到, 或没给参数 | `SKIP <文件> -> ENOENT`, 或用法提示 |

同一个命令也做成了本项目的 skill (`.agents/skills/mermaid-check/SKILL.md`),
agent 在会话里能自动看到它, 不必每次翻这份文档

### 装在哪, 怎么重建

命令实体与依赖都放在 `$HOME` 下: 不占仓库空间, 也不会被临时目录清理扫掉

```text
~/.local/share/mermaid-check/    # check-mermaid.mjs + package.json + node_modules (约 230 MB)
~/.local/bin/mermaid-check       # 命令入口 (3 行 wrapper; 该目录已在 PATH 里)
```

换机器或依赖丢了, 照下面重建一次 (需要网络, `npm` 会重新拉包):

```bash
mkdir -p ~/.local/share/mermaid-check && cd ~/.local/share/mermaid-check
npm init -y
npm install --save mermaid jsdom      # 154 个包, 约 5 分钟
```

`~/.local/share/mermaid-check/check-mermaid.mjs`:

```js
#!/usr/bin/env node
// mermaid-check: 校验 Markdown 里 mermaid 围栏块的语法.
// 用 mermaid 自己的解析器逐块 parse, DOM 由 jsdom 顶上, 因此不需要浏览器.
// 用法: mermaid-check <file.md> [...]
// 退出码: 0 = 全部通过; 1 = 有块语法错误; 2 = 文件读不到或没给文件
import { readFileSync } from "node:fs";
import { JSDOM } from "jsdom";

const dom = new JSDOM("<!doctype html><html><body></body></html>");
globalThis.window = dom.window;
globalThis.document = dom.window.document;
try {
  Object.defineProperty(globalThis, "navigator", { value: dom.window.navigator, configurable: true });
} catch {
  // Node 自带只读 navigator 时忽略
}

const mermaid = (await import("mermaid")).default;
mermaid.initialize({ startOnLoad: false });

const files = process.argv.slice(2);
if (files.length === 0) {
  console.error("用法: mermaid-check <file.md> [...]");
  process.exit(2);
}

const BLOCK_RE = /^[ \t]*```mermaid[ \t]*\n([\s\S]*?)^[ \t]*```/gm;
let total = 0;
let failed = 0;

for (const file of files) {
  let text;
  try {
    text = readFileSync(file, "utf8");
  } catch (error) {
    console.error(`SKIP ${file} -> ${error.code ?? error.message}`);
    process.exitCode = 2;
    continue;
  }
  for (const m of text.matchAll(BLOCK_RE)) {
    total += 1;
    const line = text.slice(0, m.index).split("\n").length;
    try {
      await mermaid.parse(m[1]);
      console.log(`ok   ${file}:${line}`);
    } catch (error) {
      failed += 1;
      console.log(`FAIL ${file}:${line} -> ${String(error.message).split("\n")[0]}`);
    }
  }
}

const mermaidPkg = new URL("./node_modules/mermaid/package.json", import.meta.url);
const { version } = JSON.parse(readFileSync(mermaidPkg, "utf8"));
console.log(`\n${total} 个块, ${failed} 个失败 (mermaid ${version})`);
if (failed > 0) process.exitCode = 1;
```

`~/.local/bin/mermaid-check`:

```sh
#!/bin/sh
# mermaid-check: 校验 Markdown 里的 mermaid 围栏块 (实体与依赖在 ~/.local/share/mermaid-check/)
exec node "$HOME/.local/share/mermaid-check/check-mermaid.mjs" "$@"
```

写完 `chmod +x ~/.local/bin/mermaid-check`

注: 不要放在 `/tmp` (会被清理) 或 `~/.cache` (语义是缓存, 可能被清理工具删掉);
`~/.local/share` 是 XDG 的数据目录, 就是放这种东西的地方

### 这个校验的边界

- **它只回答"语法对不对"**, 不回答"布局好不好看""平台认不认", 也不检查节点数量与图注
- 脚本用正则找围栏块, 没有 Markdown 解析器精确: 文档里作为**示例**写出来的 mermaid 块
  (比如本文件上面那个 `info` 示例) 也会被一起校验, 属于可接受的误差
- `git ls-files` 默认会转义非 ASCII 路径, 所以要 `-z` 配 `xargs -0`, 不能写成 `$(git ls-files ...)`

实测: 规范与 2.6 设计方案里的 9 个块 (1 个 `info` + 8 个 `flowchart`) 全部通过;
故意写坏一个节点时报 `Parse error on line 4` 且退出码 `1`, 文件不存在时退出码 `2`

### mmdc (备用, 一般不用)

需要"真的渲染出来"时才有用: `npm install -g @mermaid-js/mermaid-cli` 后命令名是 `mmdc`:

```bash
mmdc -i input.mmd -o output.svg -t dark -b transparent
```

它需要一个 Chromium: 默认由 puppeteer 自己下载 (几百 MB, 受限网络下会失败, 实测报
`All providers failed for chrome ...`); 更省事的是装系统 Chromium 再用 `executablePath` 指过去,
安装与配置见 [doc/dev/chromium/README.md](../chromium/README.md).
`mmdc` 本身的细节见官方仓库 <https://github.com/mermaid-js/mermaid-cli>

## agent 自检清单

改完含 Mermaid 的 Markdown, 逐条过一遍:

- [ ] 围栏语言写的是 `mermaid`, 没有用 `mmd` / `mermaidjs` 之类的别名
- [ ] 节点文字含空格, 括号, 斜杠时用引号包住, 例如 `A["Home 侧 (SMMU)"]`
- [ ] 单张图节点数不超过 25 (超出就拆分或改用文件型图片), 节点里没有塞长句
- [ ] 同一张图只保留一种形式: 没有既留 Mermaid 源码又贴同一张图片
- [ ] 跑过 `mermaid-check`, 退出码为 `0`
- [ ] 该 Markdown 同时通过 markdownlint, 见 [doc/dev/markdownlint/README.md](../markdownlint/README.md)
