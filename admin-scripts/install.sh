#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/homepage"
SCRIPTS_DIR="$APP_DIR/admin-scripts"
STAMP="$(date +%Y%m%d-%H%M%S)"

backup_if_exists() {
  local p="$1"
  if [ -f "$p" ]; then
    cp -a "$p" "${p}.bak-${STAMP}"
  fi
}

echo "=== kv1 bootstrap started ==="
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   ca-certificates curl git wget bc logrotate fail2ban

# Docker: не ставим docker-ce/containerd.io (конфликтует с Debian containerd/runc)
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found -> installing Debian docker.io"
  apt-get install -y --no-install-recommends docker.io docker-compose-plugin ||   apt-get install -y --no-install-recommends docker.io docker-compose
fi

systemctl enable --now docker

# docker compose plugin check
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-plugin || true
fi

# --- Install scripts into /usr/local/bin (avoids /home noexec/permissions issues) ---
install -m 0755 "$SCRIPTS_DIR/server-watchdog.sh" /usr/local/bin/server-watchdog
install -m 0755 "$SCRIPTS_DIR/metrics-export.sh" /usr/local/bin/metrics-export
[ -f "$SCRIPTS_DIR/server-maintenance.sh" ] && install -m 0755 "$SCRIPTS_DIR/server-maintenance.sh" /usr/local/bin/server-maintenance || true
[ -f "$SCRIPTS_DIR/deploy.sh" ] && install -m 0755 "$SCRIPTS_DIR/deploy.sh" /usr/local/bin/kv1-deploy || true

# --- docker daemon config ---
if [ -f "$SCRIPTS_DIR/config/docker-daemon.json" ]; then
  mkdir -p /etc/docker
  backup_if_exists /etc/docker/daemon.json
  install -m 0644 "$SCRIPTS_DIR/config/docker-daemon.json" /etc/docker/daemon.json
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
[ -f "$SCRIPTS_DIR/config/logrotate-server-watchdog.conf" ] && install -m 0644 "$SCRIPTS_DIR/config/logrotate-server-watchdog.conf" /etc/logrotate.d/server-watchdog || true
[ -f "$SCRIPTS_DIR/config/logrotate-kv1-deploy.conf" ] && install -m 0644 "$SCRIPTS_DIR/config/logrotate-kv1-deploy.conf" /etc/logrotate.d/kv1-deploy || true

# fix logrotate status perms warning
[ -f /var/lib/logrotate/status ] && chmod 600 /var/lib/logrotate/status || true

# --- Telegram env file (optional) ---
mkdir -p /etc/kv1
if [ ! -f /etc/kv1/telegram.env ] && [ -f "$SCRIPTS_DIR/config/telegram.env.example" ]; then
  install -m 0640 "$SCRIPTS_DIR/config/telegram.env.example" /etc/kv1/telegram.env
  echo "NOTE: edit /etc/kv1/telegram.env to enable Telegram alerts"
fi

# --- systemd units ---
for unit in kv1.service server-watchdog.service server-watchdog.timer server-maintenance.service server-maintenance.timer kv1-deploy.service kv1-deploy.timer; do
  if [ -f "$SCRIPTS_DIR/systemd/$unit" ]; then
    install -m 0644 "$SCRIPTS_DIR/systemd/$unit" "/etc/systemd/system/$unit"
  fi
done

systemctl daemon-reload

# enable core units (ignore missing)
systemctl enable --now kv1.service || true
systemctl enable --now server-watchdog.timer || true
systemctl enable --now server-maintenance.timer || true
systemctl enable --now kv1-deploy.timer || true

# cleanup old root-based scripts if exist
rm -f /root/server-watchdog.sh /root/metrics-export.sh /root/server-maintenance.sh 2>/dev/null || true

systemctl reset-failed || true
echo "=== kv1 bootstrap done ==="
