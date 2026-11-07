#!/usr/bin/env bash
# Деплой шлюза на чистой Ubuntu 22.04/24.04 за один запуск.
# Использование: sudo ./scripts/install.sh <SERVER_IP> [DEST_SNI] [PORT]
#   SERVER_IP  — публичный IPv4 (или IPv6) сервера
#   DEST_SNI   — (опционально) сайт-«одолжитель» для REALITY, по умолчанию www.samsung.com
#   PORT       — (опционально) порт inbound'а; по умолчанию 443. Нестандартный порт
#                (напр. 8443) — только если 443 занят: повышает заметность для DPI
#                (предупреждение самого Xray про non-443).
# Идемпотентно: повторный запуск обновляет конфиг и рестартует контейнер, секреты сохраняются.
set -euo pipefail
cd "$(dirname "$0")/.."   # -> deploy/

[ "$(id -u)" -eq 0 ] || { echo "ERROR: запустите через sudo" >&2; exit 1; }
SERVER_IP="${1:?Использование: sudo ./scripts/install.sh <SERVER_IP> [DEST_SNI] [PORT]}"
DEST_SNI="${2:-}"
PORT_ARG="${3:-}"

# 1) Docker + Compose (если отсутствуют)
if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq docker.io docker-compose-v2
  systemctl enable --now docker
fi
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y -qq docker-compose-v2
fi

# 2) Публичные параметры
if [ ! -f .env ]; then cp .env.example .env; fi
sed -i "s|^SERVER_HOST=.*|SERVER_HOST=${SERVER_IP}|" .env
if [ -n "$PORT_ARG" ]; then
  sed -i "s|^XRAY_PORT=.*|XRAY_PORT=${PORT_ARG}|" .env
fi

if [ -n "$DEST_SNI" ]; then sed -i "s|^XRAY_DEST=.*|XRAY_DEST=${DEST_SNI}|" .env; fi

# 3) Секреты (идемпотентно)
./scripts/gen-keys.sh

# 4) Рендер конфига из шаблона (секреты только сюда, файл вне git)
set -a; source .env; set +a
XRAY_VERSION="${XRAY_VERSION#v}"   # docker-тег — версия релиза БЕЗ 'v'
# ...и нормализуем в .env: `docker compose` читает файл напрямую, тег с 'v' не существует
if grep -qE '^XRAY_VERSION=' .env; then sed -i "s|^XRAY_VERSION=.*|XRAY_VERSION=${XRAY_VERSION}|" .env; fi
sed -e "s|__XRAY_PORT__|${XRAY_PORT}|g" \
    -e "s|__XRAY_UUID__|${XRAY_UUID}|g" \
    -e "s|__XRAY_DEST__|${XRAY_DEST}|g" \
    -e "s|__XRAY_REALITY_PRIVATE__|${XRAY_REALITY_PRIVATE}|g" \
    -e "s|__XRAY_SHORT_ID__|${XRAY_SHORT_ID}|g" \
    config/config.template.json > config/config.json
chmod 644 config/config.json

# 5) Валидация конфига пиннед-версией ядра (fail-fast до рестарта)
docker run --rm -v "$(pwd)/config/config.json:/usr/local/etc/xray/config.json:ro" \
  "ghcr.io/xtls/xray-core:${XRAY_VERSION}" run -test -c /usr/local/etc/xray/config.json

# 6) Firewall: открыть фактический порт inbound'а, если ufw активен
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "${XRAY_PORT:-443}/tcp"
fi

# 7) Старт
docker compose pull
docker compose up -d
sleep 2
docker logs --tail 20 xray-reality || true

# 8) Клиентский профиль
apt-get install -y -qq qrencode >/dev/null 2>&1 || true
echo
./scripts/gen-client-profile.sh
