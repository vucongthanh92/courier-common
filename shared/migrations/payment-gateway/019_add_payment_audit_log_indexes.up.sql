CREATE INDEX IF NOT EXISTS idx_payment_gateway_audit_logs_resource_created
    ON "payment-gateway".audit_logs (resource_type, resource_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_gateway_audit_logs_actor_created
    ON "payment-gateway".audit_logs (actor_type, actor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_gateway_audit_logs_action_created
    ON "payment-gateway".audit_logs (action, created_at DESC);
