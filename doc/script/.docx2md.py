#!/usr/bin/env python3
"""将设计方案 .docx 转换为规范 Markdown，并导出其中的 PNG 插图。

行为说明:
  * 输入 .docx，输出 .md；输入输出路径均由命令行给出，相对路径按当前目录解析，
    因此请在 doc/script 目录下执行本脚本。
  * PNG 插图直接写进 Markdown，形式为 ![imageN](image/<输出md基名>/imageN.png)，
    图片同步导出到「输出文件所在目录/image/<输出md基名>/」，目录不存在时自动创建。
  * 非 PNG 图片（emf/wmf 等矢量图）不导出，仅在 Markdown 里以
    <!-- 非 PNG 图片未处理：xxx.emf --> 注释标明原有位置。

用法:
    cd doc/script
    python3 ./.docx2md.py <输入.docx> <输出.md>

示例:
    cd doc/script

    # md 输出到 doc/script/.docx2md.py.output/，
    # 图片落到 .docx2md.py.output/image/内存池化SDecoder和SMMU部件设计方案v2.3/
    python3 ./.docx2md.py \\
        ../内存池化SDecoder和SMMU部件设计方案/内存池化SDecoder和SMMU部件设计方案v2.3.docx \\
        .docx2md.py.output/内存池化SDecoder和SMMU部件设计方案v2.3.md
"""

import argparse
import html
import os
import re
import unicodedata
import zipfile

BODY_RE = re.compile(r"<w:body>(.*)</w:body>", re.DOTALL)
TAG_RE = re.compile(r"<(/?)([A-Za-z0-9:]+)((?:\s+[^<>]*?)?)(/?)>")
# 源文档 heading 1/2/3 → 降一级，为文档标题留出唯一的 H1
CIRCLE = "①②③④⑤⑥⑦⑧⑨⑩"
NUM_FMT = {}


# ---------------------------------------------------------------- XML helpers
def inner(xml, tag):
    """返回 xml 中所有平衡 <tag ...>...</tag> 的内部内容。"""
    out = []
    for m in re.finditer(rf"<{re.escape(tag)}(?:\s[^<>]*?)?>", xml):
        start, depth = m.end(), 1
        for t in TAG_RE.finditer(xml, start):
            if t.group(2) != tag:
                continue
            if t.group(1):
                depth -= 1
                if depth == 0:
                    out.append(xml[start : t.start()])
                    break
            elif not t.group(4):
                depth += 1
    return out


def children(xml, tags=("w:p", "w:tbl")):
    """按文档顺序取出顶层块级元素 (tag, inner)。"""
    res, i = [], 0
    pat = re.compile(r"<(w:p|w:tbl)(?:\s[^<>]*?)?(/?)>")
    while i < len(xml):
        m = pat.search(xml, i)
        if not m:
            break
        tag = m.group(1)
        if m.group(2):
            res.append((tag, ""))
            i = m.end()
            continue
        start, depth = m.end(), 1
        for t in TAG_RE.finditer(xml, start):
            if t.group(2) != tag:
                continue
            if t.group(1):
                depth -= 1
                if depth == 0:
                    res.append((tag, xml[start : t.start()]))
                    i = t.end()
                    break
            elif not t.group(4):
                depth += 1
    return res


# ------------------------------------------------------------- inline render
RUN_RE = re.compile(
    r"<w:r(?:\s[^<>]*?)?>(.*?)</w:r>|<w:hyperlink(?:\s[^<>]*?)?>(.*?)</w:hyperlink>",
    re.DOTALL,
)
TOKEN_RE = re.compile(
    r"<w:t(?:\s[^<>]*?)?>(.*?)</w:t>|<w:tab\s*/>|<w:br\s*/>", re.DOTALL
)


def flag(rpr, tag):
    return (f"<{tag}/>") in rpr or re.search(rf'<{tag}\s+w:val="(?:1|true|on)"', rpr)


def runs_tokens(p):
    """把 w:p 拆成 (text, bold, italic, strike) 序列。"""
    toks = []
    for m in RUN_RE.finditer(p):
        chunk = m.group(1) or m.group(2) or ""
        rpr = re.search(r"<w:rPr>(.*?)</w:rPr>", chunk, re.DOTALL)
        rpr = rpr.group(1) if rpr else ""
        b, i = bool(flag(rpr, "w:b")), bool(flag(rpr, "w:i"))
        s = bool(flag(rpr, "w:strike") or flag(rpr, "w:dstrike"))
        buf = []
        for t in TOKEN_RE.finditer(chunk):
            if t.group(1) is not None:
                buf.append(html.unescape(t.group(1)))
            else:
                buf.append(" ")  # w:tab / w:br
        text = "".join(buf)
        if not text:
            continue
        # 空白单独作为无格式片段，避免 "** 文本 **" 失效
        if not text.strip():
            toks.append((text, False, False, False))
            continue
        head = text[: len(text) - len(text.lstrip())]
        tail = text[len(text.rstrip()) :]
        if head:
            toks.append((head, False, False, False))
        toks.append((text.strip(), b, i, s))
        if tail:
            toks.append((tail, False, False, False))
    return toks


