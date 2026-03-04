#!/usr/bin/env bash
set -u

# Self-healing watchdog:
# - пишет метрики в /var/log/server-metrics.log
# - лечит проблемы по эскалации: restart container -> restart docker -> reboot
# - не трогает контейнер во время старта и сразу после reboot (grace)
# - защищён от reboot loop (cooldown)
#
# Важно: ожидается, что docker-compose проект поднимается unit-ом kv1.service.

LOG="/var/log/server-watchdog.log"
METRIC_LOG="/var/log/server-metrics.log"
STATE="/var/lib/server-watchdog.state"
REBOOT_STATE="/var/lib/server-watchdog.reboot"

# ===== НАСТРОЙКИ =====
LOAD_LIMIT="2.0"        # float
RAM_LIMIT="90"          # percent
BOOT_GRACE=180          # сек после reboot, когда ничего не делаем
START_GRACE=120         # сек после старта контейнера, когда ничего не делаем
MAX_STAGE1=2            # 1..2: restart container / compose
MAX_STAGE2=4            # 3..4: restart docker
MAX_STAGE3=5            # 5+: reboot
REBOOT_COOLDOWN=3600    # 1 час
CONTAINER="homepage-nginx-1"
COMPOSE_UNIT="kv1.service"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /var/lib

log_action() {
  echo "$(date -Is) $*" >> "$LOG"
}

float_gt() {
  # usage: float_gt a b  -> 0 if a>b else 1
  awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>b)}'
}

container_exists() {
  docker inspect "$CONTAINER" >/dev/null 2>&1
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo false)" = "true" ]
}

container_health() {
  docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo unknown
}

write_metrics() {
  local ts load ram health
  ts="$(date -Is)"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo 0)"
  ram="$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}' 2>/dev/null || echo 0)"
  health="$(container_health)"
  echo "$ts load=$load ram=$ram health=$health" >> "$METRIC_LOG"
}

# ===== INIT STATE =====
if [ ! -f "$STATE" ]; then
  echo "0" > "$STATE"
fi
FAIL_COUNT="$(cat "$STATE" 2>/dev/null || echo 0)"

# ===== GRACE AFTER REBOOT =====
UPTIME="$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)"
if [ "$UPTIME" -lt "$BOOT_GRACE" ]; then
  exit 0
fi

# ===== METRICS =====
write_metrics

# ===== GRACE AFTER CONTAINER START =====
if container_exists; then
  STARTED_AT="$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER" 2>/dev/null || true)"
  if [ -n "$STARTED_AT" ]; then
    START_SEC="$(date -d "$STARTED_AT" +%s 2>/dev/null || echo 0)"
    NOW_SEC="$(date +%s)"
    AGE="$((NOW_SEC - START_SEC))"
    if [ "$AGE" -lt "$START_GRACE" ]; then
      exit 0
    fi
  fi
fi

PROBLEM=0
MISSING_OR_STOPPED=0

# ===== CHECKS =====
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
  PROBLEM=1
  MISSING_OR_STOPPED=1
elif ! container_running; then
  log_action "Container not running: $CONTAINER"
  PROBLEM=1
  MISSING_OR_STOPPED=1
else
  HEALTH="$(container_health)"
  if [ "$HEALTH" = "unhealthy" ]; then
    log_action "Container unhealthy"
    PROBLEM=1
  fi
fi

# ===== ESCALATION =====
if [ "$PROBLEM" -eq 1 ]; then
  FAIL_COUNT="$((FAIL_COUNT + 1))"
  echo "$FAIL_COUNT" > "$STATE"
else
  echo "0" > "$STATE"
  if [ -x "$SCRIPT_DIR/metrics-export.sh" ]; then
    "$SCRIPT_DIR/metrics-export.sh" >/dev/null 2>&1 || true
  fi
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
  systemctl restart docker >/dev/null 2>&1 || true

elif [ "$FAIL_COUNT" -ge "$MAX_STAGE3" ]; then
  NOW="$(date +%s)"
  if [ -f "$REBOOT_STATE" ]; then
    LAST_REBOOT="$(cat "$REBOOT_STATE" 2>/dev/null || echo 0)"
    DIFF="$((NOW - LAST_REBOOT))"
    if [ "$DIFF" -lt "$REBOOT_COOLDOWN" ]; then
      log_action "Stage 3 → Reboot skipped (cooldown active, ${DIFF}s < ${REBOOT_COOLDOWN}s)"
      exit 0
    fi
  fi

  echo "$NOW" > "$REBOOT_STATE"
  log_action "Stage 3 → Reboot server (fail_count=$FAIL_COUNT)"
  echo "0" > "$STATE"
  reboot
fi

if [ -x "$SCRIPT_DIR/metrics-export.sh" ]; then
  "$SCRIPT_DIR/metrics-export.sh" >/dev/null 2>&1 || true
fi
