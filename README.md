# Домашняя страничка Коли Вольхина aka 5-Sb WereWolf

## DEPLOY

[DEPLOY](admin-scripts/DEPLOY.md)

## Настроить окружение разработки

Разработка сайта sb-werewolf-2025 ведётся с помощью Vite
(ради горячей перезагрузки). Исходники лежат в директории `src`.

Соответственно:
```shell
cd .\src
npm i
```

Для того что бы директория `www/storage` была доступна из `src`,
надо сделать символьную ссылку (команда для win10):
```shell
cd .\src
mklink /D "storage" "..\www\storage"
```

### Сборка sb-werewolf-2025
Если в директории с исходниками делать `npm run build` 
(в директории разработки - в `src`),
то Vite вообще всё заливает в директорию `src/dist/assets`,
то есть всё что лежит в `src/storage` перемещается туда.

При том что `src/storage` это символьная ссылка на `www/storage`,
получается в `src/dist/assets` лежит всё тоже самое,
что в `www/storage`, это не нужное дублирование, 
потому что с этими же файлами работает старый дизайн 
из директории `www/verywell`.

Если нам от Vite была нужна только горячая перезагрузка,
то `npm run build` использовать не будем.

Будем использовать  `tailwindcss` для генерации CSS из исходников.

Для этого создадим директорию для результата генерации и
выполним генерацию:
```shell
mkdir .\src\sb-werewolf-2025\src\out
npx @tailwindcss/cli -i ./src/sb-werewolf-2025/src/sb-werewolf-2025.css -o ./src/sb-werewolf-2025/src/out/sb-werewolf-2025.css
```

### Публикация sb-werewolf-2025
После сборки CSS файла:
- удаляем всё в `www/sb-werewolf-2025`, 
- копируем всё из `src/sb-werewolf-2025` в `www/sb-werewolf-2025`,
- удаляем исходник `www/sb-werewolf-2025/src/sb-werewolf-2025.css`
- копируем сгенерированный `sb-werewolf-2025.css` из
 `www/sb-werewolf-2025/src/out/` в
`www/sb-werewolf-2025/src/` (на уровень выше)
- готово

Можно заливать на хостинг.