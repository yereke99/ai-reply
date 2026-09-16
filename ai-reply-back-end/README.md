# AI Reply — Backend

Go-бэкенд для AI Reply: REST API для iOS/Android, AI-шлюз (ключ провайдера живёт
только здесь), тарифы и квоты, админ-панель на Vue и публичный лендинг.
Языки интерфейса: **қазақша, русский, English, oʻzbekcha**.

```
Mobile (iOS / Android / клавиатура)
        │  Bearer access token
        ▼
   AI Reply Backend  ──►  Auth ──► Quota ──► AI Gateway ──► OpenAI
        │                                   (ключ только на сервере)
        ├── SQLite (только метаданные: тексты переписки не хранятся)
        ├── /admin  — Vue SPA: дашборд, пользователи, тарифы, аудит
        └── /       — лендинг (kk / ru / en / uz)
```

## Быстрый старт

```bash
cp .env.example .env
# заполнить OPENAI_API_KEY и три секрета: make secrets
make run           # http://localhost:8080
```

Или в Docker:

```bash
cp .env.example .env
docker compose up --build
```

При старте автоматически применяются миграции, создаются тарифы
(`free 7/день`, `standard 30/день`, `pro 50/день`) и администратор из
`ADMIN_EMAIL` / `ADMIN_PASSWORD`.

Проверка:

```bash
curl localhost:8080/healthz
curl localhost:8080/api/v1/plans
open http://localhost:8080/          # лендинг
open http://localhost:8080/admin     # админка
```

Демо-вход в приложении: любой номер поддерживаемой страны + код **1111**
(`AUTH_DEMO_MODE=true`). В production демо-режим не запускается — сервер
откажется стартовать.

## Структура

```
cmd/server/          точка входа: конфиг → БД → миграции → сервисы → HTTP
config/              загрузка и валидация окружения (без секретов в коде)
migrations/          SQL-схема, встроена в бинарник
internal/
  traits/            общие мелочи: UUID, часы, обрезка текста, маскирование
  phone/             E.164 для 12 стран (KZ, RU, UZ, KG, TJ, TM, AZ, GE, UA, BY, TR, AE)
  domain/            сущности и доменные ошибки
  database/          SQLite: WAL, один писатель, пул читателей, миграции
  repository/        SQL-слой (в т.ч. атомарный учёт квоты)
  auth/              OTP, JWT (15 мин), refresh с ротацией, PBKDF2 для админов
  users/             профиль и устройства
  plans/             каталог тарифов
  subscriptions/     подписки и расчёт текущего лимита (entitlement)
  ai/                промпт, клиент OpenAI Responses API, шлюз с учётом токенов
  payments/          интерфейс эквайринга + demo-адаптер
  notifications/     каркас APNs/FCM (честные заглушки, без фейкового «отправлено»)
  localization/      kk/ru/en/uz для веба и админки
  middleware/        request-id, логи, паника, CORS, заголовки, rate limit
  transport/
    httpx/           конверт ошибок, разбор JSON, IP клиента
    api/             /api/v1/* для мобильных + совместимость со старым /v1/*
    adminapi/        /api/v1/admin/* для SPA
    web/             лендинг (SSR + Vue-острова) и оболочка админки
  apptest/           сквозные тесты всего стека
```

## Что уже работает

- регистрация по телефону (12 стран) или e-mail, демо-OTP `1111`;
- access (15 мин) + refresh с ротацией и детектом переиспользования;
- профиль, устройства, тарифы, подписки, usage;
- AI-ответ через сервер: квота → провайдер → учёт токенов и стоимости;
- лимиты живут в БД: 30 → 50 в день меняется в админке без релиза приложения;
- админка: дашборд с графиками, пользователи, CRUD тарифов, аудит, настройки;
- лендинг на 4 языках с анимированной демонстрацией работы клавиатуры;
- полная совместимость со старым контрактом (`/v1/auth/register`, `/v1/reply/generate`),
  поэтому уже собранные iOS/Android-версии продолжают работать.

## Приватность (проверяется тестами)

| Что | Ответ |
|---|---|
| Ключ OpenAI в мобильном коде | НЕТ — только `.env` на сервере |
| Приложение ходит в OpenAI напрямую | НЕТ — только через бэкенд |
| Текст сообщения в БД | НЕТ — в схеме нет такой колонки |
| Текст виден администратору | НЕТ — в admin API нет таких полей |
| Текст в логах | НЕТ — логируются только метаданные |

Тест `TestMessageContentIsNeverPersisted` отправляет уникальную строку через
`/api/v1/ai/reply` и ищет её в файле БД, WAL и логах — любой найденный след
роняет сборку.

## Команды

```bash
make test        # все тесты
make test-race   # включая гонки на квоте
make vet
make build
make secrets     # сгенерировать JWT/legacy секреты
```

## Что осталось до продакшна

- реальный провайдер OTP (SMS или WhatsApp Business) — один интерфейс `auth.Sender`;
- реальный эквайринг — один интерфейс `payments.Provider`;
- APNs/FCM — интерфейс `notifications.Transport`;
- rate limiter в памяти → Redis при нескольких инстансах;
- `APP_ENV=production`, HTTPS, `ADMIN_SECURE_COOKIES=true`, `AUTH_DEMO_MODE=false`.

Подробности: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/API.md](docs/API.md), [docs/MOBILE_MIGRATION.md](docs/MOBILE_MIGRATION.md).
