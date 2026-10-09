#!/usr/bin/env bash
# 首次部署：授权 GitHub → 建仓库 → 推送 → 开启 GitHub Pages。
# 授权一次后 token 会缓存，之后每日更新走 publish.sh 即可，无需再授权。
#
#   用法： bash deploy-github.sh
#          REPO=my-board bash deploy-github.sh          # 自定义仓库名
#          GITHUB_TOKEN=xxx bash deploy-github.sh       # 已有 token

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SRC:-$DIR/../风控模型/outputs}"
REPO="${REPO:-jc-dashboard}"
CLIENT_ID="${CLIENT_ID:-178c6fc778ccc68e1d6a}"
TOKEN_FILE="${GITHUB_TOKEN_FILE:-$DIR/../风控模型/.secrets/github-token}"
API="https://api.github.com"
NET_OPT=""

detect_net() {
  if curl -s -o /dev/null --max-time 8 "$API/rate_limit"; then echo "==> 网络：直连"; return; fi
  local p
  for p in 127.0.0.1:1082 127.0.0.1:7890 127.0.0.1:1087 127.0.0.1:6152 127.0.0.1:8118; do
    if curl -s -o /dev/null --max-time 5 -x "http://$p" "$API/rate_limit"; then
      NET_OPT="-x http://$p"; export HTTPS_PROXY="http://$p" HTTP_PROXY="http://$p"
      echo "==> 网络：通过本机代理 $p"; return
    fi
  done
  echo "无法连接 $API，请检查网络或本机代理。"; exit 1
}

jget() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || true; }

detect_net

# ---------- 生成站点 ----------
python3 "$DIR/build_site.py" "$SRC" "$DIR"

# ---------- 取 token ----------
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ]; then
  TOKEN="$(tr -d ' \t\r\n' < "$TOKEN_FILE")"
fi

if [ -z "$TOKEN" ]; then
  echo "==> 请求 GitHub 设备授权码"
  DEV="$(curl -sS $NET_OPT -X POST https://github.com/login/device/code \
    -H "Accept: application/json" -d "client_id=$CLIENT_ID" -d "scope=repo")"
  USER_CODE="$(printf '%s' "$DEV" | jget user_code)"
  DEVICE_CODE="$(printf '%s' "$DEV" | jget device_code)"
  INTERVAL="$(printf '%s' "$DEV" | jget interval)"
  [ -z "$INTERVAL" ] && INTERVAL=5
  if [ -z "$USER_CODE" ] || [ -z "$DEVICE_CODE" ]; then
    echo "获取设备码失败："; printf '%s\n' "$DEV" | head -c 400; echo; exit 1
  fi
  echo
  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │  1) 打开  https://github.com/login/device    │"
  echo "  │  2) 输入代码   $USER_CODE"
  echo "  │  3) 点 Authorize 授权                        │"
  echo "  └─────────────────────────────────────────────┘"
  echo
  echo "等待授权中（最多 15 分钟）..."
  for _ in $(seq 1 180); do
    sleep "$INTERVAL"
    RESP="$(curl -sS --max-time 20 $NET_OPT -X POST https://github.com/login/oauth/access_token \
      -H "Accept: application/json" -d "client_id=$CLIENT_ID" \
      -d "device_code=$DEVICE_CODE" \
      -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" || true)"
    TOKEN="$(printf '%s' "$RESP" | jget access_token)"
    [ -n "$TOKEN" ] && break
  done
  [ -n "$TOKEN" ] || { echo "授权等待超时，请重新运行本脚本。"; exit 1; }
  echo "==> 授权成功"
  mkdir -p "$(dirname "$TOKEN_FILE")"
  printf '%s' "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "    token 已缓存到 $TOKEN_FILE（仅供本机使用，不会进仓库）"
fi

auth=(-H "Authorization: Bearer $TOKEN"
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28")

echo "==> 校验身份"
ME="$(curl -sS $NET_OPT "${auth[@]}" "$API/user")"
LOGIN="$(printf '%s' "$ME" | jget login)"
if [ -z "$LOGIN" ]; then
  echo "token 无效或权限不足："; printf '%s\n' "$ME" | head -6; exit 1
fi
echo "    账号：$LOGIN"

echo "==> 准备仓库 $LOGIN/$REPO"
CODE="$(curl -s -o /dev/null -w '%{http_code}' $NET_OPT "${auth[@]}" "$API/repos/$LOGIN/$REPO")"
if [ "$CODE" = "200" ]; then
  echo "    仓库已存在"
else
  curl -sS $NET_OPT "${auth[@]}" -X POST "$API/user/repos" \
    -d "{\"name\":\"$REPO\",\"private\":false,\"has_issues\":false,\"has_wiki\":false,\"description\":\"竞彩足球风控模型 · 每日预测看板\"}" >/dev/null
  echo "    已创建公开仓库"
fi

echo "==> 提交并推送"
cd "$DIR"
[ -d .git ] || git init -q -b main
git config user.name "$LOGIN"
git config user.email "$LOGIN@users.noreply.github.com"
git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "竞彩风控看板 · 首次部署 $(date '+%Y-%m-%d %H:%M')"
fi
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$LOGIN/$REPO.git"

PUSH_URL="https://x-access-token:$TOKEN@github.com/$LOGIN/$REPO.git"
if [ "${FORCE:-0}" = "1" ]; then
  git push -q --force "$PUSH_URL" HEAD:main
elif ! git push -q "$PUSH_URL" HEAD:main; then
  echo; echo "推送被拒绝（远端 main 已有内容）。确认可覆盖后： FORCE=1 bash deploy-github.sh"
  exit 1
fi
echo "    已推送"

echo "==> 开启 GitHub Pages"
PC="$(curl -s -o /dev/null -w '%{http_code}' $NET_OPT "${auth[@]}" "$API/repos/$LOGIN/$REPO/pages")"
if [ "$PC" != "200" ]; then
  curl -sS $NET_OPT "${auth[@]}" -X POST "$API/repos/$LOGIN/$REPO/pages" \
    -d '{"source":{"branch":"main","path":"/"}}' >/dev/null 2>&1 || true
fi

PAGES_URL="https://$LOGIN.github.io/$REPO/"
SITE_URL_FILE="$DIR/public-url.txt"
printf '%s\n' "$PAGES_URL" > "$SITE_URL_FILE"
echo
echo "仓库地址： https://github.com/$LOGIN/$REPO"
echo "公网地址： $PAGES_URL"
echo
echo "首次部署通常需要 1 分钟左右，等待站点上线..."
for _ in $(seq 1 30); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' $NET_OPT "$PAGES_URL")" = "200" ]; then
    echo "已上线：$PAGES_URL"; exit 0
  fi
  sleep 6
done
echo "还没就绪，等 1-2 分钟后刷新上面的公网地址即可。"
