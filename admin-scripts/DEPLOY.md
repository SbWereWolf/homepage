# Deploy kv1.me on a fresh server (Debian/Ubuntu)

Эта папка содержит админ-скрипты, которые **поднимают сервер с нуля** и держат его в self-healing состоянии.

## Что делает install.sh

- ставит Docker + docker compose plugin
- ограничивает docker-логи (`/etc/docker/daemon.json`)
- ограничивает systemd journal (drop-in в `/etc/systemd/journald.conf.d/`)
- настраивает fail2ban (jail `sshd`)
- включает self-healing watchdog (systemd timer каждые 2 минуты)
- включает daily maintenance (systemd timer)
- ставит systemd unit `kv1.service` для `docker compose up -d`
- добавляет logrotate для логов watchdog/metrics/maintenance

## Поднятие с нуля

1. Зайти на сервер под root.

2. Поставить git (если нет):

```bash
apt update && apt install -y git
```

1. Склонировать репозиторий в `/home/homepage`:

```bash
cd /home
git clone <YOUR_REPO_URL> homepage
cd /home/homepage
```

1. Запустить bootstrap:

```bash
chmod +x /home/homepage/admin-scripts/install.sh
/home/homepage/admin-scripts/install.sh
```

1. Поднять сайт:

```bash
cd /home/homepage
docker compose up -d
```

1. Проверки:

```bash
docker ps
systemctl status kv1
systemctl list-timers | egrep 'watchdog|maintenance'
tail -n 50 /var/log/server-watchdog.log
tail -n 50 /var/log/server-metrics.log
```

## Миграция со старой схемы (/root)

Если ранее скрипты лежали в `/root` и systemd units указывали на них:

- удалить старые файлы:
  - `/root/server-watchdog.sh`
  - `/root/metrics-export.sh`
  - `/root/server-maintenance.sh` (если был)
- убедиться, что активны таймеры из `/home/homepage/admin-scripts`:

```bash
systemctl list-timers | grep watchdog
systemctl cat server-watchdog.service
```

## Метрики

Watchdog пишет метрики в `/var/log/server-metrics.log` и экспортирует JSON в:
`/home/homepage/www/metrics/data.json`

Страница графика лежит в `www/metrics/index.html` и будет доступна по:
`https://kv1.me/metrics/`
