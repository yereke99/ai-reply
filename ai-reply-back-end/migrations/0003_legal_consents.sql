-- 0003_legal_consents: versioned acceptance of the public legal documents.

CREATE TABLE legal_consents (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    terms_version   TEXT NOT NULL,
    privacy_version TEXT NOT NULL,
    accepted_at     INTEGER NOT NULL,
    locale          TEXT NOT NULL DEFAULT 'en',
    platform        TEXT NOT NULL DEFAULT '',
    app_version     TEXT NOT NULL DEFAULT '',
    created_at      INTEGER NOT NULL,
    UNIQUE (user_id, terms_version, privacy_version)
);

CREATE INDEX idx_legal_consents_user
    ON legal_consents (user_id, accepted_at DESC);
