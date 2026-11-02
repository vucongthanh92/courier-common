-- Add origin classification, wallet controls, a scoped idempotency owner and
-- the system clearing account used by SePay top-ups.

ALTER TABLE "payment-gateway".ledger_journals
    ADD COLUMN source_type TEXT NOT NULL DEFAULT 'internal',
    ADD COLUMN source_provider TEXT;

ALTER TABLE "payment-gateway".ledger_journals
    ADD CONSTRAINT ledger_journals_source_type_check
        CHECK (source_type IN ('external_provider', 'internal', 'admin', 'system')),
    ADD CONSTRAINT ledger_journals_source_provider_check
        CHECK (
            (source_type = 'external_provider' AND source_provider IS NOT NULL)
            OR (source_type <> 'external_provider' AND source_provider IS NULL)
        );

CREATE INDEX idx_payment_gateway_journals_source_provider_created
    ON "payment-gateway".ledger_journals (source_type, source_provider, created_at DESC);

ALTER TABLE "payment-gateway".wallets
    ADD COLUMN display_name TEXT,
    ADD COLUMN wallet_type TEXT NOT NULL DEFAULT 'personal',
    ADD COLUMN metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN status_reason TEXT,
    ADD COLUMN restricted_at TIMESTAMPTZ,
    ADD COLUMN restricted_by TEXT,
    ADD COLUMN risk_level TEXT NOT NULL DEFAULT 'normal';

ALTER TABLE "payment-gateway".wallets
    ADD CONSTRAINT wallets_wallet_type_check
        CHECK (wallet_type IN ('personal', 'merchant', 'escrow', 'system')),
    ADD CONSTRAINT wallets_risk_level_check
        CHECK (risk_level IN ('normal', 'elevated', 'high')),
    ADD CONSTRAINT wallets_restricted_at_check
        CHECK (status <> 'restricted' OR restricted_at IS NOT NULL);

ALTER TABLE "payment-gateway".idempotency_keys
    ADD COLUMN user_id BIGINT CHECK (user_id IS NULL OR user_id > 0);

ALTER TABLE "payment-gateway".idempotency_keys
    DROP CONSTRAINT IF EXISTS idempotency_keys_scope_idempotency_key_key,
    ADD CONSTRAINT idempotency_keys_scope_user_key_unique
        UNIQUE (scope, user_id, idempotency_key);

CREATE INDEX idx_payment_gateway_idempotency_user_created
    ON "payment-gateway".idempotency_keys (user_id, created_at DESC)
    WHERE user_id IS NOT NULL;

INSERT INTO "payment-gateway".ledger_accounts (
    id, account_code, account_type, currency, wallet_id, normal_side, is_active
) VALUES (
    1001, 'asset:sepay:clearing:vnd', 'asset', 'VND', NULL, 'debit', TRUE
) ON CONFLICT (account_code) DO NOTHING;
