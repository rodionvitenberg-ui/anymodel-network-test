#!/usr/bin/env bash
# Сборка клиентского VLESS-профиля из deploy/.env.
# Вывод: VLESS-строка (импорт в Hiddify/v2rayNG/Streisand) + QR-код при наличии qrencode.
set -euo pipefail
cd "$(dirname "$0")/.."   # -> deploy/

ENV_FILE=".env"
[ -f "$ENV_FILE" ] || { echo "ERROR: нет deploy/.env — сначала запустите install.sh или scripts/gen-keys.sh" >&2; exit 1; }

get() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"'; }

HOST=$(get SERVER_HOST)
PORT=$(get XRAY_PORT)
DEST=$(get XRAY_DEST)
UUID=$(get XRAY_UUID)
PUB=$(get XRAY_REALITY_PUBLIC)
SID=$(get XRAY_SHORT_ID)
NAME=$(get PROFILE_NAME)

[ -n "$HOST" ] || { echo "ERROR: SERVER_HOST не задан в deploy/.env" >&2; exit 1; }
[ -n "$UUID" ] || { echo "ERROR: XRAY_UUID не найден (запустите scripts/gen-keys.sh)" >&2; exit 1; }
[ -n "$PUB" ] || { echo "ERROR: XRAY_REALITY_PUBLIC не найден (запустите scripts/gen-keys.sh)" >&2; exit 1; }
[ -n "$SID" ] || { echo "ERROR: XRAY_SHORT_ID не найден (запустите scripts/gen-keys.sh)" >&2; exit 1; }
PORT=${PORT:-443}

URL="vless://${UUID}@${HOST}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST}&fp=chrome&pbk=${PUB}&sid=${SID}&type=tcp&headerType=none#${NAME}"

echo "=== VLESS-строка ==="
echo "$URL"
echo
if command -v qrencode >/dev/null 2>&1; then
  echo "=== QR-код (Hiddify: '+' -> 'Сканировать QR') ==="
  qrencode -t UTF8 "$URL"
else
  echo "(подсказка: 'sudo apt install qrencode' — тогда здесь появится QR-код)"
fi
