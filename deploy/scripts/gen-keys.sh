#!/usr/bin/env bash
# Генерация секретов шлюза в deploy/.env (UUID клиента, x25519-пара REALITY, shortId).
# Идемпотентно: существующие значения не перезаписываются, повторный запуск безопасен.
set -euo pipefail
cd "$(dirname "$0")/.."   # -> deploy/

ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then cp .env.example "$ENV_FILE"; fi

XRAY_VERSION=$(grep -E '^XRAY_VERSION=' "$ENV_FILE" | cut -d= -f2 | tr -d '"' || true)
XRAY_VERSION=${XRAY_VERSION:-26.6.27}
XRAY_VERSION=${XRAY_VERSION#v}   # docker-тег — версия релиза БЕЗ 'v'

# Источник xray: локальная сборка (.bin/xray) — для локальных тестов, иначе docker с пиннед-тегом
run_xray() {
  if [ -x "../.bin/xray" ]; then
    "../.bin/xray" "$@"
  elif command -v docker >/dev/null 2>&1; then
    docker run --rm "ghcr.io/xtls/xray-core:${XRAY_VERSION}" "$@"
  else
    echo "ERROR: нужен docker или локальный бинарник Xray-core/.bin/xray" >&2
    exit 1
  fi
}

set_kv() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

# UUID клиента
if ! grep -qE '^XRAY_UUID=.+' "$ENV_FILE"; then
  set_kv XRAY_UUID "$(run_xray uuid)"
fi

# x25519-пара REALITY
if ! grep -qE '^XRAY_REALITY_PRIVATE=.+' "$ENV_FILE"; then
  OUT=$(run_xray x25519)
  PRIV=$(printf '%s\n' "$OUT" | awk '/^PrivateKey:/{print $2}')
  PUB=$(printf '%s\n' "$OUT" | awk '/^Password/{print $3}')
  [ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "ERROR: не удалось разобрать вывод xray x25519" >&2; exit 1; }
  set_kv XRAY_REALITY_PRIVATE "$PRIV"
  set_kv XRAY_REALITY_PUBLIC "$PUB"
fi

# shortId (0–16 hex; 8 hex достаточно)
if ! grep -qE '^XRAY_SHORT_ID=.+' "$ENV_FILE"; then
  set_kv XRAY_SHORT_ID "$(openssl rand -hex 4)"
fi

chmod 600 "$ENV_FILE"
echo "OK: секреты в deploy/.env готовы (XRAY_UUID, XRAY_REALITY_PRIVATE/PUBLIC, XRAY_SHORT_ID)."
