#!/usr/bin/env python3
"""把风控模型 outputs/ 里的两个看板拷成可发布的静态站点。

  index.html     ← outputs/dashboard.html   今日预测看板
  overview.html  ← outputs/综合仪表盘.html    综合仪表盘

两个页面都是**零依赖单文件 HTML**，这里只额外注入一个悬浮切换条，
方便在手机/任意电脑上互相跳转。注入是幂等的：已注入过就先剥离再注入，
所以看板每天重新生成后直接再跑一次即可。
"""
import os
import re
import sys

NAV_ID = "jcsite-nav"

_CSS = (
    "#jcsite-nav{position:fixed;right:14px;bottom:14px;z-index:2147483647;"
    "display:flex;gap:8px;font:600 13px/1.2 -apple-system,BlinkMacSystemFont,"
    "'PingFang SC','Microsoft YaHei',sans-serif}"
    "#jcsite-nav a{display:block;padding:9px 14px;border-radius:999px;"
    "text-decoration:none;color:#fff;background:rgba(20,26,40,.82);"
    "border:1px solid rgba(255,255,255,.18);backdrop-filter:blur(8px);"
    "-webkit-backdrop-filter:blur(8px);box-shadow:0 6px 18px rgba(0,0,0,.28)}"
    "#jcsite-nav a.on{background:linear-gradient(135deg,#1f6feb,#0ea5e9);"
    "border-color:rgba(255,255,255,.35)}"
    "@media (max-width:520px){#jcsite-nav{right:8px;bottom:8px;gap:6px}"
    "#jcsite-nav a{padding:8px 11px;font-size:12px}}"
)


def _nav(active: str) -> str:
    today_cls = " class=\"on\"" if active == "today" else ""
    over_cls = " class=\"on\"" if active == "overview" else ""
    rev_cls = " class=\"on\"" if active == "review" else ""
    foc_cls = " class=\"on\"" if active == "focus" else ""
    return (
        f"<style>{_CSS}</style>"
        f"<div id=\"{NAV_ID}\">"
        f"<a href=\"./index.html\"{today_cls}>今日看板</a>"
        f"<a href=\"./overview.html\"{over_cls}>综合仪表盘</a>"
        f"<a href=\"./focus.html\"{foc_cls}>重点分析</a>"
        f"<a href=\"./review.html\"{rev_cls}>大复盘</a>"
        f"</div>"
    )


