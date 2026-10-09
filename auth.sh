#!/usr/bin/env bash
# GitHub 设备码授权（带状态持久化，进程意外退出也不丢流程）。
#
#   bash auth.sh
# 结果：
#   /tmp/gh_user_code.txt   给用户输入的 8 位代码（同时打印到 stdout）
#   <TOKEN_FILE>            拿到后写入 token（供 publish.sh 复用）
#   /tmp/gh_auth.log        全过程日志（含每次轮询结果）
#
# 注意：刻意不启用 set -e —— 网络抖动不该让整个授权流程崩掉。

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_ID="${CLIENT_ID:-178c6fc778ccc68e1d6a}"
TOKEN_FILE="${GITHUB_TOKEN_FILE:-$DIR/../风控模型/.secrets/github-token}"
STATE="/tmp/gh_device.json"
CODE_FILE="/tmp/gh_user_code.txt"
API_TOKEN="https://github.com/login/oauth/access_token"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

jget() { python3 -c "import json,sys; print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || true; }

# 1) 申请设备码
log "申请设备码..."
DEV="$(curl -sS --max-time 25 -X POST https://github.com/login/device/code \
  -H "Accept: application/json" -d "client_id=$CLIENT_ID" -d "scope=repo")" || true
DEVICE_CODE="$(printf '%s' "$DEV" | jget device_code)"
USER_CODE="$(printf '%s' "$DEV" | jget user_code)"
INTERVAL="$(printf '%s' "$DEV" | jget interval)"
[ -z "$INTERVAL" ] && INTERVAL=5

if [ -z "$DEVICE_CODE" ] || [ -z "$USER_CODE" ]; then
  log "申请失败：$(printf '%s' "$DEV" | head -c 300)"
  exit 1
fi
printf '%s' "$DEV" > "$STATE"
printf '%s' "$USER_CODE" > "$CODE_FILE"
log "设备码申请成功"
log "  请打开 https://github.com/login/device 并输入： $USER_CODE"

# 2) 轮询换取 token（记录每次结果，便于排查）
log "开始等待授权（最多 15 分钟）..."
i=0
while [ "$i" -lt 180 ]; do
  i=$((i + 1))
  sleep "$INTERVAL"
  RESP="$(curl -sS --max-time 20 -X POST "$API_TOKEN" \
    -H "Accept: application/json" \
    -d "client_id=$CLIENT_ID" \
    -d "device_code=$DEVICE_CODE" \
    -d "grant_type=urn:ietf:params:oauth:grant-type:device_code" 2>&1)" || true
  TOKEN="$(printf '%s' "$RESP" | jget access_token)"
  if [ -n "$TOKEN" ]; then
    mkdir -p "$(dirname "$TOKEN_FILE")"
    printf '%s' "$TOKEN" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    log "授权成功！token 已写入 $TOKEN_FILE"
    exit 0
  fi
  ERR="$(printf '%s' "$RESP" | jget error)"
  case "$ERR" in
    authorization_pending) [ $((i % 12)) -eq 0 ] && log "  等待中…（第 $i 次）" ;;
    slow_down)             INTERVAL=$((INTERVAL + 5)); log "  限速，间隔调到 ${INTERVAL}s" ;;
    "")                    [ $((i % 12)) -eq 0 ] && log "  网络抖动：$(printf '%s' "$RESP" | head -c 120)" ;;
    *)                     log "  授权返回错误：$ERR"; sleep 3 ;;
  esac
done

log "超时未完成授权，请重新运行 bash auth.sh"
exit 1
