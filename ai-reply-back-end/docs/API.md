# API

Базовый префикс — `/api/v1`. Все ответы — JSON, ошибки в одном конверте:

```json
{ "error": { "code": "DAILY_LIMIT_REACHED", "message": "Daily generation limit reached.",
             "details": { "daily_limit": 7, "used_today": 7, "resets_at": "2026-03-11T19:00:00Z" } } }
```

Клиент реагирует на `code`, а не на текст: `message` — только для отладки,
локализация живёт в приложении.

## Коды ошибок

`INVALID_REQUEST`, `INVALID_OTP`, `OTP_EXPIRED`, `UNAUTHORIZED`, `TOKEN_EXPIRED`,
`ACCOUNT_DISABLED`, `DAILY_LIMIT_REACHED`, `MONTHLY_LIMIT_REACHED`,
`SUBSCRIPTION_EXPIRED`, `RATE_LIMITED`, `AI_PROVIDER_UNAVAILABLE`, `AI_TIMEOUT`,
`AI_EMPTY_RESPONSE`, `PAYMENT_REQUIRED`, `NOT_FOUND`, `CONFLICT`, `INTERNAL_ERROR`.

## Аутентификация

### POST /api/v1/auth/request-otp
```json
{ "identifier": "+7 701 123 45 67", "locale": "kk" }
```
→ `{ "kind": "phone", "masked_identifier": "+77011***67", "channel": "stub", "expires_in": 300, "demo_mode": true }`

Телефон нормализуется в E.164. Поддержаны KZ, RU, UZ, KG, TJ, TM, AZ, GE, UA, BY, TR, AE
(`GET /api/v1/config` отдаёт список с примерами). Неподдержанная страна → `INVALID_REQUEST`.

### POST /api/v1/auth/verify-otp
```json
{ "identifier": "+77011234567", "code": "1111",
  "device": { "device_id": "", "platform": "ios", "app_version": "1.2.0",
              "os_version": "18.2", "locale": "kk", "timezone": "Asia/Almaty" } }
```
→ `access_token`, `refresh_token`, `expires_in`, `device_id`, `is_new_user`,
`user`, `profile`, `subscription`, `usage`.

`device_id` можно не присылать — сервер вернёт сгенерированный, его нужно
сохранить и присылать дальше.

### POST /api/v1/auth/refresh
`{ "refresh_token": "…" }` → новая пара. Старый refresh сразу отзывается;
повторное использование отзывает всю цепочку сессии (признак кражи токена).

### POST /api/v1/auth/logout
`{ "refresh_token": "…" }` → `{ "ok": true }` (идемпотентно).

## Профиль и лимиты

| Метод | Путь | Описание |
|---|---|---|
| GET | `/api/v1/me` | профиль + тариф + квота одним запросом |
| PATCH | `/api/v1/me` | частичное обновление профиля (все поля опциональны) |
| GET | `/api/v1/me/usage` | `daily_limit`, `used_today`, `remaining_today`, `resets_at` |
| GET | `/api/v1/me/subscription` | текущий тариф и статус |
| GET | `/api/v1/me/devices` | список устройств |
| POST | `/api/v1/devices` | регистрация устройства и push-токена |
| DELETE | `/api/v1/devices/{id}` | отозвать устройство |
| GET | `/api/v1/plans` | активные тарифы (публично) |
| GET | `/api/v1/config` | лимиты, языки, страны, режимы (публично) |

## Генерация ответа

### POST /api/v1/ai/reply
```json
{
  "source_text": "Здравствуйте! Сколько стоит доставка?",
  "instruction": "Ответь вежливо, скажи что уточню",
  "language": "ru",
  "template_id": "client",
  "template": { "name": "Клиент", "relationship": "client", "tone": "professional",
                "instructions": "", "reply_length": "short", "emoji_policy": "minimal",
                "working_hours_behaviour": "mention_when_relevant" },
  "business_context": { "enabled": true, "is_within_working_hours": false,
                        "current_local_time": "22:40", "next_working_period": "завтра 10:00" },
  "platform": "ios", "app_version": "1.2.0"
}
```
→
```json
{ "reply": "…", "detected_language": "ru",
  "usage": { "daily_limit": 7, "used_today": 1, "remaining_today": 6,
             "resets_at": "2026-03-11T19:00:00Z", "timezone": "Asia/Almaty" } }
```

Порядок на сервере: аутентификация → валидация размера → тариф и квота
(атомарный резерв) → промпт → провайдер → учёт токенов → ответ.
При ошибке провайдера резерв возвращается, счётчик не растёт.

Профиль берётся с сервера; блок `profile` в запросе допускается для клиентов,
которые держат его локально, и имеет приоритет.

## Платежи (demo)

| Метод | Путь |
|---|---|
| POST | `/api/v1/payments/checkout` → `{ "plan_id": "…" }` |
| POST | `/api/v1/payments/{id}/confirm` |

В `PAYMENT_MODE=demo` подтверждение сразу переводит пользователя на тариф.
Реальный эквайринг подключается одной реализацией `payments.Provider`.

## Совместимость со старыми сборками

Пока `LEGACY_API_ENABLED=true` работают эндпоинты прежнего бэкенда — байт в байт:

- `POST /v1/auth/register` — `{ "install_id": "…" }` → `{ "token", "expires_at" }`
- `POST /v1/reply/generate` — прежний формат, включая `keyboard_language`,
  `user_instruction` (Android) и `business_context`; ответ `{ "reply", "detected_language" }`;
  ошибки прежними кодами (`rate_limited`, `message_too_long` + `limit`/`actual`, …).

Отличие одно: запросы теперь учитываются в квоте и статистике. `install_id`
хранится только как HMAC — исходное значение в БД не попадает.

## Админ API

`/api/v1/admin/*` — cookie-сессия + заголовок `X-CSRF-Token` на любые изменения.
`session`, `dashboard`, `users`, `users/{id}`, `users/{id}/status|plan|reset-quota|revoke-sessions`,
`plans` (GET/POST/PATCH/archive), `audit`, `settings`, `settings/pricing`, `notifications`, `locale`.

Ни один admin-эндпоинт не отдаёт текст сообщений — такой функции нет.

## Служебное

`GET /healthz` — живость, `GET /readyz` — готовность (пинг БД).
