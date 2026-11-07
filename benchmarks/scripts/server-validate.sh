#!/usr/bin/env bash
# Серверная валидация деплоя (запускается на VPS от root).
# Порт берётся из deploy/.env (XRAY_PORT), корень репозитория — из пути скрипта.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/deploy" || exit 1
[ -f .env ] || { echo "ERROR: нет $ROOT/deploy/.env" >&2; exit 1; }
set -a; source .env; set +a
PORT=${XRAY_PORT:-443}
XRAY_VERSION="${XRAY_VERSION:-26.6.27}"; XRAY_VERSION="${XRAY_VERSION#v}"   # тот же пин, что у сервера

CONF=$(mktemp /tmp/xv-client.XXXXXX.json)
trap 'docker rm -f xv-client >/dev/null 2>&1; rm -f "$CONF"' EXIT

echo "=== 1) REALITY anti-probe: cert seen by unauthenticated client ==="
echo | openssl s_client -connect "127.0.0.1:${PORT}" -servername "${XRAY_DEST}" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

cat > "$CONF" <<EOF
{ "log": {"loglevel": "warning"},
  "inbounds": [{"listen": "0.0.0.0", "port": 10801, "protocol": "socks", "settings": {"udp": true}}],
  "outbounds": [ { "protocol": "vless",
      "settings": { "vnext": [ {"address": "127.0.0.1", "port": ${PORT},
        "users": [{"id": "${XRAY_UUID}", "flow": "xtls-rprx-vision", "encryption": "none"}]} ] },
      "streamSettings": { "network": "tcp", "security": "reality",
        "realitySettings": { "serverName": "${XRAY_DEST}", "fingerprint": "chrome",
          "publicKey": "${XRAY_REALITY_PUBLIC}", "shortId": "${XRAY_SHORT_ID}", "spiderX": "/" } } } ] }
EOF
chmod 644 "$CONF"   # клиентский контейнер идёт под uid 65532 — файл должен быть читаемым

docker rm -f xv-client >/dev/null 2>&1
# --network host: клиент должен видеть хостовый loopback (127.0.0.1:${PORT}, где слушает сервер)
docker run --rm -d --name xv-client --network host \
  -v "$CONF":/usr/local/etc/xray/config.json:ro \
  "ghcr.io/xtls/xray-core:${XRAY_VERSION}" run -c /usr/local/etc/xray/config.json >/dev/null
sleep 2

echo "=== 2) Full E2E on server (curl -> socks -> xray client -> REALITY -> xray server -> internet) ==="
curl -sS --max-time 20 --socks5-hostname 127.0.0.1:10801 \
  -o /dev/null -w 'E2E_GOOGLE=%{http_code} total=%{time_total}s\n' https://www.google.com/generate_204
curl -sS --max-time 20 --socks5-hostname 127.0.0.1:10801 \
  -o /dev/null -w 'E2E_OPENAI=%{http_code} total=%{time_total}s\n' https://api.openai.com/v1/models

echo '=== SERVER VALIDATION DONE ==='
