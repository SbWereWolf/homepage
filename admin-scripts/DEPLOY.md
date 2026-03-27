<!-- PATCH: append this section to your existing DEPLOY.md -->

## Полная очистка перед переустановкой

В репозитории есть скрипт `admin-scripts/uninstall.sh`.

- По умолчанию **DRY-RUN** (ничего не удаляет, только печатает действия):
```bash
sudo /home/homepage/admin-scripts/uninstall.sh
```

- Реальная очистка (удаляет всё, что было настроено *вне репозитория*: systemd units, /usr/local/bin, /etc/kv1, лог-файлы, state-файлы и т.д.):
```bash
sudo /home/homepage/admin-scripts/uninstall.sh --force
```

Бэкапы удаляемых конфигов сохраняются в `/root/kv1-uninstall-backup-<timestamp>/`.
