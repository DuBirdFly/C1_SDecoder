#!/usr/bin/env node
// check-wavedrom: 校验 WaveDrom 描述 (*.json5) 能不能渲染, 结构是否自洽, 标签有没有压在一起.
//
// 渲染交给已装的命令行 `wavedrom` (npm 包, 3.7.0): 本脚本只补它不查的部分 ——
//   - 波形图 (signal): 各行的 wave 是否等长, "|" (空档) 的位置是否各行一致
//   - 波形图: data 个数与数据格数是否一致, node 长度是否与 wave 等长, edge 引用的节点是否存在
//   - 波形图: 相邻两拍是否写了同一个电平 "0" / "1" (会画成 0m0 / 1m1 的毛刺, 应改用 ".")
//   - 位域图 (reg) 没有 lane / data / edge 的概念, 只查"能渲染"与"标签不重叠"
//   - 两种图都查: 同一行相邻标签是否重叠 (宽度按字数估: CJK 15px, 其它 8px)
//
// 用法: node script/ci/check-wavedrom.mjs [-o <out.svg>] <file.json5> [...]
// 退出码: 0 = 全部通过; 1 = 渲染 / 结构 / 标签重叠有问题; 2 = 文件读不到, 参数不对, 或找不到 wavedrom
import { readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const BIN = process.env.WAVEDROM ?? "wavedrom";
const MAX_BUFFER = 64 * 1024 * 1024;        // 一张图的 SVG 五十来 KB, 留足余量

// ---- 调命令行: 只认 --input, SVG 走 stdout, 出错是 node 的栈 (末尾带 行:列) ----
function run(args) {
    const res = spawnSync(BIN, args, { encoding: "utf8", maxBuffer: MAX_BUFFER });
    if (res.error?.code === "ENOENT") {
        console.error(`找不到 \`${BIN}\` 命令: 先装 npm 包 wavedrom (npm install -g wavedrom)`);
        process.exit(2);
    }
    if (res.error) throw res.error;
    return { status: res.status, stderr: (res.stderr ?? "").trim(), stdout: res.stdout ?? "" };
}

// ---- 从 wavedrom 的 stderr 里挑出真正那句 (node 栈里最后一行的版本号没用) ----
function pickError(stderr) {
    const lines = stderr.split("\n").map((line) => line.trim()).filter(Boolean);
    return lines.find((line) => /^(?:[A-Za-z]*Error|Uncaught)\b/.test(line)) ?? lines[lines.length - 1] ?? "";
}

// ---- 电平毛刺: 相邻两拍写同一个 "0"/"1" 时, wavedrom 会画 0m0 / 1m1 这种中间凸起的毛刺,
//      要延续电平得用 "." (0. / 1.); 跨 "|" 空档的不算 (空档本身就会断开) ----
const LEVEL_CHARS = "01";
function checkLevelGlitch(name, wave) {
    const problems = [];
    const chars = [...wave];
    for (let i = 1; i < chars.length; i++) {
        if (!LEVEL_CHARS.includes(chars[i]) || chars[i] !== chars[i - 1]) continue;
        problems.push(
            `${name}: wave 第 ${i} / ${i + 1} 拍连着两个 "${chars[i]}" —— 渲染会在中间画毛刺 (0m0 / 1m1),` +
            ` 要延续电平请把第 ${i + 1} 拍写成 "."`,
        );
    }
    return problems;
}

// ---- 结构自检: 各行走同样多的拍; data 个数与数据格数一致; edge 引用的节点存在 ----
const DATA_CHARS = "=23456789";
function checkStructure(obj) {
    const lanes = (obj?.signal ?? []).filter((lane) => lane && lane.wave);   // {} 是空行分隔
    if (lanes.length === 0) {
        // 位域图 (reg) 没有 lane / data / edge, 结构那几条不适用,
        // 只保留"能渲染"与"标签不重叠"两项; 两样都没有才是真拿错文件
        return Array.isArray(obj?.reg) ? [] : ["既没有 signal 里的 wave 行, 也没有 reg 位域"];
    }
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
        problems.push(...checkLevelGlitch(lane.name ?? "(无名)", wave));
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
    const stack = [[0, 0, "start"]];   // x / y / 继承下来的 text-anchor
    const rows = new Map();
    const names = new Map();
    const key = (v) => Math.round(v * 10) / 10;
    const tagRe = /<g\b[^>]*>|<\/g>|<text\b[^>]*>(.*?)<\/text>/gs;
    for (const m of svg.matchAll(tagRe)) {
        const tok = m[0];
        if (tok.startsWith("<g")) {
            // wavedrom 会写单参数的 translate(x) (只有 x 位移), 不能当成没有位移:
            // 位域图的字段名与位号全靠它定位, 漏掉就会把不相干的标签算成同一行
            const tr = /translate\(\s*(-?[\d.]+)(?:[ ,]+(-?[\d.]+))?/.exec(tok);
            const [x, y] = tr ? [Number(tr[1]), tr[2] === undefined ? 0 : Number(tr[2])] : [0, 0];
            const parent = stack[stack.length - 1];
            // text-anchor 常写在 <g> 上继承下来 (root 就是 middle), 只看 <text> 自己的属性会算错左右边界
            const anchor = /\stext-anchor="([a-z]+)"/.exec(tok)?.[1] ?? parent[2];
            stack.push([parent[0] + x, parent[1] + y, anchor]);
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
            const anchor = /text-anchor="([a-z]+)"/.exec(tok)?.[1] ?? stack[stack.length - 1][2];
            const width = [...text].reduce((sum, c) => sum + (c.codePointAt(0) > 0x2e80 ? 15 : 8), 0);
            const ax = stack[stack.length - 1][0] + x;
            const ay = stack[stack.length - 1][1] + (Number(/\sy="(-?[\d.]+)"/.exec(tok)?.[1]) || 0);
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
    } else if (argv[i] === "-h" || argv[i] === "--help") {
        console.log("用法: check-wavedrom.mjs [-o <out.svg>] <file.json5> [...]");
        process.exit(0);
    } else {
        files.push(argv[i]);
    }
}
if (files.length === 0 || (out && files.length > 1)) {
    console.error("用法: check-wavedrom.mjs [-o <out.svg>] <file.json5> [...]");
    process.exit(2);
}

const version = run(["--version"]).stdout.trim();
let failed = 0;
let total = 0;

for (const file of files) {
    total += 1;
    let text;
    try {
        text = readFileSync(file, "utf8");
    } catch (error) {
        console.log(`SKIP ${file} -> ${error.code ?? error.message}`);
        process.exitCode = 2;
        continue;
    }

    const rendered = run(["--input", file]);
    const problems = [];
    let obj = null;
    let shape = "";
    if (rendered.status !== 0) {
        problems.push(pickError(rendered.stderr) || `wavedrom 退出码 ${rendered.status}`);
    } else if (!rendered.stdout.startsWith("<svg")) {
        problems.push("wavedrom 没有把 SVG 输出到 stdout");
    }
    if (problems.length === 0) {
        try {
            obj = (0, eval)(`(${text})`);       // json5 兼容 (注释 / 不带引号的键) 靠 JS eval
        } catch { /* wavedrom 的 json5 解析已经过了, 走不到这里 */ }
        if (Array.isArray(obj?.reg)) {
            const bits = obj.reg.reduce((sum, field) => sum + (Number(field?.bits) || 0), 0);
            shape = `位域图, ${obj.reg.length} 个字段 / ${bits} 位`;
        } else {
            const lanes = (obj?.signal ?? []).filter((lane) => lane && lane.wave);
            const beats = [...(lanes[0]?.wave ?? "")].filter((c) => c !== "|").length;
            shape = `${beats} 拍, ${lanes.length} 行`;
        }
        problems.push(...checkStructure(obj));
        problems.push(...checkOverlap(rendered.stdout));
    }
    if (problems.length) {
        failed += 1;
        for (const problem of problems) console.log(`FAIL ${file} -> ${problem}`);
    } else {
        console.log(`ok   ${file} (${shape})`);
        if (out) {
            writeFileSync(out, rendered.stdout);
            console.log(`     SVG -> ${out}`);
        }
    }
}

console.log(`\n${total} 个文件, ${failed} 个失败 (wavedrom ${version})`);
process.exitCode = process.exitCode === 2 ? 2 : failed > 0 ? 1 : 0;
