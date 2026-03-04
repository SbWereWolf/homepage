#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/homepage"
SCRIPTS_DIR="$APP_DIR/admin-scripts"

echo "=== kv1 bootstrap started ==="

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ca-certificates curl git wget bc logrotate fail2ban

# Docker: don't install docker-ce/containerd.io on Debian; use docker.io if missing
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found -> installing Debian docker.io"
  apt-get install -y --no-install-recommends docker.io docker-compose-plugin ||   apt-get install -y --no-install-recommends docker.io docker-compose
fi

systemctl enable --now docker

if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-plugin || true
fi

chmod +x   "$SCRIPTS_DIR/install.sh"   "$SCRIPTS_DIR/deploy.sh"   "$SCRIPTS_DIR/server-watchdog.sh"   "$SCRIPTS_DIR/server-maintenance.sh"   "$SCRIPTS_DIR/metrics-export.sh" 2>/dev/null || true

# logrotate for deploy log
if [ -f "$SCRIPTS_DIR/config/logrotate-kv1-deploy.conf" ]; then
  install -m 0644 "$SCRIPTS_DIR/config/logrotate-kv1-deploy.conf" /etc/logrotate.d/kv1-deploy
fi

# Telegram env template (optional)
mkdir -p /etc/kv1
if [ ! -f /etc/kv1/telegram.env ] && [ -f "$SCRIPTS_DIR/config/telegram.env.example" ]; then
  install -m 0640 "$SCRIPTS_DIR/config/telegram.env.example" /etc/kv1/telegram.env
  echo "NOTE: edit /etc/kv1/telegram.env to enable Telegram alerts"
fi

# install/update watchdog unit so it reads /etc/kv1/telegram.env
if [ -f "$SCRIPTS_DIR/systemd/server-watchdog.service" ]; then
  install -m 0644 "$SCRIPTS_DIR/systemd/server-watchdog.service" /etc/systemd/system/server-watchdog.service
  systemctl daemon-reload
  systemctl restart server-watchdog.timer 2>/dev/null || true
fi

echo "=== kv1 bootstrap done ==="
