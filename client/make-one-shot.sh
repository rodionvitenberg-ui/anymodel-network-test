#!/usr/bin/env bash
# Генератор одноразового установщика шлюза: dist/anymodel-gw-installer.sh
#
# Использование:  ./client/make-one-shot.sh [файл-профиля]
#   (по умолчанию профиль берётся из ~/.config/anygateway/client.env)
#
# Результат — автономный скрипт: внутри зашиты секреты профиля и раннер,
# ядро скачивается при установке. Тестировщику достаточно:
#   bash anymodel-gw-installer.sh
# Секреты в git НЕ попадают (dist/ в .gitignore). Файл = credential:
# передавать только доверенным каналом; отзыв — ротация ключей на сервере.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_SRC="${1:-$HOME/.config/anygateway/client.env}"
[ -f "$ENV_SRC" ] || { echo "ERROR: нет файла профиля $ENV_SRC" >&2; exit 1; }
for k in SERVER_HOST XRAY_PORT XRAY_UUID XRAY_DEST XRAY_REALITY_PUBLIC XRAY_SHORT_ID; do
  grep -q "^$k=" "$ENV_SRC" || { echo "ERROR: в профиле нет $k" >&2; exit 1; }
done
VER=$(grep -E '^CLIENT_XRAY_VERSION=' "$ROOT/deploy/.env.example" | head -1 | cut -d= -f2- | tr -d '"' || true)
[ -n "$VER" ] || VER=$(grep -E '^XRAY_VERSION=' "$ROOT/deploy/.env.example" | head -1 | cut -d= -f2- | tr -d '"')
case "$VER" in v*) ;; *) VER="v$VER" ;; esac
HOST=$(grep -E '^SERVER_HOST=' "$ENV_SRC" | head -1 | cut -d= -f2-)
PORT=$(grep -E '^XRAY_PORT=' "$ENV_SRC" | head -1 | cut -d= -f2-)
DEST=$(grep -E '^XRAY_DEST=' "$ENV_SRC" | head -1 | cut -d= -f2-)

# раннер = benchmarks/scripts/run-client.sh, ROOT = каталог самого раннера (standalone)
RUNNER=$(mktemp /tmp/anygw-runner-XXXXXX)
trap 'rm -f "$RUNNER"' EXIT
sed 's|^ROOT=.*|ROOT="$(cd "$(dirname "$0")" \&\& pwd)"|' "$ROOT/benchmarks/scripts/run-client.sh" > "$RUNNER"
bash -n "$RUNNER" || { echo "ERROR: битый раннер" >&2; exit 1; }

OUT="$ROOT/dist/anymodel-gw-installer.sh"
mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<HEADER
#!/usr/bin/env bash
# Anygateway one-shot installer — собран $(date -u '+%Y-%m-%d %H:%M UTC'), ядро Xray-core ${VER}
# Профиль: anymodel-gw @ ${HOST}:${PORT} (SNI: ${DEST})
# ВНИМАНИЕ: файл содержит секреты профиля (UUID/PublicKey/shortId) — это credential.
# Не коммитить, не публиковать. Отзыв доступа — ротация ключей на сервере.
set -euo pipefail
command -v systemctl >/dev/null || { echo "ERROR: нужен systemd (user-менеджер)" >&2; exit 1; }
SHARE="\$HOME/.local/share/anygateway"
CONF="\$HOME/.config/anygateway"
XRAY_VER="${VER}"
mkdir -p "\$SHARE/.bin" "\$CONF" "\$HOME/.config/systemd/user"
chmod 700 "\$CONF" 2>/dev/null || true
HEADER

echo "base64 -d > \"\$CONF/client.env\" <<'B64ENV'" >> "$OUT"
base64 -w0 "$ENV_SRC" >> "$OUT"; echo >> "$OUT"; echo "B64ENV" >> "$OUT"
echo "base64 -d > \"\$SHARE/run-client.sh\" <<'B64RUN'" >> "$OUT"
base64 -w0 "$RUNNER" >> "$OUT"; echo >> "$OUT"; echo "B64RUN" >> "$OUT"

cat >> "$OUT" <<'BODY'
chmod 600 "$CONF/client.env"
chmod 755 "$SHARE/run-client.sh"
if [ ! -x "$SHARE/.bin/xray" ]; then
  case "$(uname -m)" in aarch64|arm64) A="Xray-linux-arm64-v8a.zip" ;; *) A="Xray-linux-64.zip" ;; esac
  echo "[i] скачиваю ядро Xray-core $XRAY_VER ($A)..."
  TMPZ=$(mktemp /tmp/xray-core-XXXXXX.zip)
  curl -fsSL -o "$TMPZ" "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}/${A}"
  if command -v unzip >/dev/null 2>&1; then
    unzip -o -q "$TMPZ" xray -d "$SHARE/.bin"
  else
    python3 -m zipfile -e "$TMPZ" "$SHARE/.bin"
  fi
  chmod +x "$SHARE/.bin/xray"; rm -f "$TMPZ"
fi
"$SHARE/.bin/xray" version | head -1
cat > "$HOME/.config/systemd/user/anymodel-gw.service" <<UNIT
[Unit]
Description=Anygateway REALITY client (Xray + system proxy)

[Service]
Type=simple
Environment=SET_SYS_PROXY=1
ExecStart=$SHARE/run-client.sh
ExecStopPost=/usr/bin/env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus gsettings set org.gnome.system.proxy mode 'none'
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=default.target
UNIT
systemctl --user stop anymodel-gw 2>/dev/null || true
pkill -f 'run-clien[t]' 2>/dev/null || true
pkill -x xray 2>/dev/null || true
sleep 1
systemctl --user daemon-reload
systemctl --user enable anymodel-gw >/dev/null 2>&1 || true
systemctl --user restart anymodel-gw
sleep 3
if [ "$(systemctl --user is-active anymodel-gw)" != "active" ]; then
  journalctl --user -u anymodel-gw --no-pager | tail -20 >&2
  echo "ERROR: сервис не поднялся" >&2
  exit 1
fi
CODE=$(curl -sS -m 12 -x http://127.0.0.1:10809 -o /dev/null -w '%{http_code}' https://www.google.com/generate_204 2>/dev/null || echo FAIL)
IP=$(curl -sS -m 12 -x http://127.0.0.1:10809 https://ifconfig.me 2>/dev/null || echo FAIL)
echo
echo "=== УСТАНОВЛЕНО (one-shot) ==="
echo "проверка:  generate_204 -> $CODE | exit-IP: $IP"
echo "стоп:      systemctl --user stop anymodel-gw    (прокси снимется сам)"
echo "старт:     systemctl --user start anymodel-gw"
echo "автозапуск выкл: systemctl --user disable anymodel-gw"
echo "Перезапусти браузер — туннель поднимается сам при каждом входе в систему."
BODY

chmod 755 "$OUT"
bash -n "$OUT" || { echo "ERROR: сгенерированный скрипт не проходит bash -n" >&2; exit 1; }
echo "OK: $OUT ($(stat -c '%s' "$OUT") байт) — содержит секреты, в git не коммитить"