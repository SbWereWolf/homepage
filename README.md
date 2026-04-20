# Домашняя страничка Коли Вольхина aka 5-Sb WereWolf

## DEPLOY

[DEPLOY](admin-scripts/DEPLOY.md)

## Структура проектов

На одном домене публикуются два независимых статических сайта:
- `https://kv1.me/` — бизнес-визитка;
- `https://kv1.me/home/` — личный сайт.

Исходники и опубликованные файлы разведены по отдельным директориям:

```text
business-card/
  src/
home/
  src/
www/
  business-card/
  home/
  metrics/
```

`www/metrics` — служебная директория для мониторинга, она не относится
ни к бизнес-визитке, ни к личному сайту.

## Настроить окружение разработки личного сайта

Разработка сайта sb-werewolf-2025 ведётся с помощью Vite
(ради горячей перезагрузки). Исходники лежат в директории `home/src`.

Соответственно:

```shell
cd .\home\src
npm i
```

Для того чтобы директория `www/home/storage` была доступна из
`home/src`, надо сделать символьную ссылку (команда для win10):

```shell
cd .\home\src
mklink /D "storage" "..\..\www\home\storage"
```

### Сборка sb-werewolf-2025

Если в директории с исходниками делать `npm run build` 
(в директории разработки - в `home/src`),
то Vite вообще всё заливает в директорию `home/src/dist/assets`,
то есть всё что лежит в `home/src/storage` перемещается туда.

При том что `home/src/storage` это символьная ссылка на
`www/home/storage`,
получается в `home/src/dist/assets` лежит всё тоже самое,
что в `www/home/storage`, это не нужное дублирование,
потому что с этими же файлами работает старый дизайн 
из директории `www/home/verywell`.

Если нам от Vite была нужна только горячая перезагрузка,
то `npm run build` использовать не будем.

Будем использовать `tailwindcss` для генерации CSS из исходников.

Для этого создадим директорию для результата генерации и
выполним генерацию:

```shell
mkdir .\home\src\sb-werewolf-2025\src\out
npx @tailwindcss/cli -i ./home/src/sb-werewolf-2025/src/sb-werewolf-2025.css -o ./home/src/sb-werewolf-2025/src/out/sb-werewolf-2025.css
```

### Публикация sb-werewolf-2025

После сборки CSS файла:
- удаляем всё в `www/home/sb-werewolf-2025`,
- копируем всё из `home/src/sb-werewolf-2025` в
`www/home/sb-werewolf-2025`,
- удаляем исходник
`www/home/sb-werewolf-2025/src/sb-werewolf-2025.css`
- копируем сгенерированный `sb-werewolf-2025.css` из
 `www/home/sb-werewolf-2025/src/out/` в
`www/home/sb-werewolf-2025/src/` (на уровень выше)
- готово

Можно заливать на хостинг.