def build(src_file: str, out_file: str, active: str) -> int:
    if not os.path.exists(src_file):
        print(f"  [跳过] 找不到 {src_file}")
        return 0
    with open(src_file, encoding="utf-8") as f:
        html = f.read()
    # 幂等：先剥掉上一次注入的内容
    html = re.sub(r"<style>#jcsite-nav\{.*?</style>", "", html, flags=re.S)
    html = re.sub(r"<div id=\"jcsite-nav\">.*?</div>", "", html, flags=re.S)
    if "</body>" in html:
        html = html.replace("</body>", _nav(active) + "\n</body>", 1)
    else:
        html += _nav(active)
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  {os.path.basename(src_file)}  ->  {os.path.basename(out_file)}  ({len(html)//1024} KB)")
    return len(html)


def _inline(t: str) -> str:
    """极简行内格式：**粗体**、`代码`、[文字](链接)"""
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    t = re.sub(r"\[(.+?)\]\((.+?)\)", r'<a href="\2">\1</a>', t)
    return t


def render_md(md: str, title: str, active: str = "review") -> str:
    """极简 Markdown → HTML（够用即可：标题/表格/引用/分隔线/粗体/列表）"""
    out, i = [], 0
    lines = md.split("\n")
    while i < len(lines):
        ln = lines[i].rstrip()
        if ln.startswith("|") and i + 1 < len(lines) and set(lines[i + 1].strip()) <= set("|-: "):
            head = [c.strip() for c in ln.strip("|").split("|")]
            i += 2
            body = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                body.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
                i += 1
            out.append("<table><thead><tr>" + "".join(f"<th>{_inline(c)}</th>" for c in head) + "</tr></thead><tbody>")
            for row in body:
                out.append("<tr>" + "".join(f"<td>{_inline(c)}</td>" for c in row) + "</tr>")
            out.append("</tbody></table>")
            continue
        if ln.startswith("### "):
            out.append(f"<h3>{_inline(ln[4:])}</h3>")
        elif ln.startswith("## "):
            out.append(f"<h2>{_inline(ln[3:])}</h2>")
        elif ln.startswith("# "):
            out.append(f"<h1>{_inline(ln[2:])}</h1>")
        elif ln.startswith("> "):
            out.append(f"<blockquote>{_inline(ln[2:])}</blockquote>")
        elif ln.strip() == "---":
            out.append("<hr>")
        elif ln.startswith("- "):
            out.append(f"<li>{_inline(ln[2:])}</li>")
        elif ln.strip():
            out.append(f"<p>{_inline(ln)}</p>")
        i += 1
    css = (
        "body{margin:0;padding:28px 18px 90px;background:#0e1420;color:#dbe4f0;"
        "font:15px/1.75 -apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei',sans-serif}"
        ".wrap{max-width:900px;margin:0 auto}h1{font-size:24px;color:#6cb6ff;margin:.2em 0 .6em}"
        "h2{font-size:19px;color:#7ee0c0;margin:1.8em 0 .6em;border-left:4px solid #1f6feb;padding-left:10px}"
        "h3{font-size:16px;color:#ffd166;margin:1.4em 0 .4em}"
        "table{width:100%;border-collapse:collapse;margin:.8em 0;font-size:13.5px;display:block;overflow-x:auto}"
        "th,td{border:1px solid #23324a;padding:7px 9px;text-align:left;white-space:nowrap}"
        "th{background:#16233a;color:#9cc4ff}tr:nth-child(even) td{background:#121b2c}"
        "blockquote{margin:.8em 0;padding:.6em 1em;border-left:3px solid #5b7bb5;background:#131d30;color:#a9bcd8}"
        "code{background:#1b2740;padding:1px 5px;border-radius:4px;color:#ffd166;font-size:13px}"
        "b{color:#fff}hr{border:0;border-top:1px solid #23324a;margin:1.6em 0}"
        "li{margin-left:1.2em}a{color:#6cb6ff}"
    )
    return (f"<!DOCTYPE html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">"
            f"<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            f"<title>{title}</title><style>{css}</style></head><body><div class=\"wrap\">"
            + "\n".join(out) + "</div>" + _nav(active) + "</body></html>")


def build_review(src: str, dst: str) -> int:
    """把 outputs/ 里最新的大复盘 Markdown 渲染成 review.html"""
    import glob
    cands = sorted(glob.glob(os.path.join(src, "大复盘_*.md")))
    if not cands:
        print("  [跳过] 未找到大复盘 Markdown")
        return 0
    latest = cands[-1]
    with open(latest, encoding="utf-8") as f:
        md = f.read()
    html = render_md(md, os.path.basename(latest)[:-3], "review")
    with open(os.path.join(dst, "review.html"), "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  {os.path.basename(latest)}  ->  review.html  ({len(html)//1024} KB)")
    return len(html)


def build_focus(src: str, dst: str) -> int:
    """把 outputs/ 里最新的「重点分析」Markdown 渲染成 focus.html"""
    import glob
    cands = sorted(glob.glob(os.path.join(src, "重点分析_*.md")))
    if not cands:
        return 0
    latest = cands[-1]
    with open(latest, encoding="utf-8") as f:
        md = f.read()
    html = render_md(md, os.path.basename(latest)[:-3], "focus")
    with open(os.path.join(dst, "focus.html"), "w", encoding="utf-8") as f:
        f.write(html)
    print(f"  {os.path.basename(latest)}  ->  focus.html  ({len(html)//1024} KB)")
    return len(html)


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    dst = sys.argv[2] if len(sys.argv) > 2 else "."
    print("==> 生成站点文件")
    n1 = build(os.path.join(src, "dashboard.html"), os.path.join(dst, "index.html"), "today")
    n2 = build(os.path.join(src, "综合仪表盘.html"), os.path.join(dst, "overview.html"), "overview")
    build_review(src, dst)
    build_focus(src, dst)
    if not n1:
        print("  [错误] 今日看板缺失，站点未生成")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
