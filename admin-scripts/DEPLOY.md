# Deploy kv1.me on a fresh server (Debian/Ubuntu)

Эта папка содержит админ-скрипты, которые поднимают сервер с нуля и держат его в self-healing состоянии.

## Что делает install.sh

- ставит базовые утилиты (curl/git/wget/bc/logrotate/fail2ban)
- ставит Docker **только если Docker ещё не установлен** (на Debian использует `docker.io`, чтобы не ловить конфликты `containerd.io` vs `containerd`)
- включает docker service и проверяет наличие `docker compose`
- ограничивает docker-логи (`/etc/docker/daemon.json`)
- ограничивает systemd journal (drop-in в `/etc/systemd/journald.conf.d/`)
- настраивает fail2ban (jail `sshd`)
- включает self-healing watchdog (`server-watchdog.timer`, запуск каждые 2 минуты)
- включает daily maintenance (`server-maintenance.timer`)
- ставит systemd unit `kv1.service` для `docker compose up -d`
- включает авто-деплой из git (`kv1-deploy.timer`, каждые 5 минут)
- добавляет logrotate для логов watchdog/metrics/maintenance/deploy
- готовит файл `/etc/kv1/telegram.env` (опционально) для Telegram-уведомлений

## Поднятие с нуля

### 1) Зайти на сервер под root

### 2) Поставить git (если нет)

```bash
apt update && apt install -y git
```

### 3) Склонировать репозиторий в `/home/homepage`

```bash
cd /home
git clone https://github.com/SbWereWolf/homepage.git homepage
cd /home/homepage
```

### 4) Запустить bootstrap

```bash
chmod +x /home/homepage/admin-scripts/install.sh
/home/homepage/admin-scripts/install.sh
```

### 5) Поднять сайт

```bash
cd /home/homepage
docker compose up -d
```

### 6) Проверки

```bash
docker ps
systemctl status kv1
systemctl list-timers | egrep 'watchdog|maintenance|deploy'
tail -n 50 /var/log/server-watchdog.log
tail -n 50 /var/log/server-metrics.log
tail -n 50 /var/log/kv1-deploy.log
```

## Авто-деплой из git

Авто-деплой реализован скриптом `admin-scripts/deploy.sh` + таймером `kv1-deploy.timer`.

- каждые 5 минут делает `git fetch`
- если есть новые коммиты — делает `git reset --hard origin/master`
- затем `docker compose pull` и `docker compose up -d --remove-orphans`
- лог пишет в `/var/log/kv1-deploy.log`

Управление:

```bash
# включить (если не включено):
systemctl enable --now kv1-deploy.timer

# выключить:
systemctl disable --now kv1-deploy.timer

# запустить вручную один раз:
systemctl start kv1-deploy.service

# посмотреть лог:
tail -n 200 /var/log/kv1-deploy.log
```

## Метрики

Watchdog пишет метрики в `/var/log/server-metrics.log` и экспортирует JSON в:
`/home/homepage/www/metrics/data.json`

Страница графика лежит в `www/metrics/index.html` и будет доступна по:
`https://kv1.me/metrics/`

## Telegram-уведомления (Stage 2/3)

Watchdog умеет отправлять уведомления в Telegram при серьёзной эскалации:

- Stage 2: restart docker
- Stage 3: reboot (если нет cooldown)

### 1) Создать бота

- Открыть `@BotFather`
- `/newbot`
- Получить `TOKEN`

### 2) Узнать chat_id

Написать боту любое сообщение и посмотреть `getUpdates`:

- Открой: `https://api.telegram.org/bot<TOKEN>/getUpdates`
- Найди `chat.id`

### 3) Заполнить файл на сервере

Файл создаётся install.sh как шаблон (если его не было):

`/etc/kv1/telegram.env`

Пример содержимого:

```bash
TELEGRAM_TOKEN="123456:ABCDEF..."
TELEGRAM_CHAT="123456789"
```

Права:

```bash
chmod 600 /etc/kv1/telegram.env
```

Применить:

```bash
systemctl restart server-watchdog.timer
```

## Где лежат логи

- watchdog: `/var/log/server-watchdog.log`
- metrics: `/var/log/server-metrics.log`
- maintenance: `/var/log/server-maintenance.log`
- deploy: `/var/log/kv1-deploy.log`

Все эти логи ротируются через logrotate.
