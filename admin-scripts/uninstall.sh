#!/usr/bin/env bash
set -euo pipefail

# kv1 uninstall (safe-by-default)
# - By default runs in DRY-RUN mode (prints actions only)
# - Real deletion only with: --force
#
# Removes ONLY things created/managed by kv1 admin-scripts outside the repo:
# - systemd units/timers (kv1, watchdog, maintenance, deploy)
# - /usr/local/bin helper scripts (server-watchdog, metrics-export, etc.)
# - configs under /etc/* created by our tooling (docker daemon.json, journald drop-in, fail2ban jail.local, /etc/kv1 telegram env)
# - logrotate snippets created by our tooling
# - runtime state in /var/lib + logs in /var/log
# - stops docker compose stack and removes volumes: docker compose down -v
#
# Does NOT remove OS packages (docker/fail2ban/etc.) and does NOT delete the repo.

FORCE=0
if [[ "${1:-}" == "--force" ]]; then
  FORCE=1
fi

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/kv1-uninstall-backup-$TS"
mkdir -p "$BACKUP_DIR"

say() { echo "[$(date -Is)] $*"; }

doit() {
  if [[ "$FORCE" -eq 1 ]]; then
    eval "$@"
  else
    say "DRY-RUN: $*"
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    doit "cp -a "$f" "$BACKUP_DIR/""
  fi
}

rm_file() {
  local f="$1"
  if [[ -e "$f" ]]; then
    backup_file "$f"
    doit "rm -f "$f""
  fi
}

rm_dir() {
  local d="$1"
  if [[ -d "$d" ]]; then
    # best-effort backup tarball
    doit "tar -czf "$BACKUP_DIR/$(echo "$d" | tr '/' '_' | sed 's/^_//').tgz" "$d" >/dev/null 2>&1 || true"
    doit "rm -rf "$d""
  fi
}

stop_disable_unit() {
  local u="$1"
  if has_cmd systemctl; then
    doit "systemctl stop "$u" >/dev/null 2>&1 || true"
    doit "systemctl disable "$u" >/dev/null 2>&1 || true"
  fi
}

say "=== kv1 uninstall starting ==="
say "Mode: $([[ "$FORCE" -eq 1 ]] && echo REAL || echo DRY-RUN)"
say "Backup dir: $BACKUP_DIR"

if [[ "$(id -u)" -ne 0 ]]; then
  say "ERROR: run as root (sudo)."
  exit 1
fi

# 1) Stop/disable our services/timers
stop_disable_unit "kv1.service"
stop_disable_unit "kv1-deploy.service"
stop_disable_unit "kv1-deploy.timer"
stop_disable_unit "server-watchdog.service"
stop_disable_unit "server-watchdog.timer"
stop_disable_unit "server-maintenance.service"
stop_disable_unit "server-maintenance.timer"

# 2) Stop compose stack + remove volumes (if repo exists)
if [[ -f "/home/homepage/docker-compose.yml" ]] && has_cmd docker; then
  say "Compose detected -> docker compose down -v"
  doit "cd /home/homepage && docker compose down -v >/dev/null 2>&1 || true"
fi

# 3) Remove systemd unit files we installed/managed
rm_file "/etc/systemd/system/kv1.service"
rm_file "/etc/systemd/system/kv1-deploy.service"
rm_file "/etc/systemd/system/kv1-deploy.timer"
rm_file "/etc/systemd/system/server-watchdog.service"
rm_file "/etc/systemd/system/server-watchdog.timer"
rm_file "/etc/systemd/system/server-maintenance.service"
rm_file "/etc/systemd/system/server-maintenance.timer"

# 4) Remove docker systemd override used as watchdog for docker daemon
rm_file "/etc/systemd/system/docker.service.d/override.conf"
if [[ -d "/etc/systemd/system/docker.service.d" ]]; then
  if [[ -z "$(ls -A /etc/systemd/system/docker.service.d 2>/dev/null || true)" ]]; then
    rm_dir "/etc/systemd/system/docker.service.d"
  fi
fi

# 5) Remove /usr/local/bin helpers
rm_file "/usr/local/bin/server-watchdog"
rm_file "/usr/local/bin/metrics-export"
rm_file "/usr/local/bin/server-maintenance"
rm_file "/usr/local/bin/kv1-deploy"

# 6) Remove configs written outside repo
rm_file "/etc/docker/daemon.json"
rm_file "/etc/systemd/journald.conf.d/kv1.conf"
rm_file "/etc/systemd/journald.conf.d/99-limits.conf"
rm_file "/etc/fail2ban/jail.local"
rm_dir  "/etc/kv1"

# logrotate snippets
rm_file "/etc/logrotate.d/server-watchdog"
rm_file "/etc/logrotate.d/apache2-homepage"
rm_file "/etc/logrotate.d/apache-homepage"
rm_file "/etc/logrotate.d/kv1-deploy"

# 7) Remove runtime state/locks/logs
rm_file "/var/lib/server-watchdog.state"
rm_file "/var/lib/server-watchdog.reboot"
rm_file "/var/lib/kv1-last-good"
rm_file "/var/lib/kv1-prev-commit"
rm_file "/var/lock/kv1-deploy.lock"

rm_file "/var/log/server-watchdog.log"
rm_file "/var/log/server-metrics.log"
rm_file "/var/log/server-maintenance.log"
rm_file "/var/log/kv1-deploy.log"
rm_file "/var/log/disk-alert.log"

# Remove rotated logs (best-effort)
doit "rm -f /var/log/server-watchdog.log.* /var/log/server-metrics.log.* /var/log/server-maintenance.log.* /var/log/kv1-deploy.log.* 2>/dev/null || true"

# 8) Reload systemd and restart core services (best-effort)
if has_cmd systemctl; then
  doit "systemctl daemon-reload || true"
  doit "systemctl reset-failed || true"
  doit "systemctl restart systemd-journald >/dev/null 2>&1 || true"
  doit "systemctl restart docker >/dev/null 2>&1 || true"
  doit "systemctl restart fail2ban >/dev/null 2>&1 || true"
fi

say "=== kv1 uninstall finished ==="
say "Next: apply repo patch, then run /home/homepage/admin-scripts/install.sh"
say "Tip: run with --force to actually delete (current run is $([[ "$FORCE" -eq 1 ]] && echo REAL || echo DRY-RUN))."
