#!/usr/bin/env bash
set -euo pipefail

# Ежедневное обслуживание (безопасно для продакшна):
# - чистит apt cache
# - ограничивает размер systemd journal
# - удаляет dangling docker images и build cache
# - чистит /tmp (старше 3 дней)
# - фиксит права на /var/lib/logrotate/status

LOG="/var/log/server-maintenance.log"

log() {
  echo "$(date -Is) $*" | tee -a "$LOG"
}

log "Maintenance start"

# apt cache
if command -v apt >/dev/null 2>&1; then
  log "apt clean"
  apt clean || true
fi

# journal size cap
if command -v journalctl >/dev/null 2>&1; then
  log "journalctl --vacuum-size=100M"
  journalctl --vacuum-size=100M || true
fi

# docker cleanup (без volume prune)
if command -v docker >/dev/null 2>&1; then
  log "docker image prune -f"
  docker image prune -f >/dev/null 2>&1 || true

  log "docker builder prune -f"
  docker builder prune -f >/dev/null 2>&1 || true

  log "docker container prune -f"
  docker container prune -f >/dev/null 2>&1 || true
fi

# /tmp cleanup
log "cleanup /tmp older than 3 days"
find /tmp -type f -mtime +3 -delete 2>/dev/null || true

# logrotate status permissions
if [ -f /var/lib/logrotate/status ]; then
  chmod 600 /var/lib/logrotate/status || true
fi

log "Maintenance done"