def esc_inline(s):
    """转义正文中的 Markdown 特殊字符（*、` 等）。"""
    return re.sub(r"([*`])", r"\\\1", s)


def render_runs(toks):
    """输出强调与删除线标记；相邻同格式片段合并，标记按栈开合，避免 *** 歧义。"""

    def merge(seq):
        out = []
        for t in seq:
            if out and out[-1][1:] == t[1:]:
                out[-1] = (out[-1][0] + t[0],) + t[1:]
            else:
                out.append(t)
        return out

    merged = merge(toks)
    # 纯空白片段继承左右一致的格式，避免出现 "**a** **b**"
    for k in range(1, len(merged) - 1):
        if (
            not merged[k][0].strip()
            and merged[k][1:] == (False, False, False)
            and merged[k - 1][1:] == merged[k + 1][1:]
        ):
            merged[k] = (merged[k][0],) + merged[k - 1][1:]
    merged = merge(merged)

    out, stack = [], []  # stack: 已打开的标记，外层在前
    for text, b, i, s in merged:
        want = [m for m, on in (("*", i), ("**", b), ("~~", s)) if on]
        common = 0
        while (
            common < len(stack) and common < len(want) and stack[common] == want[common]
        ):
            common += 1
        out.extend(reversed(stack[common:]))
        out.extend(want[common:])
        stack = want
        out.append(esc_inline(text))
    out.extend(reversed(stack))
    return "".join(out).strip()


def para_text(p):
    return render_runs(runs_tokens(p))


def para_plain(p):
    """不带任何强调标记的纯文本，用于标题。"""
    s = "".join(
        html.unescape(x)
        for x in re.findall(r"<w:t(?:\s[^<>]*?)?>(.*?)</w:t>", p, re.DOTALL)
    )
    return esc_inline(s.strip())


# ------------------------------------------------------------------- tables
def cell_text(tc):
    paras = [para_text(x).strip() for x in inner(tc, "w:p")]
    paras = [x for x in paras if x]
    return "<br>".join(paras) if paras else ""


def table_matrix(tbl):
    """展开 gridSpan，vMerge 续行留空。"""
    rows = []
    for tr in inner(tbl, "w:tr"):
        row = []
        for tc in inner(tr, "w:tc"):
            pr = re.search(r"<w:tcPr>(.*?)</w:tcPr>", tc, re.DOTALL)
            pr = pr.group(1) if pr else ""
            gs = re.search(r'<w:gridSpan w:val="(\d+)"', pr)
            span = int(gs.group(1)) if gs else 1
            vm = re.search(r"<w:vMerge([^/>]*)/?>", pr)
            cont = bool(vm) and "restart" not in vm.group(1)
            txt = "" if cont else cell_text(tc)
            row.append(txt)
            row.extend([""] * (span - 1))
        if row:
            rows.append(row)
    return rows


def disp_width(s):
    """终端显示宽度：全角/宽字符计 2 列，其余计 1 列（与 prettier/string-width 一致）。"""
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in s)


def render_table(tbl):
    rows = table_matrix(tbl)
    if not rows:
        return []
    width = max(len(r) for r in rows)
    rows = [[c.replace("|", "\\|") for c in r] + [""] * (width - len(r)) for r in rows]

    cols = [max(3, max(disp_width(r[c]) for r in rows)) for c in range(width)]

    def line(cells):
        return (
            "| "
            + " | ".join(
                c + " " * (cols[i] - disp_width(c)) for i, c in enumerate(cells)
            )
            + " |"
        )

    out = [line(rows[0]), line(["-" * w for w in cols])]
    out += [line(r) for r in rows[1:]]
    out.append("")
    return out


