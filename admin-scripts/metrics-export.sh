#!/usr/bin/env bash
set -euo pipefail

INPUT="/var/log/server-metrics.log"
OUTPUT="/home/homepage/www/metrics/data.json"

LOAD_CPU_COUNT="$(nproc 2>/dev/null || true)"
if ! printf '%s\n' "$LOAD_CPU_COUNT" | grep -Eq '^[1-9][0-9]*$'; then
  echo "metrics-export: nproc returned invalid CPU count: ${LOAD_CPU_COUNT:-empty}" >&2
  LOAD_CPU_COUNT=""
fi

mkdir -p "$(dirname "$OUTPUT")"

if [ ! -f "$INPUT" ]; then
  echo "[]" > "$OUTPUT"
  exit 0
fi

tail -200 "$INPUT" | awk -v cpu_count="$LOAD_CPU_COUNT" '
BEGIN { print "["; first=1 }
{
  ts=$1
  load="0"; ram="0"; health="unknown"
  for (i=2; i<=NF; i++) {
    split($i, kv, "=")
    if (kv[1]=="load") load=kv[2]
    if (kv[1]=="ram")  ram=kv[2]
    if (kv[1]=="health") health=kv[2]
  }
  if (!first) printf ",\n"
  first=0
  if (cpu_count ~ /^[1-9][0-9]*$/) {
    load_percent = load / cpu_count * 100
    load_value = sprintf("%.0f", load_percent)
  } else {
    load_value = "null"
  }
  printf "{\"time\":\"%s\",\"load\":%s,\"ram\":%s,\"health\":\"%s\"}", ts, load_value, ram, health
}
END { print "\n]" }
' > "$OUTPUT"
