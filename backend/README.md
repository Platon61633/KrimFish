# KrimFish — сервер (Express + PostgreSQL + Docker)

## Запуск (Windows)
1. Установите и запустите Docker Desktop.
2. В папке `backend`:
   ```
   copy .env.example .env
   docker compose up --build
   ```
3. Проверка: http://localhost:3000/health → `{"ok":true}`.

Поднимаются PostgreSQL 16 и API. Миграции и демо-каталог (4 товара, слоты, промокод `FISH10`) применяются сами.

## Полезное
- Логи: `docker compose logs -f api`
- Остановить: `docker compose down`; сбросить базу: `docker compose down -v`
- Adminer (просмотр БД): `docker compose --profile tools up` → http://localhost:8080
- Вход: `POST /auth/request-code {phone}` → при `SMS_MODE=console` код в ответе (`devCode`) и в логах; `SMS_FIXED_CODE` задаёт постоянный код.
- Админ: номера в `ADMIN_PHONES` (через запятую) получают роль ADMIN при входе.
- Тесты логики: `npm test` (нужен Node 20+, `npm install`). Сквозная проверка запущенного сервера: `npm run smoke`.

## API
| Метод | Путь | Доступ |
|---|---|---|
| GET | /health, /categories, /products, /products/:id, /slots | публично |
| POST | /cart/quote | публично |
| POST | /auth/request-code, /auth/verify, /auth/refresh, /auth/logout | публично |
| GET/PATCH/DELETE | /me | клиент |
| CRUD | /me/addresses; POST /me/devices | клиент |
| POST/GET | /orders; GET /orders/:number; POST /orders/:number/cancel | клиент |
| POST | /admin/uploads `{contentType}` → `uploadUrl`, `imageUrl` | ADMIN |
| * | /admin/orders (+transition, items/:itemId), products, categories, slots, promocodes, stats | ADMIN |

Деньги — в копейках, вес — в граммах. Слот заказа: `slotId` + `slotDate`. Повтор заказа защищён заголовком `Idempotency-Key`.

## Фото товаров (S3 / MinIO)
В compose поднимается MinIO (консоль http://localhost:9001, логин/пароль из `S3_ACCESS_KEY`/`S3_SECRET_KEY`), бакет создаётся сам и открыт на чтение.
Загрузка в три шага: `POST /admin/uploads {"contentType":"image/jpeg"}` → `PUT` файла на `uploadUrl` с заголовком `Content-Type` → сохранить `imageUrl` в товар (`POST/PATCH /admin/products`).
`S3_PUBLIC_URL` должен быть адресом, доступным с устройства (для эмулятора Android — `http://10.0.2.2:9000`). Ссылка действует 10 минут. Размер файла ссылкой не ограничивается — ограничивайте в приложении (сжатие до ~1 МБ).
В production замените на любой S3-совместимый сервис (Yandex Object Storage и т. п.): задайте `S3_PUBLIC_URL`, `S3_BUCKET`, ключи и уберите `minio` из compose.

## Production
Задайте `NODE_ENV=production`, `JWT_SECRET` (≥32 символов), `SMS_MODE` с реальным провайдером (сейчас реализован только console), `CORS_ORIGIN`, `SEED_DEMO=false`.

## Статус проверки
Логика (деньги, статусы, слоты, телефоны) покрыта тестами; схема и ограничения проверены на PostgreSQL 16. Express-слой и сборка Docker-образа у меня не запускались (npm-реестр был недоступен) — при ошибке пришлите вывод `docker compose logs`.