# ---------------------------------------------------------------- numbering
def collect_headings(z):
    """由 styles.xml 解析「样式ID → Markdown 标题层级」。

    优先用大纲级别 outlineLvl（0 基），其次从样式名推断，兼容
    `heading 1` 与 `1级标题` 两种常见命名；两者都没有则不是标题。
    返回 {styleId: 层级(1 基)}。
    """
    st = z.read("word/styles.xml").decode("utf-8")
    levels = {}
    for m in re.finditer(
        r'<w:style\b[^>]*w:styleId="([^"]+)".*?</w:style>', st, re.DOTALL
    ):
        sid, body = m.group(1), m.group(0)
        if 'w:type="paragraph"' not in body and "w:type=" in body:
            continue  # 跳过字符/表格样式
        name = re.search(r'<w:name w:val="([^"]+)"', body)
        name = name.group(1) if name else ""
        outline = re.search(r'<w:outlineLvl w:val="(\d+)"', body)
        if outline:
            levels[sid] = int(outline.group(1)) + 1
            continue
        m2 = re.match(r"(?:heading|标题)\s*(\d+)$", name.strip(), re.IGNORECASE)
        if not m2:
            m2 = re.match(r"(\d+)\s*级标题$", name.strip())
        if m2 and 1 <= int(m2.group(1)) <= 9:
            levels[sid] = int(m2.group(1))
    return levels


def collect_numbering(z):
    num = z.read("word/numbering.xml").decode("utf-8")
    n2a = dict(
        re.findall(
            r'<w:num w:numId="(\d+)"[^>]*>\s*<w:abstractNumId w:val="(\d+)"', num
        )
    )
    ab = {}
    for m in re.finditer(
        r'<w:abstractNum w:abstractNumId="(\d+)".*?</w:abstractNum>', num, re.DOTALL
    ):
        lv = {}
        for lm in re.finditer(
            r'<w:lvl w:ilvl="(\d+)".*?</w:lvl>', m.group(0), re.DOTALL
        ):
            fmt = re.search(r'<w:numFmt w:val="([^"]+)"', lm.group(0))
            txt = re.search(r'<w:lvlText w:val="([^"]*)"', lm.group(0))
            lv[lm.group(1)] = (
                fmt.group(1) if fmt else "decimal",
                txt.group(1) if txt else "%1.",
            )
        ab[m.group(1)] = lv
    for nid, aid in n2a.items():
        NUM_FMT[nid] = ab.get(aid, {})


def seq_number(fmt, n):
    if fmt == "decimalEnclosedCircleChinese":
        return CIRCLE[n - 1] if n <= 10 else str(n)
    if fmt in ("lowerLetter", "upperLetter"):
        base = ord("a") if fmt == "lowerLetter" else ord("A")
        return chr(base + (n - 1) % 26)
    if fmt in ("lowerRoman", "upperRoman"):
        romans = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]
        s = romans[n - 1] if n <= 10 else str(n)
        return s.upper() if fmt == "upperRoman" else s
    return str(n)


def marker(numid, ilvl, counters):
    """按原文档的 lvlText 生成列表前缀（项目符号 → "- "）。"""
    fmt, lvltext = NUM_FMT.get(numid, {}).get(ilvl, ("bullet", ""))
    if fmt == "bullet":
        return "- "
    key = (numid, ilvl)
    n = counters.get(key, 0) + 1
    counters[key] = n
    pre = re.sub(r"%(\d+)", lambda m: seq_number(fmt, n), lvltext)
    return pre.replace("\u3000", " ").strip() + " "


