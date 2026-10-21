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
- Вход: `POST /auth/register {email, password, name?}`, `/auth/login {email, password}`, `/auth/google {idToken}`, `/auth/vk {code, codeVerifier, deviceId, state, redirectUri}`. Пароли хранятся как scrypt-хэши, после 5 неверных попыток вход на email блокируется на 5 минут. `GET /auth/providers` говорит приложению, какие кнопки показывать.
- Админ: задайте в `.env` `ADMIN_EMAILS` и `ADMIN_PASSWORD`: при старте сервер создаёт этих администраторов с таким паролем. Роль ADMIN можно получить только так или через Google (если Google подтвердил этот email). Обычная регистрация на такой адрес закрыта, а вход через VK роль ADMIN не выдаёт.
- Подтверждение почты: `POST /auth/register` не создаёт аккаунт, а отправляет 6-значный код (действует 10 минут, 5 попыток, повторная отправка раз в минуту, не более 5 писем в час). Аккаунт создаётся в `POST /auth/verify-email {email, code}`, который сразу возвращает токены. Вход с неподтверждённой почтой отвечает 403 с `details.code = EMAIL_NOT_VERIFIED`, `POST /auth/resend-code` присылает код заново. В `MAIL_MODE=console` (по умолчанию вне production) письмо не уходит, а код пишется в лог и возвращается в ответе как `devCode`; для боевого режима задайте `MAIL_MODE=smtp` и `SMTP_*` (см. `.env.example`). Google-вход почту не проверяет: её уже подтвердил Google.
- Google: в Google Cloud создайте OAuth-клиент «Веб-приложение» и пропишите его ID в `GOOGLE_CLIENT_ID`. Для Android нужен ещё клиент «Android» (имя пакета + SHA-1 ключа подписи); приложение само берёт Web client ID с сервера. Токен проверяется на сервере по ключам Google, без внешних библиотек.
- VK ID: создайте приложение в кабинете VK ID, пропишите `VK_CLIENT_ID` (и в `mobile/android/gradle.properties`). Обмен кода написан по документации VK ID по памяти и не проверялся с настоящими ключами: сверьте адреса и поля в `src/lib/vk.js` с документацией.
- Телефон больше не логин: его вводят при оформлении заказа (для курьера), он сохраняется в профиле, но не подтверждается.
- Тесты логики: `npm test` (нужен Node 20+, `npm install`). Сквозная проверка запущенного сервера: `npm run smoke`.

## API
| Метод | Путь | Доступ |
|---|---|---|
| GET | /health, /categories, /products, /products/:id, /slots | публично |
| POST | /cart/quote | публично |
| POST/GET | /auth/register, /auth/login, /auth/google, /auth/vk, /auth/refresh, /auth/logout; GET /auth/providers | публично |
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
Задайте `NODE_ENV=production`, `JWT_SECRET` (≥32 символов), `ADMIN_EMAILS` и `ADMIN_PASSWORD` (≥12 символов), `CORS_ORIGIN`, `SEED_DEMO=false`.

## Статус проверки
Логика (деньги, статусы, слоты, телефоны) покрыта тестами; схема и ограничения проверены на PostgreSQL 16. Express-слой и сборка Docker-образа у меня не запускались (npm-реестр был недоступен) — при ошибке пришлите вывод `docker compose logs`.
