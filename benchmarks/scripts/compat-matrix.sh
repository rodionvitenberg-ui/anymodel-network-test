#!/usr/bin/env bash
# Матрица совместимости REALITY: сервер Xray-core N x клиенты (sing-box = ядро Hiddify, xray-клиент).
# Отвечает на вопрос «какую версию сервера ставить, чтобы работал Hiddify/v2rayNG/наш клиент».
# Обоснование пина 26.6.27: docs/adr/0001-server-pinned-26.6.27.md
#
# Использование:
#   ./benchmarks/scripts/compat-matrix.sh                 # 26.6.27 + 26.10.31 vs sing-box 1.14.4 и xray-клиент
#   SERVER_VERSIONS="26.6.27 26.7.28 26.9.9" ./compat-matrix.sh
#   SINGBOX_VERSION=1.15.0-alpha.13 ./compat-matrix.sh
# Требует: curl, unzip/tar, сеть (бинарники качаются в CACHE, по умолчанию /tmp/anygw-compat).
# Секреты берутся из deploy/.env и в вывод не попадают.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/deploy" || exit 1
[ -f .env ] || ./scripts/gen-keys.sh >/dev/null || exit 1
set -a; source .env; set +a

SERVER_VERSIONS=${SERVER_VERSIONS:-"26.6.27 26.10.31"}
SINGBOX_VERSION=${SINGBOX_VERSION:-1.14.4}
CHECK_URL=${CHECK_URL:-https://www.google.com/generate_204}
CACHE=${CACHE:-/tmp/anygw-compat}
PORT_BASE=${PORT_BASE:-19400}
mkdir -p "$CACHE"

case "$(uname -m)" in
  aarch64|arm64) XRAY_ASSET=Xray-linux-arm64-v8a.zip; SB_ARCH=arm64 ;;
  *)             XRAY_ASSET=Xray-linux-64.zip;        SB_ARCH=amd64 ;;
esac

# --- получение бинарников (кэшируется) ---
fetch_xray() { # $1=version -> путь к бинарнику
  local v=$1
  local dir="$CACHE/xray-$v"
  [ -x "$dir/xray" ] && { echo "$dir/xray"; return; }
  mkdir -p "$dir"
  if curl -fsSL -o "$CACHE/xray-$v.zip" "https://github.com/XTLS/Xray-core/releases/download/v$v/$XRAY_ASSET" \
     && unzip -o -q "$CACHE/xray-$v.zip" xray -d "$dir"; then
    chmod +x "$dir/xray"; echo "$dir/xray"
  else
    echo "ERROR: не скачался Xray-core $v" >&2; return 1
  fi
}

fetch_singbox() {
  local v=$1
  local dir="$CACHE/sing-box-$v"
  [ -x "$dir/sing-box" ] && { echo "$dir/sing-box"; return; }
  mkdir -p "$dir"
  if curl -fsSL -o "$CACHE/sb-$v.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v$v/sing-box-$v-linux-$SB_ARCH.tar.gz" \
     && tar xzf "$CACHE/sb-$v.tar.gz" -C "$dir" --strip-components=1; then
    chmod +x "$dir/sing-box"; echo "$dir/sing-box"
  else
    echo "ERROR: не скачался sing-box $v" >&2; return 1
  fi
}

