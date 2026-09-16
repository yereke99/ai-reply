-- 0001_init: негізгі схема. Барлық уақыт өрістері UTC (unix миллисекунд).
-- PRIVACY: бұл схемада хабарлама мәтіні сақталатын бірде-бір баған жоқ.

CREATE TABLE users (
    id            TEXT PRIMARY KEY,
    phone         TEXT UNIQUE,
    email         TEXT UNIQUE,
    status        TEXT NOT NULL DEFAULT 'active',      -- active | disabled
    locale        TEXT NOT NULL DEFAULT 'en',          -- kk | ru | en | uz
    timezone      TEXT NOT NULL DEFAULT '',
    platform      TEXT NOT NULL DEFAULT '',            -- ios | android | web | legacy
    app_version   TEXT NOT NULL DEFAULT '',
    os_version    TEXT NOT NULL DEFAULT '',
    kind          TEXT NOT NULL DEFAULT 'account',     -- account | legacy_install
    legacy_client TEXT UNIQUE,                         -- HMAC(install_id), тек ескі клиенттер үшін
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL,
    last_active_at INTEGER,
    deleted_at    INTEGER,
    CHECK (phone IS NOT NULL OR email IS NOT NULL OR legacy_client IS NOT NULL)
);
CREATE INDEX idx_users_created_at ON users (created_at);
CREATE INDEX idx_users_last_active ON users (last_active_at);
CREATE INDEX idx_users_platform ON users (platform);

CREATE TABLE user_profiles (
    user_id        TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    display_name   TEXT NOT NULL DEFAULT '',
    role           TEXT NOT NULL DEFAULT '',
    description    TEXT NOT NULL DEFAULT '',
    preferred_tone TEXT NOT NULL DEFAULT 'natural',
    business_offering TEXT NOT NULL DEFAULT '',
    business_summary  TEXT NOT NULL DEFAULT '',
    business_rules    TEXT NOT NULL DEFAULT '[]',      -- JSON array
    onboarding_completed INTEGER NOT NULL DEFAULT 0,
    updated_at     INTEGER NOT NULL
);

CREATE TABLE auth_identities (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind        TEXT NOT NULL,                          -- phone | email
    value       TEXT NOT NULL,
    country     TEXT NOT NULL DEFAULT '',               -- ISO-3166 alpha-2, телефон үшін
    verified_at INTEGER,
    created_at  INTEGER NOT NULL,
    UNIQUE (kind, value)
);
CREATE INDEX idx_auth_identities_user ON auth_identities (user_id);

-- OTP кодтары хэш түрінде ғана сақталады.
CREATE TABLE otp_codes (
    id            TEXT PRIMARY KEY,
    identity_kind TEXT NOT NULL,
    identity_value TEXT NOT NULL,
    channel       TEXT NOT NULL DEFAULT 'stub',        -- stub | sms | whatsapp | email
    code_hash     TEXT NOT NULL,
    attempts      INTEGER NOT NULL DEFAULT 0,
    max_attempts  INTEGER NOT NULL DEFAULT 5,
    expires_at    INTEGER NOT NULL,
    consumed_at   INTEGER,
    created_at    INTEGER NOT NULL
);
CREATE INDEX idx_otp_lookup ON otp_codes (identity_kind, identity_value, consumed_at, expires_at);

CREATE TABLE devices (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    platform     TEXT NOT NULL DEFAULT '',
    app_version  TEXT NOT NULL DEFAULT '',
    os_version   TEXT NOT NULL DEFAULT '',
    model        TEXT NOT NULL DEFAULT '',
    locale       TEXT NOT NULL DEFAULT '',
    push_token   TEXT,
    push_enabled INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    revoked_at   INTEGER
);
CREATE INDEX idx_devices_user ON devices (user_id);
CREATE UNIQUE INDEX idx_devices_push ON devices (push_token) WHERE push_token IS NOT NULL;

