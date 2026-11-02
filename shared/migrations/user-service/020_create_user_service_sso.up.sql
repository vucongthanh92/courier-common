CREATE TABLE IF NOT EXISTS "user-service".sso_sessions (
    id BIGINT PRIMARY KEY CHECK (id > 0),
    user_id BIGINT NOT NULL REFERENCES "user-service".users(id),
    session_hash TEXT NOT NULL UNIQUE,
    user_agent TEXT,
    ip INET,
    auth_time TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sso_sessions_user_active
    ON "user-service".sso_sessions (user_id, expires_at)
    WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS "user-service".sso_authorization_codes (
    id BIGINT PRIMARY KEY CHECK (id > 0),
    code_hash TEXT NOT NULL UNIQUE,
    user_id BIGINT NOT NULL REFERENCES "user-service".users(id),
    client_id TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    scope TEXT NOT NULL,
    state TEXT,
    nonce TEXT,
    code_challenge TEXT NOT NULL,
    code_challenge_method TEXT NOT NULL,
    sso_session_id BIGINT REFERENCES "user-service".sso_sessions(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sso_authorization_codes_active
    ON "user-service".sso_authorization_codes (client_id, expires_at)
    WHERE consumed_at IS NULL;
