#!/usr/bin/env bash
# Локальный smoke-тест полного пути без VPS:
#   [curl] --socks5--> [xray-клиент VLESS+REALITY] --> [xray-сервер REALITY на 127.0.0.1:TEST_PORT] --> [интернет]
# Требует локально собранного бинарника: cd Xray-core && go build -o ../.bin/xray ./main
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/.bin/xray"
[ -x "$BIN" ] || { echo "Нет $BIN. Соберите: cd $ROOT/Xray-core && go build -o $ROOT/.bin/xray ./main" >&2; exit 1; }
cd "$ROOT/deploy"
[ -f .env ] || ./scripts/gen-keys.sh
set -a; source .env; set +a

TEST_PORT=${TEST_PORT:-8443}
SOCKS_PORT=${SOCKS_PORT:-10800}
HOST_UNDER_TEST=${HOST_UNDER_TEST:-127.0.0.1}
CHECK_URL=${CHECK_URL:-https://www.google.com/generate_204}

# 1) Серверный конфиг на тестовом порту (из того же шаблона, что и в деплое)
sed -e "s|__XRAY_PORT__|${TEST_PORT}|g" \
    -e "s|__XRAY_UUID__|${XRAY_UUID}|g" \
    -e "s|__XRAY_DEST__|${XRAY_DEST}|g" \
    -e "s|__XRAY_REALITY_PRIVATE__|${XRAY_REALITY_PRIVATE}|g" \
    -e "s|__XRAY_SHORT_ID__|${XRAY_SHORT_ID}|g" \
    config/config.template.json > /tmp/xray-smoke-server.json

# 2) Клиентский конфиг (socks -> VLESS+REALITY, идентичен профилю Hiddify/v2rayNG)
cat > /tmp/xray-smoke-client.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"listen": "127.0.0.1", "port": ${SOCKS_PORT}, "protocol": "socks", "settings": {"udp": true}}
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {"address": "${HOST_UNDER_TEST}", "port": ${TEST_PORT},
           "users": [{"id": "${XRAY_UUID}", "flow": "xtls-rprx-vision", "encryption": "none"}]}
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${XRAY_DEST}",
          "fingerprint": "chrome",
          "publicKey": "${XRAY_REALITY_PUBLIC}",
          "shortId": "${XRAY_SHORT_ID}",
          "spiderX": "/"
        }
      }
    }
  ]
}
EOF

"$BIN" run -test -c /tmp/xray-smoke-server.json >/dev/null
SERVER_PID=""
CLIENT_PID=""
if [ "${SKIP_SERVER:-0}" != "1" ]; then
  "$BIN" run -c /tmp/xray-smoke-server.json >/tmp/xray-smoke-server.log 2>&1 &
  SERVER_PID=$!
fi
trap '[ -n "$SERVER_PID" ] && kill $SERVER_PID 2>/dev/null; [ -n "$CLIENT_PID" ] && kill $CLIENT_PID 2>/dev/null' EXIT
sleep 1

"$BIN" run -c /tmp/xray-smoke-client.json >/tmp/xray-smoke-client.log 2>&1 &
CLIENT_PID=$!
sleep 1.5

echo ">>> curl через туннель (socks 127.0.0.1:${SOCKS_PORT} -> ${HOST_UNDER_TEST}:${TEST_PORT} -> ${CHECK_URL})"
curl -sS --max-time 20 --socks5-hostname "127.0.0.1:${SOCKS_PORT}" \
  -o /dev/null -w 'HTTP %{http_code}, %{time_total}s\n' "$CHECK_URL"

echo "SMOKE OK: REALITY-хендшейк и проксирование работают."
