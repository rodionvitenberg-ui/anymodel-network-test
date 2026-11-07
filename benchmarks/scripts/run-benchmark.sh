#!/usr/bin/env bash
# Клиентская батарея замеров (запускается с машины пользователя, через локальный socks клиента).
# Использование: SERVER_HOST=1.2.3.4 LOCAL_SOCKS_PORT=10800 ./run-benchmark.sh [label]
# Результат: benchmarks/results/<дата>-<label>.csv + stdout-сводка.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_HOST=${SERVER_HOST:?Нужен SERVER_HOST}
SOCKS=${LOCAL_SOCKS_PORT:-10800}
LABEL=${1:-$(date +%F-%H%M)}
OUT="$ROOT/benchmarks/results/${LABEL}.csv"
mkdir -p "$ROOT/benchmarks/results"
echo "metric,value,unit" > "$OUT"

note() { echo "[bench] $*"; }
row()  { echo "$1" | tee -a "$OUT"; }

# 1) Baseline RTT до сервера (напрямую, без туннеля)
note "ping до ${SERVER_HOST} (10 проб)..."
for i in $(seq 1 10); do
  ping -c 1 -W 2 "$SERVER_HOST" 2>/dev/null \
    | awk -F'time=' '/time=/{split($2,a," "); printf "ping_rtt_direct,%s,ms\n", a[1]}' >> "$OUT" || true
done

# 2) Прикладная latency: curl TTFB напрямую и через туннель (по 5 прогонов)
for i in $(seq 1 5); do
  T=$(curl -sS -o /dev/null --max-time 15 \
    -w "%{time_connect},%{time_appconnect},%{time_starttransfer}" \
    "https://api.openai.com/v1/models" 2>/dev/null) \
    && echo "ttfb_direct,${i},${T}" >> "$OUT" || echo "ttfb_direct,${i},fail,fail,fail" >> "$OUT"
  T=$(curl -sS -o /dev/null --max-time 15 --socks5-hostname "127.0.0.1:${SOCKS}" \
    -w "%{time_connect},%{time_appconnect},%{time_starttransfer}" \
    "https://api.openai.com/v1/models" 2>/dev/null) \
    && echo "ttfb_tunnel,${i},${T}" >> "$OUT" || echo "ttfb_tunnel,${i},fail,fail,fail" >> "$OUT"
done

# 3) Пропускная способность через туннель (даунлоад, по умолчанию 25 МБ)
note "даунлоад ${DOWNLOAD_BYTES:-25000000} байт через туннель..."
curl -sS -o /dev/null --max-time 120 --socks5-hostname "127.0.0.1:${SOCKS}" \
  -w "download_tunnel,${DOWNLOAD_BYTES:-25000000}B,%{speed_download}\n" \
  "https://speed.cloudflare.com/__down?bytes=${DOWNLOAD_BYTES:-25000000}" >> "$OUT" 2>/dev/null \
  || echo "download_tunnel,fail,fail" >> "$OUT"

# 4) Freeze-тест TCP 16-20 (bbs#490): ОДНО соединение, без range-запросов, по умолчанию до 50 МБ.
#    Если соединение замерзает — curl упрётся в --max-time; смотрим, сколько успело прийти.
note "freeze-тест: одно соединение, до ${FREEZE_BYTES:-50000000} байт, таймаут 60с..."
FREEZE_OUT=$(curl -sS -o /dev/null --max-time 60 --socks5-hostname "127.0.0.1:${SOCKS}" \
  -w "%{size_download},%{time_total}" \
  "https://speed.cloudflare.com/__down?bytes=${FREEZE_BYTES:-50000000}" 2>/dev/null || echo "stalled_or_failed")
echo "freeze_test_one_conn,${FREEZE_OUT},bytes,seconds" >> "$OUT"

note "готово: ${OUT}"
echo "--- сводка ---"
column -t -s, "$OUT" 2>/dev/null || cat "$OUT"
