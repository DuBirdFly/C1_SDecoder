# wavedrom 渲染与校验

本文件面向 **AI agent**: 写完或改完 `*.json5` 的 WaveDrom 波形描述之后, 用它确认图能渲染出来.
人看图, 导出图片在编辑器里做, 见 "在编辑器里渲染与导出"; agent 用命令行校验, 见 "wavedrom-check".

波形源文件怎么写, 要不要贴进 Markdown, 以 [doc/md文件编写规范.md](../md文件编写规范.md) 的 "图表" 为准:
WaveDrom 在 GitHub 与常见编辑器预览里**不会自动渲染**, 所以**不把 json5 贴进 Markdown**;
需要出图时导出 SVG / PNG, 按文件型图片规范命名与引用. `doc/design_plan/wavedrom_render/` 下的
json5 就是这些图的源文件.

## 为什么必须校验

- 写错了在编辑器里往往是一块报错文字或空白, 而且 wavedrom 只给 "文件级" 的说明, 不指到行,
  语法错误要自己按报错信息回源文件找
- 渲染器是 VSCode 扩展自带的 wavedrom (浏览器 bundle), 版本随扩展走; 语法与皮肤差异只能以它为准
- 语法过了只是底线: 一行少写一个字符会让这条线整体错位, `data` 标签给多给少,
  `|` 空档位置各行不一致, 一格塞太长的标签压到隔壁 —— 这些 wavedrom 都不报错,
  得靠结构检查与重叠检查兜底

## 渲染与校验方式

| 方式 | 适用场景 | 代价 |
| --- | --- | --- |
| `wavedrom-check` 命令 | **agent 默认用这个**: 复用扩展自带的 wavedrom 无头渲染 | 无额外成本, 秒级, 不需要浏览器与网络 |
| 编辑器里的扩展 | 人看图, 导出 SVG / PNG | 要装 VSCode 扩展; agent 看不到界面 |
| <https://wavedrom.com/editor.html> | 人工快速试语法 | 要人手粘贴, 版本不一定与扩展一致 |

### 在编辑器里渲染与导出

