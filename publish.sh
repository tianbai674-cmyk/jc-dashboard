#!/usr/bin/env bash
# 把竞彩风控看板发布到 GitHub Pages（每日自动复用本脚本）。
#
#   用法： bash publish.sh          # 生成站点文件并推送
#          DRY=1 bash publish.sh    # 只生成，不推送
#
# 站点文件由风控模型的 outputs/ 同步而来，每次发布都会重新生成：
#   index.html     ← outputs/dashboard.html        （今日预测看板）
#   overview.html  ← outputs/综合仪表盘.html        （综合仪表盘）
# 两个页面都会注入一个悬浮切换条，方便互相跳转。

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../风控模型/outputs}"
REPO="${REPO:-jc-dashboard}"
TOKEN_FILE="${GITHUB_TOKEN_FILE:-$DIR/../风控模型/.secrets/github-token}"
API="https://api.github.com"
NET_OPT=""

echo "==> 源目录: $SRC"
[ -f "$SRC/dashboard.html" ] || { echo "找不到 $SRC/dashboard.html，先跑一次 run_full.py"; exit 1; }

# ---------- 网络：直连不通再试本机代理 ----------
detect_net() {
  if curl -s -o /dev/null --max-time 8 "$API/rate_limit"; then echo "==> 网络：直连"; return; fi
  local p
  for p in 127.0.0.1:1082 127.0.0.1:7890 127.0.0.1:1087 127.0.0.1:6152 127.0.0.1:8118; do
    if curl -s -o /dev/null --max-time 5 -x "http://$p" "$API/rate_limit"; then
      NET_OPT="-x http://$p"; export HTTPS_PROXY="http://$p" HTTP_PROXY="http://$p"
      echo "==> 网络：通过本机代理 $p"; return
    fi
  done
  echo "无法连接 ${API}，请检查网络。"; exit 1
}

jget() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || true; }

# ---------- 生成站点（拷贝 + 注入切换条）----------
python3 "$DIR/build_site.py" "$SRC" "$DIR"

if [ "${DRY:-0}" = "1" ]; then echo "==> DRY=1，跳过推送"; exit 0; fi

detect_net

TOKEN="${GITHUB_TOKEN:-}"
[ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ] && TOKEN="$(tr -d ' \t\r\n' < "$TOKEN_FILE")"
if [ -z "$TOKEN" ]; then
  echo "没有可用 token。先运行一次： bash deploy-github.sh"
  exit 1
fi

auth=(-H "Authorization: Bearer $TOKEN"
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28")

LOGIN="$(curl -sS $NET_OPT "${auth[@]}" "$API/user" | jget login)"
[ -n "$LOGIN" ] || { echo "token 无效或已过期，请重新运行 deploy-github.sh"; exit 1; }

cd "$DIR"
[ -d .git ] || git init -q -b main
git config user.name "$LOGIN"
git config user.email "$LOGIN@users.noreply.github.com"
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "看板更新 $(date '+%Y-%m-%d %H:%M')"
else
  echo "==> 内容无变化"
fi

git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$LOGIN/$REPO.git"
PUSH_URL="https://x-access-token:$TOKEN@github.com/$LOGIN/$REPO.git"
git push -q "$PUSH_URL" HEAD:main

echo
echo "公网地址： https://$LOGIN.github.io/$REPO/"
echo "仓库地址： https://github.com/$LOGIN/$REPO"