# -------------------------------------------------------------------- main
def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        prog=".docx2md.py",
        description="将设计方案 .docx 转换为规范 Markdown，并导出其中的 PNG 插图。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "示例（在 doc/script 目录下执行）:\n"
            "  cd doc/script\n"
            "  python3 ./.docx2md.py <输入.docx> <输出.md>\n"
        ),
    )
    parser.add_argument("input", help="输入 .docx 文件路径")
    parser.add_argument("output", help="输出 .md 文件路径（所属目录不存在时自动创建）")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    src_docx = args.input
    out_md = args.output

    # 与 md 现有形式保持一致：图片放在 <输出目录>/image/<md 基名>/，
    # Markdown 中以 image/<md 基名>/xxx.png 相对引用（同 Typora 每文档一目录的约定）
    out_dir = os.path.dirname(out_md) or "."
    out_stem = os.path.splitext(os.path.basename(out_md))[0]
    rel_img_dir = f"image/{out_stem}"
    img_dir = os.path.join(out_dir, "image", out_stem)
    os.makedirs(out_dir, exist_ok=True)

    z = zipfile.ZipFile(src_docx)
    body = BODY_RE.search(z.read("word/document.xml").decode("utf-8")).group(1)
    rels = {}
    for m in re.finditer(
        r'Id="(rId\d+)"[^>]*Target="(media/[^"]+)"',
        z.read("word/_rels/document.xml.rels").decode("utf-8"),
    ):
        rels[m.group(1)] = m.group(2)
    collect_numbering(z)
    head_levels = collect_headings(z)

    emitted, skipped, lines, counters = set(), 0, [], {}
    img_re = re.compile(r'r:embed="(rId\d+)"|r:id="(rId\d+)"')
    title_open, title_lines = True, 0

    blocks = children(body)
    plain = [para_plain(c) if t == "w:p" else "" for t, c in blocks]

    def caption_for(i):
        """图片说明：优先取后续的图/表题注；无题注时提示按上下文补图。"""
        for j in range(i + 1, min(i + 3, len(blocks))):
            if plain[j]:
                if re.match(r"^(图|表)\s*\d+\s*[:：]", plain[j]):
                    return plain[j]
                break
        return "原文无题注，请按上下文补图"

    for i, (tag, content) in enumerate(blocks):
        if tag == "w:tbl":
            lines.extend(render_table(content))
            continue

        p = content
        # 图片（w:drawing / w:object-v:imagedata）
        imgs = []
        for m in img_re.finditer(p):
            t = rels.get(m.group(1) or m.group(2))
            if t and t not in emitted:
                emitted.add(t)
                imgs.append(t)
        if imgs:
            cap = caption_for(i)
            for t in imgs:
                name = os.path.basename(t)
                # 非 PNG（emf/wmf 等矢量图）不做导出，只在 md 里留注释标明位置
                if not name.lower().endswith(".png"):
                    skipped += 1
                    lines.append(
                        f"<!-- 非 PNG 图片未处理：{name}"
                        f"{'　—　' + cap if cap else ''} -->"
                    )
                    continue
                os.makedirs(img_dir, exist_ok=True)
                with open(os.path.join(img_dir, name), "wb") as f:
                    f.write(z.read("word/" + t))
                stem = os.path.splitext(name)[0]
                lines.append(f"![{stem}]({rel_img_dir}/{name})")
            lines.append("")
            continue

        text = para_text(p)
        if not text:
            continue

        style = re.search(r'<w:pStyle w:val="([^"]+)"', p)
        style = style.group(1) if style else ""
        if style in head_levels:
            title_open = False
            # 源文档标题降一级，为文档标题留出唯一的 H1
            lines.append("#" * min(head_levels[style] + 1, 6) + " " + para_plain(p))
            lines.append("")
            counters.clear()
            continue

        # 文档标题块：正文开始前居中、无大纲级别的段落
        centered = bool(re.search(r'<w:jc w:val="center"', p))
        if title_open and centered:
            title_lines += 1
            lines.append(
                "# " + para_plain(p)
                if title_lines == 1
                else "**" + para_plain(p) + "**"
            )
            lines.append("")
            continue
        title_open = False

        numpr = re.search(r"<w:numPr>(.*?)</w:numPr>", p, re.DOTALL)
        if numpr:
            numid = re.search(r'<w:numId w:val="(\d+)"', numpr.group(1))
            ilvl = re.search(r'<w:ilvl w:val="(\d+)"', numpr.group(1))
            if numid and numid.group(1) != "0":
                lv = ilvl.group(1) if ilvl else "0"
                lines.append(
                    "  " * int(lv) + marker(numid.group(1), lv, counters) + text
                )
                lines.append("")
                continue

        lines.append(text)
        lines.append("")

    md, blank = [], 0
    for ln in lines:
        if ln == "":
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        md.append(ln)

    # 合并同类列表项之间的空行，避免生成松散列表
    item = re.compile(r"^(\s*)(- |\d+[.)]\s|[a-zA-Z][.)]\s|[ivxIVX]+[.)]\s|[①-⑩]\s)")
    res = []
    for i, ln in enumerate(md):
        if ln == "" and res and item.match(res[-1]):
            nxt = next((x for x in md[i + 1 :] if x != ""), None)
            if (
                nxt
                and item.match(nxt)
                and item.match(nxt).group(1) == item.match(res[-1]).group(1)
            ):
                continue
        res.append(ln)

    out = "\n".join(res).strip() + "\n"
    with open(out_md, "w", encoding="utf-8") as f:
        f.write(out)
    print(
        f"written: {out_md} ({len(out)} chars, "
        f"{len(emitted) - skipped} PNG exported, {skipped} non-PNG skipped)"
    )


if __name__ == "__main__":
    main()
