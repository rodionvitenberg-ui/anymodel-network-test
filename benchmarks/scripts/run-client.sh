#!/usr/bin/env bash
# Локальный Xray-клиент к боевому REALITY-серверу — для проверки и замеров (socks, без TUN).
# Использование:
#   GW_ENV_FILE=/tmp/gw-env ./run-client.sh            # foreground, Ctrl+C — остановка
#   LOCAL_SOCKS_PORT=10800 GW_ENV_FILE=... ./run-client.sh
# Секреты НЕ хранятся в репозитории: берутся из файла формата deploy/.env (GW_ENV_FILE)
# или из переменных SERVER_HOST/XRAY_PORT/XRAY_UUID/XRAY_REALITY_PUBLIC/XRAY_SHORT_ID/XRAY_DEST.
# Конфиг рендерится в /tmp с правами 600.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE=${GW_ENV_FILE:-}
[ -n "$ENV_FILE" ] || ENV_FILE="$HOME/.config/anygateway/client.env"
[ -f "$ENV_FILE" ] || ENV_FILE=/tmp/gw-env
SOCKS=${LOCAL_SOCKS_PORT:-10808}
HTTP=${LOCAL_HTTP_PORT:-10809}
BIN="$ROOT/.bin/xray"
[ -x "$BIN" ] || { echo "нет $BIN — собери: (cd Xray-core && go build -o ../.bin/xray ./main)" >&2; exit 1; }
get() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true; }
HOST=${SERVER_HOST:-$(get SERVER_HOST)}
UUID=${XRAY_UUID:-$(get XRAY_UUID)}
PUB=${XRAY_REALITY_PUBLIC:-$(get XRAY_REALITY_PUBLIC)}
SID=${XRAY_SHORT_ID:-$(get XRAY_SHORT_ID)}
DEST=${XRAY_DEST:-$(get XRAY_DEST)}
PORT=${XRAY_PORT:-$(get XRAY_PORT)}
PORT=${PORT:-443}
for v in HOST UUID PUB SID DEST; do
  [ -n "${!v}" ] || { echo "нет $v — задай переменные или GW_ENV_FILE (формат deploy/.env)" >&2; exit 1; }
done
CONF=$(mktemp /tmp/gw-client.XXXXXX.json)
trap 'rm -f "$CONF"' EXIT
cat > "$CONF" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"listen": "127.0.0.1", "port": ${SOCKS}, "protocol": "socks", "settings": {"udp": true}}, {"listen": "127.0.0.1", "port": ${HTTP}, "protocol": "http"}],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {"vnext": [{"address": "${HOST}", "port": ${PORT}, "users": [{"id": "${UUID}", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
      "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"serverName": "${DEST}", "fingerprint": "chrome", "publicKey": "${PUB}", "shortId": "${SID}", "spiderX": "/"}}
    }
  ]
}
EOF
chmod 600 "$CONF"

# Опционально: системный SOCKS-прокси для браузера (GNOME). Откат при выходе гарантирован.
# Отключить: SET_SYS_PROXY=0
SYS=${SET_SYS_PROXY:-1}
if [ "$SYS" = "1" ] && command -v gsettings >/dev/null 2>&1; then
  export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}
  P=org.gnome.system.proxy
  # ВАЖНО: перезаписываем http/https тоже — там могли остаться мёртвые значения от Hiddify
  gsettings set $P.http host '127.0.0.1' 2>/dev/null || true
  gsettings set $P.http port "$HTTP" 2>/dev/null || true
  gsettings set $P.https host '127.0.0.1' 2>/dev/null || true
  gsettings set $P.https port "$HTTP" 2>/dev/null || true
  gsettings set $P.socks host '127.0.0.1' 2>/dev/null || true
  gsettings set $P.socks port "$SOCKS" 2>/dev/null || true
  gsettings set $P mode 'manual' 2>/dev/null || true
  echo "[client] системный прокси: HTTP/HTTPS 127.0.0.1:${HTTP}, SOCKS 127.0.0.1:${SOCKS} — перезапусти браузер"
fi

shutdown() {
  kill "$XPID" 2>/dev/null || true
  wait "$XPID" 2>/dev/null || true
  if [ "$SYS" = "1" ] && command -v gsettings >/dev/null 2>&1; then
    P=org.gnome.system.proxy
    gsettings set $P.http host '' 2>/dev/null || true
    gsettings set $P.http port 0 2>/dev/null || true
    gsettings set $P.https host '' 2>/dev/null || true
    gsettings set $P.https port 0 2>/dev/null || true
    gsettings set $P.socks host '' 2>/dev/null || true
    gsettings set $P.socks port 0 2>/dev/null || true
    gsettings set $P mode 'none' 2>/dev/null || true
    echo "[client] системный прокси сброшен (mode 'none')"
  fi
}
trap shutdown EXIT
# INT/TERM/HUP (в т.ч. systemctl --user stop) — штатное завершение: exit 0,
# чтобы юнит не помечался failed; cleanup выполнит EXIT-трап. Падение xray
# (exit wait'а != 0 без сигнала) мимо этого трапа → Restart=on-failure работает.
trap 'exit 0' INT TERM HUP

echo "[client] socks5://127.0.0.1:${SOCKS} -> ${HOST}:${PORT} (SNI: ${DEST})"
"$BIN" run -c "$CONF" &
XPID=$!
wait "$XPID"
