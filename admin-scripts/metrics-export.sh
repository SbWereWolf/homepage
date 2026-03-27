#!/usr/bin/env bash
set -euo pipefail

INPUT="/var/log/server-metrics.log"
OUTPUT="/home/homepage/www/metrics/data.json"

mkdir -p "$(dirname "$OUTPUT")"

if [ ! -f "$INPUT" ]; then
  echo "[]" > "$OUTPUT"
  exit 0
fi

tail -200 "$INPUT" | awk '
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
  printf "{\"time\":\"%s\",\"load\":%s,\"ram\":%s,\"health\":\"%s\"}", ts, load, ram, health
}
END { print "\n]" }
' > "$OUTPUT"
