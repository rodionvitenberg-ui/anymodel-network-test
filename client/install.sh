#!/usr/bin/env bash
# Одноразовая установка клиента на ПК: секреты + автозапуск через systemd --user.
#
# Использование:
#   ./client/install.sh "vless://..."    # разобрать профиль из VLESS-строки (рекомендуется)
#   ./client/install.sh --ssh [alias]    # или стянуть секреты с сервера по SSH (спросит sudo-пароль)
#
# После установки туннель включается сам при каждом входе в систему; системный
# прокси браузеру ставится при старте и снимается при остановке автоматически.
# Секреты хранятся в ~/.config/anygateway/client.env (600, вне git).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR=${GW_CONFIG_DIR:-$HOME/.config/anygateway}
ENV_FILE="$DIR/client.env"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/anymodel-gw.service"
SERVICE=anymodel-gw
mkdir -p "$DIR" "$UNIT_DIR"
chmod 700 "$DIR"

write_env_from_fields() { # HOST PORT UUID DEST PUB SID
  local f
  for f in "$@"; do
    [ -n "$f" ] || { echo "ERROR: не все поля профиля получены" >&2; exit 1; }
  done
  umask 077
  cat > "$ENV_FILE" <<EOF
SERVER_HOST=$1
XRAY_PORT=$2
XRAY_UUID=$3
XRAY_DEST=$4
XRAY_REALITY_PUBLIC=$5
XRAY_SHORT_ID=$6
EOF
  chmod 600 "$ENV_FILE"
}

if [ "${1:-}" = "--ssh" ]; then
  ALIAS=${2:-${GW_SSH_ALIAS:-final}}
  REMOTE_ENV=${GW_REMOTE_ENV:-anymodel-network-test/deploy/.env}   # путь относительно ~ на сервере
  echo "[i] тяну секреты с сервера '$ALIAS' (введи sudo-пароль сервера на запрос)..."
  ssh -t "$ALIAS" "sudo -p '[sudo] $ALIAS: ' grep -E '^(SERVER_HOST|XRAY_PORT|XRAY_UUID|XRAY_REALITY_PUBLIC|XRAY_SHORT_ID|XRAY_DEST)=' $REMOTE_ENV" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  [ "$(grep -c '=' "$ENV_FILE")" -eq 6 ] || { echo "ERROR: с сервера пришло не 6 полей" >&2; exit 1; }
