#!/usr/bin/env bash
set -euo pipefail

# Bootstrap / update server for kv1.me project.
# Run as root from inside repo: /home/homepage/admin-scripts/install.sh
# chmod +x /home/homepage/admin-scripts/install.sh

APP_DIR="/home/homepage"
SCRIPTS_DIR="$APP_DIR/admin-scripts"

echo "=== kv1 bootstrap started ==="

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git wget bc logrotate fail2ban

# --- Docker: НЕ ставим docker-ce/containerd.io, чтобы не ловить конфликты на Debian ---
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found -> installing Debian docker.io"
  apt-get install -y --no-install-recommends docker.io docker-compose-plugin || \
  apt-get install -y --no-install-recommends docker.io docker-compose
fi

systemctl enable --now docker

# docker compose plugin check
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-plugin || true
fi

# --- docker daemon config (лог-лимиты и т.п.) ---
if [ -f "$SCRIPTS_DIR/config/docker-daemon.json" ]; then
  install -D -m 0644 "$SCRIPTS_DIR/config/docker-daemon.json" /etc/docker/daemon.json
  systemctl restart docker || true
fi

# --- docker systemd watchdog override ---
if [ -f "$SCRIPTS_DIR/systemd/docker.override.conf" ]; then
  mkdir -p /etc/systemd/system/docker.service.d
  install -m 0644 "$SCRIPTS_DIR/systemd/docker.override.conf" /etc/systemd/system/docker.service.d/override.conf
  systemctl daemon-reload
  systemctl restart docker || true
fi

# --- journald limits (drop-in) ---
if [ -f "$SCRIPTS_DIR/config/journald-limits.conf" ]; then
  mkdir -p /etc/systemd/journald.conf.d
  install -m 0644 "$SCRIPTS_DIR/config/journald-limits.conf" /etc/systemd/journald.conf.d/kv1.conf
  systemctl restart systemd-journald || true
fi

# --- fail2ban rules ---
if [ -f "$SCRIPTS_DIR/config/fail2ban-jail.local" ]; then
  install -m 0644 "$SCRIPTS_DIR/config/fail2ban-jail.local" /etc/fail2ban/jail.local
  systemctl enable --now fail2ban
  systemctl restart fail2ban || true
fi

# --- logrotate configs ---
if [ -f "$SCRIPTS_DIR/config/logrotate-server-watchdog.conf" ]; then
  install -m 0644 "$SCRIPTS_DIR/config/logrotate-server-watchdog.conf" /etc/logrotate.d/server-watchdog
fi

if [ -f "$SCRIPTS_DIR/config/logrotate-apache-homepage.conf" ]; then
  install -m 0644 "$SCRIPTS_DIR/config/logrotate-apache-homepage.conf" /etc/logrotate.d/apache2-homepage
fi

# logrotate status permissions (чтобы убрать warning world-readable)
if [ -f /var/lib/logrotate/status ]; then
  chmod 600 /var/lib/logrotate/status || true
fi

# --- kv1 compose autostart service ---
if [ -f "$SCRIPTS_DIR/systemd/kv1.service" ]; then
  install -m 0644 "$SCRIPTS_DIR/systemd/kv1.service" /etc/systemd/system/kv1.service
  systemctl daemon-reload
  systemctl enable --now kv1.service || true
fi

# --- watchdog ---
if [ -f "$SCRIPTS_DIR/systemd/server-watchdog.service" ] && [ -f "$SCRIPTS_DIR/systemd/server-watchdog.timer" ]; then
  install -m 0644 "$SCRIPTS_DIR/systemd/server-watchdog.service" /etc/systemd/system/server-watchdog.service
  install -m 0644 "$SCRIPTS_DIR/systemd/server-watchdog.timer" /etc/systemd/system/server-watchdog.timer
  systemctl daemon-reload
  systemctl enable --now server-watchdog.timer
fi

# --- maintenance ---
if [ -f "$SCRIPTS_DIR/systemd/server-maintenance.service" ] && [ -f "$SCRIPTS_DIR/systemd/server-maintenance.timer" ]; then
  install -m 0644 "$SCRIPTS_DIR/systemd/server-maintenance.service" /etc/systemd/system/server-maintenance.service
  install -m 0644 "$SCRIPTS_DIR/systemd/server-maintenance.timer" /etc/systemd/system/server-maintenance.timer
  systemctl daemon-reload
  systemctl enable --now server-maintenance.timer
fi

# --- cleanup old root-based scripts if exist ---
rm -f /root/server-watchdog.sh /root/metrics-export.sh /root/server-maintenance.sh 2>/dev/null || true

systemctl reset-failed || true
echo "=== kv1 bootstrap done ==="
