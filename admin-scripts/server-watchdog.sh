#!/usr/bin/env bash
set -u

LOG="/var/log/server-watchdog.log"
METRIC_LOG="/var/log/server-metrics.log"
STATE="/var/lib/server-watchdog.state"
REBOOT_STATE="/var/lib/server-watchdog.reboot"

TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT="${TELEGRAM_CHAT:-}"

send_telegram() {
  local msg="$1"
  [ -n "${TELEGRAM_TOKEN}" ] || return 0
  [ -n "${TELEGRAM_CHAT}" ] || return 0
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"     --data-urlencode "chat_id=${TELEGRAM_CHAT}"     --data-urlencode "text=${msg}"     >/dev/null 2>&1 || true
}

# ===== SETTINGS =====
LOAD_LIMIT="2.0"
RAM_LIMIT="90"
BOOT_GRACE=180
START_GRACE=120
MAX_STAGE1=2
MAX_STAGE2=4
MAX_STAGE3=5
REBOOT_COOLDOWN=3600

CONTAINER="homepage-nginx-1"
COMPOSE_UNIT="kv1.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /var/lib

log_action() { echo "$(date -Is) $*" >> "$LOG"; }

float_gt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'; }

container_exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }
container_running() { [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]; }
container_health() { docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo unknown; }

write_metrics() {
  local ts load ram health
  ts="$(date -Is)"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
  ram="$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}' 2>/dev/null || echo 0)"
  health="$(container_health)"
  echo "$ts load=$load ram=$ram health=$health" >> "$METRIC_LOG"
}

[ -f "$STATE" ] || echo "0" > "$STATE"
FAIL_COUNT="$(cat "$STATE" 2>/dev/null || echo 0)"

UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
[ "$UPTIME" -lt "$BOOT_GRACE" ] && exit 0

write_metrics

if container_exists; then
  STARTED_AT="$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER" 2>/dev/null || true)"
  if [ -n "$STARTED_AT" ]; then
    START_SEC="$(date -d "$STARTED_AT" +%s 2>/dev/null || echo 0)"
    NOW_SEC="$(date +%s)"
    AGE="$((NOW_SEC - START_SEC))"
    [ "$AGE" -lt "$START_GRACE" ] && exit 0
  fi
fi

PROBLEM=0
MISSING_OR_STOPPED=0

CURRENT_LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
if float_gt "$CURRENT_LOAD" "$LOAD_LIMIT"; then
  log_action "High load: $CURRENT_LOAD (limit $LOAD_LIMIT)"
  PROBLEM=1
fi

RAM_USED="$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}' 2>/dev/null || echo 0)"
if [ "$RAM_USED" -ge "$RAM_LIMIT" ]; then
  log_action "High RAM: ${RAM_USED}% (limit ${RAM_LIMIT}%)"
  PROBLEM=1
fi

if ! container_exists; then
  log_action "Container missing: $CONTAINER"
  PROBLEM=1; MISSING_OR_STOPPED=1
elif ! container_running; then
  log_action "Container not running: $CONTAINER"
  PROBLEM=1; MISSING_OR_STOPPED=1
else
  HEALTH="$(container_health)"
  if [ "$HEALTH" = "unhealthy" ]; then
    log_action "Container unhealthy"
    PROBLEM=1
  fi
fi

if [ "$PROBLEM" -eq 1 ]; then
  FAIL_COUNT="$((FAIL_COUNT + 1))"
  echo "$FAIL_COUNT" > "$STATE"
else
  echo "0" > "$STATE"
  [ -x "$SCRIPT_DIR/metrics-export.sh" ] && "$SCRIPT_DIR/metrics-export.sh" >/dev/null 2>&1 || true
  exit 0
fi

if [ "$FAIL_COUNT" -le "$MAX_STAGE1" ]; then
  log_action "Stage 1 → Heal service/container (fail_count=$FAIL_COUNT)"
  if [ "$MISSING_OR_STOPPED" -eq 1 ]; then
    systemctl start "$COMPOSE_UNIT" >/dev/null 2>&1 || true
  else
    docker restart "$CONTAINER" >/dev/null 2>&1 || true
  fi
elif [ "$FAIL_COUNT" -le "$MAX_STAGE2" ]; then
  log_action "Stage 2 → Restart docker (fail_count=$FAIL_COUNT)"
  send_telegram "⚠️ kv1: Stage 2 — docker restart on $(hostname) (fail_count=$FAIL_COUNT)"
  systemctl restart docker >/dev/null 2>&1 || true
elif [ "$FAIL_COUNT" -ge "$MAX_STAGE3" ]; then
  NOW="$(date +%s)"
  if [ -f "$REBOOT_STATE" ]; then
    LAST_REBOOT="$(cat "$REBOOT_STATE" 2>/dev/null || echo 0)"
    DIFF="$((NOW - LAST_REBOOT))"
    if [ "$DIFF" -lt "$REBOOT_COOLDOWN" ]; then
      log_action "Stage 3 → Reboot skipped (cooldown active)"
      exit 0
    fi
  fi
  echo "$NOW" > "$REBOOT_STATE"
  log_action "Stage 3 → Reboot server (fail_count=$FAIL_COUNT)"
  send_telegram "🔥 kv1: Stage 3 — reboot on $(hostname) (fail_count=$FAIL_COUNT)"
  echo "0" > "$STATE"
  reboot
fi

[ -x "$SCRIPT_DIR/metrics-export.sh" ] && "$SCRIPT_DIR/metrics-export.sh" >/dev/null 2>&1 || true
