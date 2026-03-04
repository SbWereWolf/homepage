# Deploy kv1.me on a fresh server (Debian/Ubuntu)

Эта папка содержит админ-скрипты, которые **поднимают сервер с нуля** и держат его в self-healing состоянии.

## Что делает install.sh

- ставит Docker +docker compose plugin
- ограничивает docker-логи (`/etc/docker/daemon.json`)
- ограничивает systemd journal 
  (drop-in в `/etc/systemd/journald.conf.d/`)
- настраивает fail2ban (jail `sshd`)
- включает self-healing watchdog (systemd timer каждые 2 минуты)
- включает daily maintenance (systemd timer)
- ставит systemd unit `kv1.service` для `docker compose up -d`
- добавляет logrotate для логов watchdog/metrics/maintenance

## Поднятие с нуля

### 1. Зайти на сервер под root.

### 2. Поставить git (если нет):

```bash
apt update && apt install -y git
```

### 3. Склонировать репозиторий в `/home/homepage`:

```bash
cd /home
git clone https://github.com/SbWereWolf/homepage.git homepage
cd /home/homepage
```

### 4. Запустить bootstrap:

```bash
chmod +x /home/homepage/admin-scripts/install.sh
/home/homepage/admin-scripts/install.sh
```

### 5. Поднять сайт:

```bash
cd /home/homepage
docker compose up -d
```

### 6. Проверки:

```bash
docker ps
systemctl status kv1
systemctl list-timers | egrep 'watchdog|maintenance'
tail -n 50 /var/log/server-watchdog.log
tail -n 50 /var/log/server-metrics.log
```

## Метрики

Watchdog пишет метрики в `/var/log/server-metrics.log` и экспортирует
JSON в: `/home/homepage/www/metrics/data.json`

Страница графика лежит в `www/metrics/index.html` и будет доступна по:
`https://kv1.me/metrics/`
