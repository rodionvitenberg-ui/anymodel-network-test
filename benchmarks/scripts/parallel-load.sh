#!/usr/bin/env bash
# Расширенная клиентская батарея: базовая линия vs туннель, параллельные потоки,
# latency под нагрузкой, аплоад, большое односоединение, конкуренция сессий.
# Дополняет run-benchmark.sh (короткая батарея: ping/TTFB/даунлоад/freeze 50 МБ).
#
# Использование:
#   SERVER_HOST=1.2.3.4 LOCAL_SOCKS_PORT=10808 ./parallel-load.sh [label]
# Результат: benchmarks/results/<label>-parallel.csv + stdout-сводка.
#
# ВНИМАНИЕ: цифры имеют смысл только относительно базовой линии (direct) из того же
# прогона: узкое место локализуется сравнением direct/tunnel на одном эндпоинте.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER_HOST=${SERVER_HOST:?Нужен SERVER_HOST}
SOCKS=${LOCAL_SOCKS_PORT:-10808}
LABEL=${1:-$(date +%F-%H%M)}
OUT="$ROOT/benchmarks/results/${LABEL}-parallel.csv"
BIG_BYTES=${BIG_BYTES:-536870912}     # 512 МБ — одно соединение, «большой» тест
SRC=https://speed.cloudflare.com
BIG_URL=${BIG_URL:-http://ipv4.download.thinkbroadband.com/512MB.zip}
mkdir -p "$ROOT/benchmarks/results"
{ echo "metric,value,unit"; } > "$OUT"
note() { echo "[bench] $*"; }
row() { echo "$1" | tee -a "$OUT"; }
dl() { # $1=label $2=url $3=«socks» — мерить через туннель (пусто — напрямую)
  local r mode=${3:-}
  if [ -n "$mode" ]; then
    r=$(curl -sS -o /dev/null --max-time 180 --socks5-hostname "127.0.0.1:${SOCKS}" \
        -w "%{speed_download},%{time_total}" "$2" 2>/dev/null)
  else
    r=$(curl -sS -o /dev/null --max-time 180 -w "%{speed_download},%{time_total}" "$2" 2>/dev/null)
  fi
  [ -n "$r" ] && row "$1,$r,B/s,s" || row "$1,fail,-"
}

# 1-2. Базовая линия и туннель на одном эндпоинте (50 МБ): локализация узкого места
note "50 МБ: напрямую, затем через туннель..."
dl download_direct_50MB "${SRC}/__down?bytes=50000000"
dl download_tunnel_50MB "${SRC}/__down?bytes=50000000" socks

# 3. Параллельные потоки: N соединений по M байт; агрегат по wall-time
par_test() { # $1=потоки $2=байт $3=метка
  local n=$1 b=$2 label=$3 t0 t1 wall ok agg f="/tmp/par.$$.$3"
  rm -f "$f"; t0=$(date +%s%N)
  for i in $(seq 1 "$n"); do
    ( curl -sS -o /dev/null --max-time 120 --socks5-hostname "127.0.0.1:${SOCKS}" \
        -w "%{speed_download}\n" "${SRC}/__down?bytes=${b}" 2>/dev/null || echo fail
    ) >> "$f" &
  done
  wait; t1=$(date +%s%N)
  wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f",(b-a)/1e9}')
  ok=$(grep -c -v '^fail$' "$f" 2>/dev/null || true)
  rm -f "$f"
  agg=$(awk -v t=$((n*b)) -v w="$wall" 'BEGIN{printf "%.0f", t/w}')
  row "parallel_${n}x$((b/1000000))MB,agg=${agg}B/s wall=${wall}s streams=${n},B/s"
}
note "параллельные потоки 4x10 МБ и 8x5 МБ..."
par_test 4 10000000 p4
par_test 8 5000000 p8

# 4. Latency под нагрузкой: 4 потока 25 МБ, параллельно ping и TTFB через туннель
note "latency под нагрузкой (4 потока)..."
( for _ in 1 2 3 4; do curl -sS -o /dev/null --max-time 120 --socks5-hostname "127.0.0.1:${SOCKS}" \
    "${SRC}/__down?bytes=25000000" & done; wait ) &
LOADPID=$!
sleep 2
for _ in $(seq 1 12); do
  ping -c 1 -W 2 "$SERVER_HOST" 2>/dev/null \
    | awk -F'time=' '/time=/{split($2,a," "); printf "ping_under_load,%s,ms\n", a[1]}' | tee -a "$OUT"
done
for _ in $(seq 1 6); do
  curl -sS -o /dev/null --max-time 15 --socks5-hostname "127.0.0.1:${SOCKS}" \
    -w "ttfb_tunnel_under_load,%{time_starttransfer},s\n" "https://www.google.com/generate_204" 2>/dev/null \
    | tee -a "$OUT"
done
wait "$LOADPID" 2>/dev/null

# 5. Аплоад 10 МБ: напрямую и через туннель (асимметрия канала)
BIN=/tmp/up10mb.$$.bin; head -c 10000000 /dev/zero > "$BIN"
for mode in direct tunnel; do
  if [ "$mode" = tunnel ]; then P=(--socks5-hostname "127.0.0.1:${SOCKS}"); else P=(); fi
  r=$(curl -sS -o /dev/null --max-time 120 "${P[@]}" -X POST --data-binary @"$BIN" \
      -w "%{speed_upload},%{time_total}" "${SRC}/__up" 2>/dev/null)
  [ -n "$r" ] && row "upload_${mode}_10MB,$r,B/s,s" || row "upload_${mode}_10MB,fail,-"
done
rm -f "$BIN"

# 6. Большое односоединение (freeze-тест): 512 МБ одним потоком без range-запросов
note "большой файл одним соединением (до ${BIG_BYTES} Б, таймаут 90 с)..."
BIG=$(curl -sS -o /dev/null --max-time 90 --socks5-hostname "127.0.0.1:${SOCKS}" \
  -w "%{size_download},%{time_total},%{speed_download}" "$BIG_URL" 2>/dev/null || echo "stalled")
row "bigfile_one_conn_tunnel,${BIG},bytes,seconds,B/s"

# 7. Конкуренция мелких сессий: 50 и 100 одновременных запросов
conc_test() { # $1=число сессий
  local n=$1 f="/tmp/conc.$$.$1" t0 t1 wall ok mean max
  rm -f "$f"; t0=$(date +%s%N)
  for _ in $(seq 1 "$n"); do
    ( curl -sS -o /dev/null --max-time 40 --socks5-hostname "127.0.0.1:${SOCKS}" \
        -w "%{http_code} %{time_starttransfer}\n" "https://www.google.com/generate_204" 2>/dev/null \
        || echo "fail -" ) >> "$f" &
  done
  wait; t1=$(date +%s%N); wall=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.2f",(b-a)/1e9}')
  ok=$(grep -c '^204' "$f" || true)
  read -r mean max < <(awk '{s+=$2; if($2>m)m=$2} END{printf "%.3f %.3f", s/NR, m}' "$f")
  rm -f "$f"
  row "concurrency_${n},ok=${ok}/${n} wall=${wall}s mean_ttfb=${mean}s max_ttfb=${max}s,sessions"
}
note "конкуренция сессий (${SESSIONS:-50 100})..."
for n in ${SESSIONS:-50 100}; do conc_test "$n"; done

note "готово: $OUT"
echo "--- сводка ---"
column -t -s, "$OUT" 2>/dev/null || cat "$OUT"