# клиент xray: локальная сборка, иначе пин из deploy/.env.example
CLIENT_XRAY=${CLIENT_XRAY:-"$ROOT/.bin/xray"}
if [ ! -x "$CLIENT_XRAY" ]; then
  CV=$(grep -E '^CLIENT_XRAY_VERSION=' .env.example | head -1 | cut -d= -f2- | tr -d '"' || true)
  CV=${CV:-26.10.31}; CV=${CV#v}
  CLIENT_XRAY=$(fetch_xray "$CV") || exit 1
fi
SB_BIN=$(fetch_singbox "$SINGBOX_VERSION") || exit 1

# --- конфиги ---
render_server() { # $1=port $2=out
  sed -e "s|__XRAY_PORT__|$1|g" \
      -e "s|__XRAY_UUID__|${XRAY_UUID}|g" \
      -e "s|__XRAY_DEST__|${XRAY_DEST}|g" \
      -e "s|__XRAY_REALITY_PRIVATE__|${XRAY_REALITY_PRIVATE}|g" \
      -e "s|__XRAY_SHORT_ID__|${XRAY_SHORT_ID}|g" \
      config/config.template.json > "$2"
}

render_singbox_client() { # $1=port $2=socks $3=out
  cat > "$3" <<EOF
{
  "log": {"level": "info"},
  "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": $2}],
  "outbounds": [{
    "type": "vless", "server": "127.0.0.1", "server_port": $1,
    "uuid": "${XRAY_UUID}", "flow": "xtls-rprx-vision",
    "tls": {"enabled": true, "server_name": "${XRAY_DEST}",
      "utls": {"enabled": true, "fingerprint": "chrome"},
      "reality": {"enabled": true, "public_key": "${XRAY_REALITY_PUBLIC}", "short_id": "${XRAY_SHORT_ID}"}}
  }]
}
EOF
}

render_xray_client() { # $1=port $2=socks $3=out
  cat > "$3" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{"listen": "127.0.0.1", "port": $2, "protocol": "socks", "settings": {"udp": true}}],
  "outbounds": [{
    "protocol": "vless",
    "settings": {"vnext": [{"address": "127.0.0.1", "port": $1,
      "users": [{"id": "${XRAY_UUID}", "flow": "xtls-rprx-vision", "encryption": "none"}]}]},
    "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {
      "serverName": "${XRAY_DEST}", "fingerprint": "chrome",
      "publicKey": "${XRAY_REALITY_PUBLIC}", "shortId": "${XRAY_SHORT_ID}", "spiderX": "/"}}
  }]
}
EOF
}

# --- прогон одной пары ---
run_case() { # $1=server_bin $2=port $3=client_bin $4=kind(singbox|xray) -> код HTTP
  local wd; wd=$(mktemp -d "$CACHE/case-XXXXXX")
  render_server "$2" "$wd/server.json"
  local socks=$(( $2 + 1 ))
  case "$4" in
    singbox) render_singbox_client "$2" "$socks" "$wd/client.json" ;;
    xray)    render_xray_client    "$2" "$socks" "$wd/client.json" ;;
  esac
  "$1" run -test -c "$wd/server.json" >/dev/null 2>&1 || { echo "cfg-invalid"; return; }
  "$1" run -c "$wd/server.json" > "$wd/server.log" 2>&1 & local srv=$!
  sleep 1.2
  "$3" run -c "$wd/client.json" > "$wd/client.log" 2>&1 & local cli=$!
  sleep 2.5
  curl -sS --max-time 12 --socks5-hostname "127.0.0.1:$socks" -o /dev/null -w '%{http_code}' "$CHECK_URL" 2>/dev/null
  kill -9 "$srv" "$cli" 2>/dev/null; wait "$srv" "$cli" 2>/dev/null
}

echo "Стенд: sing-box $SINGBOX_VERSION | xray-клиент $("$CLIENT_XRAY" version | head -1 | cut -d' ' -f2)"
printf '%-10s %-28s %-12s\n' "СЕРВЕР" "sing-box (Hiddify core)" "xray-клиент"
i=0
for v in $SERVER_VERSIONS; do
  SBIN=$(fetch_xray "$v") || continue
  port=$(( PORT_BASE + i * 4 )); i=$(( i + 1 ))
  sb=$(run_case "$SBIN" "$port" "$SB_BIN" singbox)
  xr=$(run_case "$SBIN" "$(( port + 2 ))" "$CLIENT_XRAY" xray)
  printf '%-10s %-28s %-12s\n' "$v" "${sb:-?}" "${xr:-?}"
done
echo
echo "204 = туннель работает. '000' в колонке sing-box = REALITY-гейт сервера (см. docs/adr/0001)."