装扩展 [WaveDrom Render & Live Edit](https://marketplace.visualstudio.com/items?itemName=bmpenuelas.waveform-render)
(`bmpenuelas.waveform-render`), 然后:

- 打开 `.json5` (或 `.json`) -> 按 `Ctrl+K` 再按 `Ctrl+D` 出图; 按 `Ctrl+K` 再按 `Ctrl+L` 开实时预览
- 出图的标签页里右键可 `Save as SVG` / `Save as PNG`, 也可以用命令面板里的
  `Waveform Render: Copy Save as SVG` / `Waveform Render: Copy Save as PNG`
- 扩展自带 `default` / `dark` / `lowkey` / `narrow` 等皮肤, 不特别指定时用 `default`
- 扩展的读法是: 把整份文本塞进 `<script type="WaveDrom">` 再 `eval` 求值.
  所以 json5 里可以写 `//` 注释与不带引号的键 —— 本仓库的源文件都带注释, 就是为了写清时序口径

### wavedrom-check (推荐)

原理: 直接复用扩展自带的 `localScripts/wavedrom.min.js` (wavedrom 的浏览器 bundle),
用 node 补上 `document` / `DOMParser` 垫片, 走扩展 webview 同一条路径
(`eval(innerHTML)` -> `WaveDrom.eva` -> `WaveDrom.RenderWaveForm`), 因此**不需要浏览器, 也不需要联网**

用法 (在仓库根执行):

```bash
git ls-files -z "*.json5" | xargs -0 wavedrom-check          # 已跟踪的 json5 全部
wavedrom-check doc/design_plan/wavedrom_render/sdtlb.json5   # 还没 git add 的新文件直接传路径

# 顺带把渲染结果导成 SVG (要贴进文档时用)
wavedrom-check -o /tmp/sdtlb.svg doc/design_plan/wavedrom_render/sdtlb.json5
```

输出形如:

```text
ok   doc/design_plan/wavedrom_render/sdtlb.json5 (9 拍, 7 行)
ok   doc/design_plan/wavedrom_render/example.json5 (9 拍, 4 行)

2 个文件, 0 个失败 (wavedrom 3.7.0)
```

退出码:

| 退出码 | 含义 | 输出 |
| --- | --- | --- |
| `0` | 全部通过 | 每个文件一行 `ok <文件> (<拍数> 拍, <行数> 行)` |
| `1` | 渲染 / 结构 / 标签重叠有问题 | `FAIL <文件> -> <原因>` |
| `2` | 文件读不到, 参数不对, 或找不到 `wavedrom.min.js` | `SKIP <文件> -> ENOENT`, 或用法提示 |

它在一个文件内查这些:

| 检查项 | 报错样例 |
| --- | --- |
| 能不能渲染 | `Error in WaveJS: SyntaxError: Unexpected token ')'` |
| 各行的 wave 长度一致 | `各行的 wave 长度不一致: 3 / 4` |
| `\|` 空档位置各行一致 | `"\|" (空档) 的位置各行不一样, 各行的拍对不齐: [2] [1]` |
| `data` 个数与数据格数一致 | `req_pa[16:0]: 数据格 3 个, data 给了 2 个` |
| `node` 长度与 wave 一致, `edge` 引用的节点存在 | `edge "a~>c" 引用的节点 "c" 没有在 node 里出现过` |
| 同一行相邻标签不重叠 | `req_hit_tag_item / req_hit_data_item: 标签重叠 "A 读出" 与 "B 读出"` |

同一个命令也做成了本项目的 skill (`.agents/skills/wavedrom-check/SKILL.md`), agent 在会话里能自动看到它,
不必每次翻这份文档

### 装在哪, 怎么重建

命令实体与依赖都放在 `$HOME` 下 (与 `mermaid-check` 一致): 不占仓库空间, 也不会被临时目录清理扫掉

```text
~/.local/share/wavedrom-check/check-wavedrom.mjs   # 脚本 (唯一实体, 没有 npm 依赖)
~/.local/bin/wavedrom-check                        # 命令入口 (wrapper; 该目录已在 PATH 里)
```

前置只有两样:

- `node` (实测 v24)
- 一个 `wavedrom.min.js`: 默认按 `bmpenuelas.waveform-render-*` 找 VSCode 扩展自带的最高版本
  (`~/.vscode-server/extensions` 与 `~/.vscode/extensions` 都会找); 找不到扩展, 或想指定别的版本时, 用
  `WAVEDROM_JS=/path/to/wavedrom.min.js wavedrom-check ...` (任何一份 wavedrom 浏览器 bundle 都行)

重建 (换机器或脚本丢了):

```bash
mkdir -p ~/.local/share/wavedrom-check
# 把下面 "check-wavedrom.mjs 源码" 存成 ~/.local/share/wavedrom-check/check-wavedrom.mjs

printf '#!/bin/sh\nexec node "$HOME/.local/share/wavedrom-check/check-wavedrom.mjs" "$@"\n' > ~/.local/bin/wavedrom-check
chmod +x ~/.local/bin/wavedrom-check
```

注: 不要放在 `/tmp` (会被清理) 或 `~/.cache` (语义是缓存, 可能被清理工具删掉);
`~/.local/share` 是 XDG 的数据目录, 就是放这种东西的地方

#### check-wavedrom.mjs 源码

```js
#!/usr/bin/env node
// wavedrom-check: 校验 WaveDrom 波形描述 (*.json5) 能不能渲染, 结构是否自洽.
//
// 复用 VSCode 扩展 "WaveDrom Render & Live Edit" 自带的 localScripts/wavedrom.min.js
// (wavedrom 的浏览器 bundle), 用 node 补上 document / DOMParser 垫片, 走扩展同一条路径:
//   eval(innerHTML) -> WaveDrom.eva -> WaveDrom.RenderWaveForm
// 因此不需要浏览器, 也不需要联网.
//
// 用法: wavedrom-check [-o <out.svg>] <file.json5> [...]
// 退出码: 0 = 全部通过; 1 = 渲染 / 结构 / 标签重叠有问题; 2 = 文件读不到或没给参数
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { join, dirname } from "node:path";
import { homedir } from "node:os";

// ---- wavedrom.min.js: 先用 $WAVEDROM_JS, 否则取 VSCode 扩展自带的最高版本 ----
function findBundle() {
    if (process.env.WAVEDROM_JS) {
        return existsSync(process.env.WAVEDROM_JS) ? process.env.WAVEDROM_JS : null;
    }
    const roots = [
        join(homedir(), ".vscode-server", "extensions"),
        join(homedir(), ".vscode", "extensions"),
        join(homedir(), ".vscode-server-insiders", "extensions"),
    ];
    const found = [];
    for (const root of roots) {
        if (!existsSync(root)) continue;
        for (const name of readdirSync(root)) {
            if (!name.startsWith("bmpenuelas.waveform-render-")) continue;
            const js = join(root, name, "localScripts", "wavedrom.min.js");
            if (existsSync(js)) found.push({ name, js });
        }
    }
    if (found.length === 0) return null;
    found.sort((a, b) => a.name.localeCompare(b.name, "en", { numeric: true }));
    return found[found.length - 1].js;
}

// ---- 垫片: 浏览器 bundle 需要 window / document / DOMParser ----
function loadWaveDrom(bundle) {
    globalThis.window = {};
    let svg = null;
    const node = { childNodes: [], removeChild() {}, insertBefore() {}, setAttribute() {}, appendChild() {} };
    let source = "";
    globalThis.DOMParser = class {
        parseFromString(text) {
            svg = text;
            return { firstChild: {} };
        }
    };
    // eva 读 innerHTML, RenderWaveForm 拿同一个元素当画布 (要 childNodes / insertBefore)
    globalThis.document = {
        getElementById: () => ({ innerHTML: source, ...node }),
        createElement: () => node,
        querySelectorAll: () => [],
    };
    // 皮肤: 与扩展 webview 一样把 skins/*.js 都装上 (每个文件往 WaveSkin 里塞一个键)
    const skinDir = join(dirname(bundle), "skins");
    for (const name of existsSync(skinDir) ? readdirSync(skinDir) : []) {
        if (name.endsWith(".js")) (0, eval)(readFileSync(join(skinDir, name), "utf8"));
    }
    if (globalThis.WaveSkin) globalThis.window.WaveSkin = globalThis.WaveSkin;
    createRequire(import.meta.url)(bundle);
    const wavedrom = globalThis.window.WaveDrom;
    return {
        version: wavedrom.version,
        render(text) {
            source = text;
            svg = null;
            const tree = wavedrom.eva("InputJSON_0");   // 与扩展 webview 里同一条路径
            const baked = JSON.stringify(tree);
            wavedrom.RenderWaveForm(0, tree, "WaveDrom_Display_");
            return { tree, baked, svg };
        },
    };
}

// ---- 结构自检: 各行走同样多的拍; data 个数与数据格数一致; edge 引用的节点存在 ----
const DATA_CHARS = "=23456789";
function checkStructure(obj) {
    const lanes = (obj?.signal ?? []).filter((lane) => lane && lane.wave);   // {} 是空行分隔
    if (lanes.length === 0) return ["signal 里没有带 wave 的行"];
    const problems = [];
    const widths = new Set(lanes.map((lane) => lane.wave?.length ?? 0));
    if (widths.size > 1) {
        problems.push(`各行的 wave 长度不一致: ${[...widths].sort((a, b) => a - b).join(" / ")}`);
    }
    for (const lane of lanes) {
        const wave = lane.wave ?? "";
        const cells = [...wave].filter((c) => DATA_CHARS.includes(c)).length;
        const labels = (lane.data ?? []).length;
        if (cells !== labels) {
            problems.push(`${lane.name ?? "(无名)"}: 数据格 ${cells} 个, data 给了 ${labels} 个`);
        }
        if (lane.node && lane.node.length !== wave.length) {
            problems.push(`${lane.name ?? "(无名)"}: node 长度 ${lane.node.length} != wave 长度 ${wave.length}`);
        }
    }
    const gaps = new Set(lanes.map((lane) => [...lane.wave].map((c, i) => (c === "|" ? i : -1)).filter((i) => i >= 0).join(",")));
    if (gaps.size > 1) {
        problems.push(`"|" (空档) 的位置各行不一样, 各行的拍对不齐: ${[...gaps].map((g) => `[${g}]`).join(" ")}`);
    }
    const letters = new Set(lanes.flatMap((lane) => [...(lane.node ?? "")]).filter((c) => c !== "."));
    for (const edge of obj?.edge ?? []) {
        for (const letter of String(edge).match(/[A-Za-z0-9]/g) ?? []) {
            if (!letters.has(letter)) problems.push(`edge "${edge}" 引用的节点 "${letter}" 没有在 node 里出现过`);
        }
    }
    return problems;
}

// ---- 标签重叠: 取渲染结果里每行文字的绝对 x, 同拍互相压到就算问题 ----
function checkOverlap(svg) {
    const problems = [];
    if (!svg) return ["没有拿到渲染结果"];
    const stack = [[0, 0]];
    const rows = new Map();
    const names = new Map();
    const key = (v) => Math.round(v * 10) / 10;
    const tagRe = /<g\b[^>]*>|<\/g>|<text\b[^>]*>(.*?)<\/text>/gs;
    for (const m of svg.matchAll(tagRe)) {
        const tok = m[0];
        if (tok.startsWith("<g")) {
            const tr = /translate\(\s*(-?[\d.]+)[ ,]+(-?[\d.]+)/.exec(tok);
            const [x, y] = tr ? [Number(tr[1]), Number(tr[2])] : [0, 0];
            stack.push([stack[stack.length - 1][0] + x, stack[stack.length - 1][1] + y]);
        } else if (tok === "</g>") {
            if (stack.length > 1) stack.pop();
        } else {
            const classAttr = /\sclass="([^"]*)"/.exec(tok)?.[1] ?? "";
            const ay0 = stack[stack.length - 1][1] + (Number(/\sy="(-?[\d.]+)"/.exec(tok)?.[1]) || 0);
            if (classAttr === "info") {                      // 左侧信号名那一列: 记下来给报错定位
                names.set(key(ay0), m[1].replace(/<[^>]+>/g, "").trim());
                continue;
            }
            const text = m[1].replace(/<[^>]+>/g, "").trim();
            if (!text) continue;
            const x = Number(/\sx="(-?[\d.]+)"/.exec(tok)?.[1] ?? 0);
            const y = Number(/\sy="(-?[\d.]+)"/.exec(tok)?.[1] ?? 0);
            const anchor = /text-anchor="(\w+)"/.exec(tok)?.[1] ?? "start";
            const width = [...text].reduce((sum, c) => sum + (c.codePointAt(0) > 0x2e80 ? 15 : 8), 0);
            const ax = stack[stack.length - 1][0] + x;
            const ay = stack[stack.length - 1][1] + y;
            const left = anchor === "middle" ? ax - width / 2 : anchor === "end" ? ax - width : ax;
            const rowKey = key(ay);
            if (!rows.has(rowKey)) rows.set(rowKey, []);
            rows.get(rowKey).push({ text, left, right: left + width });
        }
    }
    for (const [y, items] of rows) {
        items.sort((a, b) => a.left - b.left);
        for (let i = 1; i < items.length; i++) {
            if (items[i].left < items[i - 1].right) {
                const where = names.get(y) ?? `y=${Math.round(y)}`;
                problems.push(`${where}: 标签重叠 "${items[i - 1].text}" 与 "${items[i].text}"`);
            }
        }
    }
    return problems;
}

// ---- 主流程 ----
const argv = process.argv.slice(2);
let out = null;
const files = [];
for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "-o") {
        out = argv[++i];
    } else {
        files.push(argv[i]);
    }
}
if (files.length === 0 || (out && files.length > 1)) {
    console.error("用法: wavedrom-check [-o <out.svg>] <file.json5> [...]");
    process.exit(2);
}

const bundle = findBundle();
if (!bundle) {
    console.error("找不到 wavedrom.min.js: 装 VSCode 扩展 bmpenuelas.waveform-render, 或用 WAVEDROM_JS 指过去");
    process.exit(2);
}

let failed = 0;
let total = 0;
const errors = [];
const originalLog = console.log;
console.log = (...args) => errors.push(args.join(" "));        // bundle 的报错走 console.log
const wavedrom = loadWaveDrom(bundle);
console.log = originalLog;

for (const file of files) {
    total += 1;
    let text;
    try {
        text = readFileSync(file, "utf8");
    } catch (error) {
        originalLog(`SKIP ${file} -> ${error.code ?? error.message}`);
        process.exitCode = 2;
        continue;
    }
    errors.length = 0;
    console.log = (...args) => errors.push(args.join(" "));
    const { baked, svg } = wavedrom.render(text);
    console.log = originalLog;

    const problems = [];
    let beats = 0;
    let lanes = 0;
    if (errors.length) {
        problems.push(errors[0].replace(/\s+/g, " ").trim());       // bundle 自己的报错信息
    } else if (baked.includes('"error')) {
        problems.push((/Error: [^"]*/.exec(baked)?.[0] ?? "渲染失败").replace(/\\"/g, '"'));
    }
    if (problems.length === 0) {
        let obj = null;
        try {
            obj = (0, eval)(`(${text})`);       // json5 兼容 (注释 / 不带引号的键) 靠 JS eval
        } catch { /* eva 已经报过错了, 走不到这里 */ }
        const sig = (obj?.signal ?? []).filter((lane) => lane && lane.wave);
        beats = [...(sig[0]?.wave ?? "")].filter((c) => c !== "|").length;
        lanes = sig.length;
        problems.push(...checkStructure(obj));
        problems.push(...checkOverlap(svg));
    }
    if (problems.length) {
        failed += 1;
        for (const problem of problems) originalLog(`FAIL ${file} -> ${problem}`);
    } else {
        originalLog(`ok   ${file} (${beats} 拍, ${lanes} 行)`);
        if (out) {
            writeFileSync(out, svg);
            originalLog(`     SVG -> ${out}`);
        }
    }
}

originalLog(`\n${total} 个文件, ${failed} 个失败 (wavedrom ${wavedrom.version})`);
if (failed > 0) process.exitCode = 1;
```

### 这个校验的边界

- **它只回答 "能不能渲染 + 结构自洽 + 标签不打架"**: 波形语义对不对 (请求拍 / 响应拍画错,
  数据画错) 与布局好不好看, 它都判断不了
- 标签宽度是按字数估的 (CJK 15px, 其它 8px), 重叠检查是估算; 边界情况以编辑器里看到的为准
- 它用的是扩展自带的那个 wavedrom 版本, 换成别的版本或别的平台, 结论不保证
- `data` 多给或者少给一律算失败: 基本都是笔误, 不算风格问题
- 结构检查是**本仓库的约定** (各行等长, `|` 对齐, `data` 与数据格一一对应), 不是 wavedrom 的语法要求

## 写波形图的约定

- 源文件放在 `doc/design_plan/wavedrom_render/`, 文件名与模块同名 (如 `sdtlb.json5`);
  `example.json5` 是扩展自带的示例, 可当模板
- 用 `//` 注释写清时序口径: 哪一拍是请求拍 / 响应拍, "有效" 怎么定义 (本仓库口径: clk 上升沿时置位),
  这一段画的是什么场景. 可参照 `doc/design_plan/wavedrom_render/sdtlb.json5`
- 长的信号名写进行名那一列 (`name`), 不要塞进 `data` 标签 —— 数据格只有一拍宽, 长了会压到隔壁
- 一张图控制在十几拍以内, 只表达一个场景; 背靠背 / 流水线用同一张图的后半段表达
- 要放进 Markdown 时: 导出 SVG, 按 [文件型图片规范](../md文件编写规范.md) 命名与引用并写图注,
  正文里不要同时留 json5 源码

## agent 自检清单

改完或新增 `*.json5` 波形描述, 逐条过一遍:

- [ ] 文件名与模块同名, 放在 `doc/design_plan/wavedrom_render/`
- [ ] 注释里写清了时序口径 (请求拍 / 响应拍, "有效" 的定义)
- [ ] 各行的拍数一致, `|` 位置一致, `data` 个数与数据格数一致
- [ ] 长的名字放在行名里, `data` 标签短到不会压到隔壁
- [ ] 跑过 `wavedrom-check`, 退出码为 `0`
- [ ] 要贴进 Markdown 时导出 SVG 并写图注, 正文里不放 json5 源码
