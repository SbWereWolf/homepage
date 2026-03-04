#!/bin/bash

# chmod +x /root/server-watchdog.sh
# systemctl restart server-watchdog.timer

# Метрики
# cat /var/log/server-metrics.log
# Лог действий
# cat /var/log/server-watchdog.log

LOG="/var/log/server-watchdog.log"
METRIC_LOG="/var/log/server-metrics.log"
STATE="/var/lib/server-watchdog.state"
REBOOT_STATE="/var/lib/server-watchdog.reboot"
DATE=$(date)

# ===== НАСТРОЙКИ =====
LOAD_LIMIT=2.0
RAM_LIMIT=90
BOOT_GRACE=180
START_GRACE=120
MAX_STAGE1=2
MAX_STAGE2=4
MAX_STAGE3=5
REBOOT_COOLDOWN=3600   # 1 час
CONTAINER="homepage-nginx-1"

# ===== INIT STATE =====
mkdir -p /var/lib
[ -f "$STATE" ] || echo "0" > $STATE
FAIL_COUNT=$(cat $STATE)

# ===== BOOT GRACE =====
UPTIME=$(cut -d. -f1 /proc/uptime)
if [ "$UPTIME" -lt "$BOOT_GRACE" ]; then
    exit 0
fi

# ===== CONTAINER AGE CHECK =====
STARTED_AT=$(docker inspect -f '{{.State.StartedAt}}' $CONTAINER 2>/dev/null)
if [ -n "$STARTED_AT" ]; then
    START_SEC=$(date -d "$STARTED_AT" +%s)
    NOW_SEC=$(date +%s)
    AGE=$((NOW_SEC - START_SEC))
    if [ "$AGE" -lt "$START_GRACE" ]; then
        exit 0
    fi
fi

PROBLEM=0

# ===== METRICS =====
CURRENT_LOAD=$(awk '{print $1}' /proc/loadavg)
RAM_USED=$(free | awk '/Mem:/ {printf("%.0f"), $3/$2 * 100}')
HEALTH=$(docker inspect --format='{{.State.Health.Status}}' $CONTAINER 2>/dev/null)

echo "$DATE load=$CURRENT_LOAD ram=${RAM_USED}% health=$HEALTH" >> $METRIC_LOG

# ===== CHECKS =====
LOAD_EXCEEDED=$(echo "$CURRENT_LOAD > $LOAD_LIMIT" | bc)
if [ "$LOAD_EXCEEDED" -eq 1 ]; then
    PROBLEM=1
fi

if [ "$RAM_USED" -ge "$RAM_LIMIT" ]; then
    PROBLEM=1
fi

if [ "$HEALTH" = "unhealthy" ]; then
    PROBLEM=1
fi

# ===== ESCALATION =====
if [ "$PROBLEM" -eq 1 ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$FAIL_COUNT" > $STATE
else
    echo "0" > $STATE
    exit 0
fi

if [ "$FAIL_COUNT" -le "$MAX_STAGE1" ]; then
    echo "$DATE Stage 1 → Restart container" >> $LOG
    docker restart $CONTAINER

elif [ "$FAIL_COUNT" -le "$MAX_STAGE2" ]; then
    echo "$DATE Stage 2 → Restart docker" >> $LOG
    systemctl restart docker

elif [ "$FAIL_COUNT" -ge "$MAX_STAGE3" ]; then

    NOW=$(date +%s)

    if [ -f "$REBOOT_STATE" ]; then
        LAST_REBOOT=$(cat $REBOOT_STATE)
        DIFF=$((NOW - LAST_REBOOT))
        if [ "$DIFF" -lt "$REBOOT_COOLDOWN" ]; then
            echo "$DATE Reboot skipped (cooldown active)" >> $LOG
            exit 0
        fi
    fi

    echo "$NOW" > $REBOOT_STATE
    echo "$DATE Stage 3 → Reboot server" >> $LOG
    echo "0" > $STATE
    reboot
fi

/root/metrics-export.sh