-- Refresh токендер тек SHA-256 хэшімен сақталады (ашық мәні ешқашан жазылмайды).
CREATE TABLE refresh_tokens (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_id    TEXT REFERENCES devices (id) ON DELETE SET NULL,
    family_id    TEXT NOT NULL,
    token_hash   TEXT NOT NULL UNIQUE,
    issued_at    INTEGER NOT NULL,
    expires_at   INTEGER NOT NULL,
    revoked_at   INTEGER,
    revoked_reason TEXT NOT NULL DEFAULT '',
    replaced_by  TEXT,
    user_agent   TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_refresh_user ON refresh_tokens (user_id);
CREATE INDEX idx_refresh_family ON refresh_tokens (family_id);

CREATE TABLE plans (
    id                   TEXT PRIMARY KEY,
    code                 TEXT NOT NULL UNIQUE,
    name_kk              TEXT NOT NULL,
    name_ru              TEXT NOT NULL,
    name_en              TEXT NOT NULL,
    name_uz              TEXT NOT NULL DEFAULT '',
    description_kk       TEXT NOT NULL DEFAULT '',
    description_ru       TEXT NOT NULL DEFAULT '',
    description_en       TEXT NOT NULL DEFAULT '',
    description_uz       TEXT NOT NULL DEFAULT '',
    price                INTEGER NOT NULL DEFAULT 0,    -- ең кіші бірлікте (тиын)
    currency             TEXT NOT NULL DEFAULT 'KZT',
    daily_message_limit  INTEGER NOT NULL DEFAULT 7,
    monthly_message_limit INTEGER NOT NULL DEFAULT 0,   -- 0 = шектеусіз
    period_days          INTEGER NOT NULL DEFAULT 30,
    is_free              INTEGER NOT NULL DEFAULT 0,
    is_active            INTEGER NOT NULL DEFAULT 1,
    sort_order           INTEGER NOT NULL DEFAULT 0,
    created_at           INTEGER NOT NULL,
    updated_at           INTEGER NOT NULL,
    archived_at          INTEGER
);

CREATE TABLE subscriptions (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    plan_id    TEXT NOT NULL REFERENCES plans (id),
    status     TEXT NOT NULL,                           -- trial|active|expired|cancelled|payment_pending
    source     TEXT NOT NULL DEFAULT 'system',          -- system|admin|payment
    started_at INTEGER NOT NULL,
    expires_at INTEGER,
    cancelled_at INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE INDEX idx_subscriptions_user ON subscriptions (user_id, status);

-- Күндік квота. Бір жолға бір атомарлы UPDATE — параллель сұраныстар лимитті аттап өте алмайды.
CREATE TABLE usage_daily (
    user_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    usage_date  TEXT NOT NULL,                          -- YYYY-MM-DD, сервер уақыт белдеуінде
    used        INTEGER NOT NULL DEFAULT 0,
    input_tokens  INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_micros   INTEGER NOT NULL DEFAULT 0,
    updated_at  INTEGER NOT NULL,
    PRIMARY KEY (user_id, usage_date)
);
CREATE INDEX idx_usage_daily_date ON usage_daily (usage_date);

CREATE TABLE usage_monthly (
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    usage_month  TEXT NOT NULL,                         -- YYYY-MM
    used         INTEGER NOT NULL DEFAULT 0,
    input_tokens  INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    cost_micros   INTEGER NOT NULL DEFAULT 0,
    updated_at   INTEGER NOT NULL,
    PRIMARY KEY (user_id, usage_month)
);

-- Тек метадеректер: мәтін де, жауап та жоқ.
CREATE TABLE ai_usage_events (
    id             TEXT PRIMARY KEY,
    user_id        TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    device_id      TEXT,
    plan_id        TEXT,
    model          TEXT NOT NULL DEFAULT '',
    status         TEXT NOT NULL,                       -- success | error
    error_code     TEXT NOT NULL DEFAULT '',
    input_tokens   INTEGER NOT NULL DEFAULT 0,
    output_tokens  INTEGER NOT NULL DEFAULT 0,
    total_tokens   INTEGER NOT NULL DEFAULT 0,
    cost_micros    INTEGER NOT NULL DEFAULT 0,
    latency_ms     INTEGER NOT NULL DEFAULT 0,
    provider_ms    INTEGER NOT NULL DEFAULT 0,
    platform       TEXT NOT NULL DEFAULT '',
    app_version    TEXT NOT NULL DEFAULT '',
    language       TEXT NOT NULL DEFAULT '',
    source_chars   INTEGER NOT NULL DEFAULT 0,          -- ұзындығы ғана, мәтіні емес
    created_at     INTEGER NOT NULL
);
CREATE INDEX idx_ai_events_created ON ai_usage_events (created_at);
CREATE INDEX idx_ai_events_user ON ai_usage_events (user_id, created_at);

CREATE TABLE model_pricing (
    id                      TEXT PRIMARY KEY,
    model                   TEXT NOT NULL,
    input_price_per_1m      REAL NOT NULL,
    output_price_per_1m     REAL NOT NULL,
    currency                TEXT NOT NULL DEFAULT 'USD',
    effective_from          INTEGER NOT NULL,
    created_at              INTEGER NOT NULL
);
CREATE INDEX idx_pricing_model ON model_pricing (model, effective_from);

CREATE TABLE payments (
    id            TEXT PRIMARY KEY,
    user_id       TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    plan_id       TEXT NOT NULL REFERENCES plans (id),
    provider      TEXT NOT NULL,                        -- demo | <acquiring>
    provider_ref  TEXT NOT NULL DEFAULT '',
    amount        INTEGER NOT NULL,
    currency      TEXT NOT NULL,
    status        TEXT NOT NULL,                        -- created|pending|succeeded|failed|refunded
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL
);
CREATE INDEX idx_payments_user ON payments (user_id, created_at);

CREATE TABLE admin_users (
    id            TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    name          TEXT NOT NULL DEFAULT '',
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'admin',        -- admin | viewer
    locale        TEXT NOT NULL DEFAULT 'ru',
    is_active     INTEGER NOT NULL DEFAULT 1,
    created_at    INTEGER NOT NULL,
    updated_at    INTEGER NOT NULL,
    last_login_at INTEGER
);

CREATE TABLE admin_sessions (
    id          TEXT PRIMARY KEY,
    admin_id    TEXT NOT NULL REFERENCES admin_users (id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    csrf_token  TEXT NOT NULL,
    created_at  INTEGER NOT NULL,
    expires_at  INTEGER NOT NULL,
    revoked_at  INTEGER,
    ip          TEXT NOT NULL DEFAULT '',
    user_agent  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_admin_sessions_admin ON admin_sessions (admin_id);

CREATE TABLE admin_audit_logs (
    id          TEXT PRIMARY KEY,
    admin_id    TEXT NOT NULL,
    admin_email TEXT NOT NULL DEFAULT '',
    action      TEXT NOT NULL,
    entity_type TEXT NOT NULL DEFAULT '',
    entity_id   TEXT NOT NULL DEFAULT '',
    metadata    TEXT NOT NULL DEFAULT '{}',             -- JSON, құпия мазмұнсыз
    ip          TEXT NOT NULL DEFAULT '',
    created_at  INTEGER NOT NULL
);
CREATE INDEX idx_audit_created ON admin_audit_logs (created_at);

CREATE TABLE notification_campaigns (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    audience    TEXT NOT NULL DEFAULT 'all',
    status      TEXT NOT NULL DEFAULT 'draft',          -- draft | unavailable
    created_by  TEXT NOT NULL DEFAULT '',
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

CREATE TABLE app_versions (
    id            TEXT PRIMARY KEY,
    platform      TEXT NOT NULL,
    version       TEXT NOT NULL,
    build         TEXT NOT NULL DEFAULT '',
    min_supported TEXT NOT NULL DEFAULT '',
    released_at   INTEGER NOT NULL,
    UNIQUE (platform, version)
);

CREATE TABLE system_settings (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
