#!/usr/bin/env bash
# Серверная часть бенчмарка (запускается на VPS от root).
# Сэмплирует docker stats контейнера шлюза + сетевые счётчики + число установленных
# соединений на порту REALITY → CSV в stdout.
#
# Использование:
#   sudo ./server-benchmark.sh [duration_sec] [port]
#   sudo ./server-benchmark.sh 120 443 > /tmp/server.csv
#   # на клиентской машине удобно гонять удалённо:
#   #   ssh <vps> "sudo ./server-benchmark.sh 120 443" > benchmarks/results/<label>-server.csv
#
# iperf3 не требуется: пропускная способность меряется со стороны клиента
# (run-benchmark.sh / parallel-load.sh), здесь — стоимость сервера под этой нагрузкой.
set -euo pipefail
DUR=${1:-120}
PORT=${2:-443}
CONTAINER=${CONTAINER:-xray-reality}
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
IFACE=${IFACE:-eth0}

echo "ts,cpu_percent,mem_usage,mem_percent,rx_bytes,tx_bytes,load1,conns"
for _ in $(seq 1 "$DUR"); do
  TS=$(date +%H:%M:%S)
  STATS=$(docker stats --no-stream --format '{{.CPUPerc}};{{.MemUsage}};{{.MemPerc}}' "$CONTAINER" 2>/dev/null | head -1)
  RX=$(cat "/sys/class/net/${IFACE}/statistics/rx_bytes" 2>/dev/null || echo 0)
  TX=$(cat "/sys/class/net/${IFACE}/statistics/tx_bytes" 2>/dev/null || echo 0)
  LA=$(cut -d' ' -f1 /proc/loadavg)
  CONNS=$(ss -Htn state established "( sport = :${PORT} )" 2>/dev/null | wc -l)
  echo "${TS},${STATS:-n/a;n/a;n/a},${RX},${TX},${LA},${CONNS}"
  sleep 1
done
