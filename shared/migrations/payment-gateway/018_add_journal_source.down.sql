DELETE FROM "payment-gateway".ledger_accounts
WHERE account_code = 'asset:sepay:clearing:vnd'
  AND NOT EXISTS (
      SELECT 1 FROM "payment-gateway".ledger_entries entries
      WHERE entries.account_id = "payment-gateway".ledger_accounts.id
  );

DROP INDEX IF EXISTS "payment-gateway".idx_payment_gateway_idempotency_user_created;
ALTER TABLE "payment-gateway".idempotency_keys
    DROP CONSTRAINT IF EXISTS idempotency_keys_scope_user_key_unique,
    ADD CONSTRAINT idempotency_keys_scope_idempotency_key_key
        UNIQUE (scope, idempotency_key),
    DROP COLUMN IF EXISTS user_id;

ALTER TABLE "payment-gateway".wallets
    DROP CONSTRAINT IF EXISTS wallets_restricted_at_check,
    DROP CONSTRAINT IF EXISTS wallets_risk_level_check,
    DROP CONSTRAINT IF EXISTS wallets_wallet_type_check,
    DROP COLUMN IF EXISTS risk_level,
    DROP COLUMN IF EXISTS restricted_by,
    DROP COLUMN IF EXISTS restricted_at,
    DROP COLUMN IF EXISTS status_reason,
    DROP COLUMN IF EXISTS metadata,
    DROP COLUMN IF EXISTS wallet_type,
    DROP COLUMN IF EXISTS display_name;

DROP INDEX IF EXISTS "payment-gateway".idx_payment_gateway_journals_source_provider_created;
ALTER TABLE "payment-gateway".ledger_journals
    DROP CONSTRAINT IF EXISTS ledger_journals_source_provider_check,
    DROP CONSTRAINT IF EXISTS ledger_journals_source_type_check,
    DROP COLUMN IF EXISTS source_provider,
    DROP COLUMN IF EXISTS source_type;