elif [ -n "${1:-}" ]; then
  URI=$1
  case "$URI" in vless://*) ;; *) echo "ERROR: ожидалась vless:// строка" >&2; exit 1 ;; esac
  BODY=${URI#vless://}
  AUTH=${BODY%%\?*}
  QUERY=${BODY#*\?}; QUERY=${QUERY%%#*}
  UUID=${AUTH%%@*}
  HOSTPORT=${AUTH#*@}
  HOST=${HOSTPORT%%:*}
  PORT=${HOSTPORT##*:}
  SNI=; PBK=; SID=
  IFS='&' read -ra KV <<< "$QUERY"
  for kv in "${KV[@]}"; do
    k=${kv%%=*}; v=${kv#*=}
    case "$k" in
      sni) SNI=$v ;;
      pbk) PBK=$v ;;
      sid) SID=$v ;;
    esac
  done
  write_env_from_fields "$HOST" "$PORT" "$UUID" "$SNI" "$PBK" "$SID"
  echo "[i] профиль разобран из VLESS-строки"
else
  echo "Использование: $0 \"vless://...\"   |   $0 --ssh [ssh-alias]" >&2
  exit 1
fi

if [ ! -x "$ROOT/.bin/xray" ]; then
  # Ядро — из официального релиза (пин из deploy/.env.example); сборка из субмодуля — fallback.
  # Свежий клон не содержит субмодуль и .bin, поэтому go требовать нельзя: качаем пиннед-бинарник.
  XRAY_VER=$(grep -E '^CLIENT_XRAY_VERSION=' "$ROOT/deploy/.env.example" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  [ -n "${XRAY_VER:-}" ] || XRAY_VER=$(grep -E '^XRAY_VERSION=' "$ROOT/deploy/.env.example" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
  case "${XRAY_VER:-}" in v*) ;; *) XRAY_VER="v${XRAY_VER:-26.10.31}" ;; esac
  case "$(uname -m)" in
    aarch64|arm64) XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
    *)             XRAY_ASSET="Xray-linux-64.zip" ;;
  esac
  echo "[i] скачиваю ядро Xray-core $XRAY_VER ($XRAY_ASSET)..."
  mkdir -p "$ROOT/.bin"
  TMPZ=$(mktemp /tmp/xray-core-XXXXXX.zip)
  if curl -fsSL -o "$TMPZ" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/${XRAY_ASSET}"; then
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -q "$TMPZ" xray -d "$ROOT/.bin"
    else
      python3 -m zipfile -e "$TMPZ" "$ROOT/.bin"
    fi
    chmod +x "$ROOT/.bin/xray"
  elif command -v go >/dev/null 2>&1; then
    echo "[i] релиз недоступен — собираю из субмодуля (нужны go и git submodule update --init)..."
    (cd "$ROOT/Xray-core" && go build -o "$ROOT/.bin/xray" ./main)
  else
    rm -f "$TMPZ"
    echo "ERROR: не удалось получить ядро (нет сети/unzip/python3/go) — положите бинарник в $ROOT/.bin/xray" >&2
    exit 1
  fi
  rm -f "$TMPZ"
  "$ROOT/.bin/xray" version | head -1
fi

if ss -tln 2>/dev/null | grep -q ':10808 '; then
  echo "[i] порт 10808 занят — останавливаю ручной экземпляр клиента..."
  pkill -f 'run-clien[t]' 2>/dev/null || true
  pkill -x xray 2>/dev/null || true
  sleep 1
  if ss -tln 2>/dev/null | grep -q ':10808 '; then
    echo "ERROR: порт 10808 всё ещё занят — разберись вручную" >&2
    exit 1
  fi
fi

cat > "$UNIT" <<EOF
[Unit]
Description=Anygateway REALITY client (Xray + system proxy)

[Service]
Type=simple
Environment=SET_SYS_PROXY=1
ExecStart=$ROOT/benchmarks/scripts/run-client.sh
ExecStopPost=/usr/bin/env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus gsettings set org.gnome.system.proxy mode 'none'
Restart=on-failure
RestartSec=5
# ручной `systemctl --user stop` убивает run-client.sh SIGTERM'ом (exit 143) — это НЕ падение
SuccessExitStatus=143

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable "$SERVICE" >/dev/null 2>&1 || true
systemctl --user restart "$SERVICE"
sleep 3
if [ "$(systemctl --user is-active "$SERVICE")" != "active" ]; then
  echo "ERROR: сервис не поднялся:" >&2
  journalctl --user -u "$SERVICE" --no-pager | tail -20 >&2
  exit 1
fi
IP=$(curl -sS -x http://127.0.0.1:10809 --max-time 10 https://ifconfig.me 2>/dev/null || echo FAIL)
EXPECT=$(grep -E '^SERVER_HOST=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)

echo
echo "=== УСТАНОВЛЕНО ==="
echo "сервис:    systemctl --user status $SERVICE   ($(systemctl --user is-active "$SERVICE"), автозапуск: $(systemctl --user is-enabled "$SERVICE"))"
echo "секреты:   $ENV_FILE"
echo "exit-IP:   $IP   (ожидание: ${EXPECT:-хост сервера из профиля})"
echo "стоп:      systemctl --user stop $SERVICE    (прокси браузера снимется сам)"
echo "старт:     systemctl --user start $SERVICE"
echo "выключить автозапуск: systemctl --user disable $SERVICE"
echo
echo "Перезапусти браузер — и пользуйся. Туннель поднимается сам при каждом входе в систему."
