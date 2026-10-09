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
    return (
        f"<style>{_CSS}</style>"
        f"<div id=\"{NAV_ID}\">"
        f"<a href=\"./index.html\"{today_cls}>今日看板</a>"
        f"<a href=\"./overview.html\"{over_cls}>综合仪表盘</a>"
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


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else "."
    dst = sys.argv[2] if len(sys.argv) > 2 else "."
    print("==> 生成站点文件")
    n1 = build(os.path.join(src, "dashboard.html"), os.path.join(dst, "index.html"), "today")
    n2 = build(os.path.join(src, "综合仪表盘.html"), os.path.join(dst, "overview.html"), "overview")
    if not n1:
        print("  [错误] 今日看板缺失，站点未生成")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
