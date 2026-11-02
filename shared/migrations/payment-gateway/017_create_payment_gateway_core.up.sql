CREATE SCHEMA IF NOT EXISTS "payment-gateway";

CREATE TYPE "payment-gateway".wallet_status AS ENUM ('active', 'restricted', 'closed');
CREATE TYPE "payment-gateway".account_type AS ENUM ('asset', 'liability', 'revenue', 'expense');
CREATE TYPE "payment-gateway".journal_status AS ENUM ('posted', 'reversed');
CREATE TYPE "payment-gateway".entry_side AS ENUM ('debit', 'credit');
CREATE TYPE "payment-gateway".topup_status AS ENUM ('created', 'pending', 'succeeded', 'failed', 'expired', 'cancelled', 'reversed');
CREATE TYPE "payment-gateway".provider_event_status AS ENUM ('received', 'processed', 'ignored', 'failed');

CREATE TABLE "payment-gateway".wallets (
    id BIGINT PRIMARY KEY CHECK (id > 0), user_id BIGINT NOT NULL CHECK (user_id > 0), currency CHAR(3) NOT NULL DEFAULT 'VND',
    status "payment-gateway".wallet_status NOT NULL DEFAULT 'active', created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), closed_at TIMESTAMPTZ,
    UNIQUE (user_id, currency), CHECK ((status = 'closed') = (closed_at IS NOT NULL))
);
CREATE TABLE "payment-gateway".ledger_accounts (
    id BIGINT PRIMARY KEY CHECK (id > 0), account_code TEXT NOT NULL UNIQUE,
    account_type "payment-gateway".account_type NOT NULL, currency CHAR(3) NOT NULL DEFAULT 'VND',
    wallet_id BIGINT UNIQUE REFERENCES "payment-gateway".wallets(id), normal_side "payment-gateway".entry_side NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE "payment-gateway".ledger_journals (
    id BIGINT PRIMARY KEY CHECK (id > 0), reference_type TEXT NOT NULL, reference_id TEXT NOT NULL,
    status "payment-gateway".journal_status NOT NULL DEFAULT 'posted',
    reversal_of_id BIGINT UNIQUE REFERENCES "payment-gateway".ledger_journals(id), narrative TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (reference_type, reference_id)
);
CREATE TABLE "payment-gateway".ledger_entries (
    id BIGINT PRIMARY KEY CHECK (id > 0), journal_id BIGINT NOT NULL REFERENCES "payment-gateway".ledger_journals(id),
    account_id BIGINT NOT NULL REFERENCES "payment-gateway".ledger_accounts(id), side "payment-gateway".entry_side NOT NULL,
    amount_minor BIGINT NOT NULL CHECK (amount_minor > 0), currency CHAR(3) NOT NULL DEFAULT 'VND',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE "payment-gateway".wallet_balances (
    wallet_id BIGINT PRIMARY KEY REFERENCES "payment-gateway".wallets(id), currency CHAR(3) NOT NULL DEFAULT 'VND',
    available_minor BIGINT NOT NULL DEFAULT 0 CHECK (available_minor >= 0), pending_minor BIGINT NOT NULL DEFAULT 0 CHECK (pending_minor >= 0),
    held_minor BIGINT NOT NULL DEFAULT 0 CHECK (held_minor >= 0), version BIGINT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE "payment-gateway".topup_intents (
    id BIGINT PRIMARY KEY CHECK (id > 0), user_id BIGINT NOT NULL CHECK (user_id > 0),
    wallet_id BIGINT NOT NULL REFERENCES "payment-gateway".wallets(id), amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL DEFAULT 'VND', provider TEXT NOT NULL, method TEXT NOT NULL,
    status "payment-gateway".topup_status NOT NULL DEFAULT 'created', provider_checkout_id TEXT, provider_payment_url TEXT,
    qr_payload TEXT, provider_invoice_number TEXT NOT NULL, payment_code TEXT, receiving_account_key TEXT,
    expires_at TIMESTAMPTZ NOT NULL, succeeded_at TIMESTAMPTZ, failure_code TEXT, failure_message TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (expires_at > created_at), UNIQUE (provider, provider_checkout_id), UNIQUE (provider, provider_invoice_number), UNIQUE (payment_code)
);
CREATE TABLE "payment-gateway".provider_events (
    id BIGINT PRIMARY KEY CHECK (id > 0), provider TEXT NOT NULL, provider_event_id TEXT NOT NULL,
    payload JSONB NOT NULL, signature_valid BOOLEAN NOT NULL, status "payment-gateway".provider_event_status NOT NULL DEFAULT 'received',
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), processed_at TIMESTAMPTZ, error_code TEXT, UNIQUE (provider, provider_event_id)
);
CREATE TABLE "payment-gateway".provider_transactions (
    id BIGINT PRIMARY KEY CHECK (id > 0), provider TEXT NOT NULL, provider_transaction_id TEXT NOT NULL,
    topup_intent_id BIGINT NOT NULL REFERENCES "payment-gateway".topup_intents(id), amount_minor BIGINT NOT NULL CHECK (amount_minor > 0),
    currency CHAR(3) NOT NULL, paid_at TIMESTAMPTZ, receiving_account_key TEXT,
    source_metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_transaction_id), UNIQUE (topup_intent_id)
);
CREATE TABLE "payment-gateway".idempotency_keys (
    id BIGINT PRIMARY KEY CHECK (id > 0), scope TEXT NOT NULL, idempotency_key TEXT NOT NULL, request_hash TEXT NOT NULL,
    response_status SMALLINT, response_body JSONB, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), expires_at TIMESTAMPTZ NOT NULL,
    UNIQUE (scope, idempotency_key), CHECK (expires_at > created_at)
);
CREATE TABLE "payment-gateway".outbox_events (
    id BIGINT PRIMARY KEY CHECK (id > 0), aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, event_type TEXT NOT NULL,
    payload JSONB NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), published_at TIMESTAMPTZ, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT
);
CREATE TABLE "payment-gateway".audit_logs (
    id BIGINT PRIMARY KEY CHECK (id > 0), actor_type TEXT NOT NULL, actor_id TEXT, action TEXT NOT NULL,
    resource_type TEXT NOT NULL, resource_id TEXT NOT NULL, ip INET, metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE "payment-gateway".reconciliation_runs (
    id BIGINT PRIMARY KEY CHECK (id > 0), provider TEXT NOT NULL, period_start TIMESTAMPTZ NOT NULL, period_end TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('running', 'completed', 'failed')), started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ, summary JSONB NOT NULL DEFAULT '{}'::jsonb, CHECK (period_end > period_start)
);
CREATE TABLE "payment-gateway".reconciliation_items (
    id BIGINT PRIMARY KEY CHECK (id > 0), reconciliation_run_id BIGINT NOT NULL REFERENCES "payment-gateway".reconciliation_runs(id),
    provider_transaction_id TEXT, topup_intent_id BIGINT REFERENCES "payment-gateway".topup_intents(id),
    status TEXT NOT NULL CHECK (status IN ('matched', 'missing_local', 'missing_provider', 'amount_mismatch', 'manual_review')),
    detail JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payment_gateway_topups_user_created ON "payment-gateway".topup_intents (user_id, created_at DESC);
CREATE INDEX idx_payment_gateway_topups_pending_expiry ON "payment-gateway".topup_intents (status, expires_at) WHERE status IN ('created', 'pending');
CREATE INDEX idx_payment_gateway_ledger_entries_account_created ON "payment-gateway".ledger_entries (account_id, created_at DESC);
CREATE INDEX idx_payment_gateway_outbox_unpublished ON "payment-gateway".outbox_events (created_at) WHERE published_at IS NULL;
CREATE INDEX idx_payment_gateway_reconciliation_items_run_status ON "payment-gateway".reconciliation_items (reconciliation_run_id, status);

CREATE OR REPLACE FUNCTION "payment-gateway".ensure_balanced_journal() RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM (
            SELECT currency,
                COALESCE(SUM(amount_minor) FILTER (WHERE side = 'debit'), 0) AS debits,
                COALESCE(SUM(amount_minor) FILTER (WHERE side = 'credit'), 0) AS credits
            FROM "payment-gateway".ledger_entries
            WHERE journal_id = COALESCE(NEW.journal_id, OLD.journal_id)
            GROUP BY currency
        ) balances WHERE debits <> credits
    ) THEN RAISE EXCEPTION 'journal % is not balanced', COALESCE(NEW.journal_id, OLD.journal_id); END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;
CREATE CONSTRAINT TRIGGER ledger_entries_balanced
AFTER INSERT OR UPDATE OR DELETE ON "payment-gateway".ledger_entries DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION "payment-gateway".ensure_balanced_journal();
