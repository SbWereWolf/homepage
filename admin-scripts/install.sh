#!/usr/bin/env bash
set -euo pipefail

# Bootstrap / update server for kv1.me project.
# Run as root from inside repo: /home/homepage/admin-scripts/install.sh

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root." >&2
  exit 1
fi

BASE_DIR="/home/homepage"
SCRIPTS_DIR="$BASE_DIR/admin-scripts"
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local path="$1"
  if [ -f "$path" ]; then
    cp -a "$path" "${path}.bak-${STAMP}"
  fi
}

echo "=== kv1 bootstrap started ==="

# 1) Packages
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y docker.io docker-compose-plugin fail2ban curl wget logrotate

# 2) Docker daemon (limit container logs)
mkdir -p /etc/docker
backup_if_exists /etc/docker/daemon.json
cp "$SCRIPTS_DIR/config/docker-daemon.json" /etc/docker/daemon.json

systemctl enable docker
systemctl restart docker

# 3) journald limits (drop-in)
mkdir -p /etc/systemd/journald.conf.d
backup_if_exists /etc/systemd/journald.conf.d/99-limits.conf
cp "$SCRIPTS_DIR/config/journald-limits.conf" /etc/systemd/journald.conf.d/99-limits.conf
systemctl restart systemd-journald || true

# 4) Fail2ban sshd policy
backup_if_exists /etc/fail2ban/jail.local
cp "$SCRIPTS_DIR/config/fail2ban-jail.local" /etc/fail2ban/jail.local
systemctl enable fail2ban
systemctl restart fail2ban || true

# 5) logrotate for watchdog/metrics/maintenance logs (+ legacy apache logs)
cp "$SCRIPTS_DIR/config/logrotate-server-watchdog.conf" /etc/logrotate.d/server-watchdog
cp "$SCRIPTS_DIR/config/logrotate-apache-homepage.conf" /etc/logrotate.d/apache-homepage || true

# fix logrotate status perms warning
if [ -f /var/lib/logrotate/status ]; then
  chmod 600 /var/lib/logrotate/status || true
fi

# 6) Docker watchdog (systemd override)
mkdir -p /etc/systemd/system/docker.service.d
backup_if_exists /etc/systemd/system/docker.service.d/override.conf
cp "$SCRIPTS_DIR/systemd/docker.override.conf" /etc/systemd/system/docker.service.d/override.conf
systemctl daemon-reload
systemctl restart docker || true

# 7) Install project systemd units
for f in server-watchdog.service server-watchdog.timer server-maintenance.service server-maintenance.timer kv1.service; do
  backup_if_exists "/etc/systemd/system/$f"
  cp "$SCRIPTS_DIR/systemd/$f" "/etc/systemd/system/$f"
done

systemctl daemon-reload

# Disable any legacy root-based units if present (best-effort)
# (just in case someone created separate service names)
systemctl stop server-watchdog.timer >/dev/null 2>&1 || true
systemctl disable server-watchdog.timer >/dev/null 2>&1 || true
systemctl stop server-maintenance.timer >/dev/null 2>&1 || true
systemctl disable server-maintenance.timer >/dev/null 2>&1 || true

# Enable our timers/services
systemctl enable --now server-watchdog.timer
systemctl enable --now server-maintenance.timer
systemctl enable --now kv1.service

# 8) Ensure metrics folder exists
mkdir -p "$BASE_DIR/www/metrics"
# create initial data.json (optional)
"$SCRIPTS_DIR/metrics-export.sh" >/dev/null 2>&1 || true

echo "=== kv1 bootstrap done ==="
echo "Check:"
echo "  systemctl list-timers | egrep 'watchdog|maintenance'"
echo "  systemctl status kv1"
echo "  docker ps"
