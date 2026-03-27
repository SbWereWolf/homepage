#!/bin/bash
set -euo pipefail

# chmod +x /home/homepage/admin-scripts/deploy.sh

# 2) Добавляем авто-деплой из git (polling, без webhook)
# Сделаем деплой, который:
# берёт изменения из origin/master
# если есть новые коммиты → делает docker compose pull + up -d
# пишет лог в /var/log/kv1-deploy.log
# защищён от параллельных запусков (flock)

# 2.1 Скрипт деплоя

APP_DIR="/home/homepage"
BRANCH="${BRANCH:-master}"
REMOTE="${REMOTE:-origin}"
LOG="/var/log/kv1-deploy.log"
LOCK="/var/lock/kv1-deploy.lock"

mkdir -p /var/lock /var/log /var/lib

exec 9>"$LOCK"
if ! flock -n 9; then
  exit 0
fi

{
  echo "=== $(date) deploy start ==="

  # на некоторых системах git ругается на safe.directory если владелец не совпадает
  git config --global --add safe.directory "$APP_DIR" >/dev/null 2>&1 || true

  cd "$APP_DIR"

  git fetch "$REMOTE" "$BRANCH"

  LOCAL="$(git rev-parse HEAD)"
  REMOTE_HASH="$(git rev-parse "$REMOTE/$BRANCH")"

  if [ "$LOCAL" = "$REMOTE_HASH" ]; then
    echo "$(date) no changes ($LOCAL)"
    exit 0
  fi

  echo "$(date) updating $LOCAL -> $REMOTE_HASH"
  echo "$LOCAL" > /var/lib/kv1-prev-commit || true

  git reset --hard "$REMOTE/$BRANCH"

  docker compose pull
  docker compose up -d --remove-orphans

  echo "$REMOTE_HASH" > /var/lib/kv1-last-good || true
  echo "=== $(date) deploy success ($REMOTE_HASH) ==="
} >> "$LOG" 2>&1
