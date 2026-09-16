#!/usr/bin/env python3
"""将 doc/ 下的设计方案 .docx 转换为规范 Markdown，并把插图导出到 doc/images/。

用法： python3 doc/.docx2md.py
"""

import html
import os
import re
import sys
import unicodedata
import zipfile

DOCX = "doc/内存池化SDecoder和SMMU部件设计方案v2.3.docx"
OUT_MD = "doc/内存池化SDecoder和SMMU部件设计方案v2.3.md"
IMG_DIR = "doc/images"

BODY_RE = re.compile(r"<w:body>(.*)</w:body>", re.DOTALL)
TAG_RE = re.compile(r"<(/?)([A-Za-z0-9:]+)((?:\s+[^<>]*?)?)(/?)>")
# 源文档 heading 1/2/3 → 降一级，为文档标题留出唯一的 H1
HEAD_STYLE = {"1": 2, "2": 3, "3": 4, "10": 2, "20": 3, "30": 4}
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
    """把 w:p 拆成 (text, bold, italic) 序列。"""
    toks = []
    for m in RUN_RE.finditer(p):
        chunk = m.group(1) or m.group(2) or ""
        rpr = re.search(r"<w:rPr>(.*?)</w:rPr>", chunk, re.DOTALL)
        rpr = rpr.group(1) if rpr else ""
        b, i = bool(flag(rpr, "w:b")), bool(flag(rpr, "w:i"))
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
            toks.append((text, False, False))
            continue
        head = text[: len(text) - len(text.lstrip())]
        tail = text[len(text.rstrip()) :]
        if head:
            toks.append((head, False, False))
        toks.append((text.strip(), b, i))
        if tail:
            toks.append((tail, False, False))
    return toks


def esc_inline(s):
    """转义正文中的 Markdown 特殊字符（*、` 等）。"""
    return re.sub(r"([*`])", r"\\\1", s)


def render_runs(toks):
    """用星号标记输出；相邻同格式片段合并，标记按栈开合，避免 *** 歧义。"""

    def merge(seq):
        out = []
        for t in seq:
            if out and out[-1][1:] == t[1:]:
                out[-1] = (out[-1][0] + t[0], t[1], t[2])
            else:
                out.append(t)
        return out

    merged = merge(toks)
    # 纯空白片段继承左右一致的格式，避免出现 "**a** **b**"
    for k in range(1, len(merged) - 1):
        if (
            not merged[k][0].strip()
            and merged[k][1:] == (False, False)
            and merged[k - 1][1:] == merged[k + 1][1:]
        ):
            merged[k] = (merged[k][0],) + merged[k - 1][1:]
    merged = merge(merged)

    out, stack = [], []  # stack: 已打开的标记，外层在前
    for text, b, i in merged:
        want = [m for m, on in (("*", i), ("**", b)) if on]
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
def main():
    with_images = "--with-images" in sys.argv
    z = zipfile.ZipFile(DOCX)
    body = BODY_RE.search(z.read("word/document.xml").decode("utf-8")).group(1)
    rels = {}
    for m in re.finditer(
        r'Id="(rId\d+)"[^>]*Target="(media/[^"]+)"',
        z.read("word/_rels/document.xml.rels").decode("utf-8"),
    ):
        rels[m.group(1)] = m.group(2)
    collect_numbering(z)

    os.makedirs(IMG_DIR, exist_ok=True)
    emitted, lines, counters = set(), [], {}
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
                with open(os.path.join(IMG_DIR, name), "wb") as f:
                    f.write(z.read("word/" + t))
                if with_images:
                    lines.append(f"![{os.path.splitext(name)[0]}](images/{name})")
                else:
                    lines.append(
                        f"<!-- 图片占位：images/{name}{'　—　' + cap if cap else ''} -->"
                    )
            lines.append("")
            continue

        text = para_text(p)
        if not text:
            continue

        style = re.search(r'<w:pStyle w:val="([^"]+)"', p)
        style = style.group(1) if style else ""
        if style in HEAD_STYLE:
            title_open = False
            lines.append("#" * HEAD_STYLE[style] + " " + para_plain(p))
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
    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"written: {OUT_MD} ({len(out)} chars, {len(emitted)} images)")


if __name__ == "__main__":
    main()
