CREATE SCHEMA IF NOT EXISTS "chat-service";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'conversation_type_enum'
          AND n.nspname = 'chat-service'
    ) THEN
        CREATE TYPE "chat-service".conversation_type_enum AS ENUM ('direct', 'group', 'notify', 'system');
    ELSIF NOT EXISTS (
        SELECT 1
        FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'conversation_type_enum'
          AND n.nspname = 'chat-service'
          AND e.enumlabel = 'system'
    ) THEN
        ALTER TYPE "chat-service".conversation_type_enum RENAME TO conversation_type_enum_old;
        CREATE TYPE "chat-service".conversation_type_enum AS ENUM ('direct', 'group', 'notify', 'system');

        IF to_regclass('"chat-service".conversations') IS NOT NULL THEN
            DROP INDEX IF EXISTS "chat-service".idx_conversations_direct_key_unique;
            DROP INDEX IF EXISTS "chat-service".idx_conversations_system_owner_name_unique;

            ALTER TABLE "chat-service".conversations
                ALTER COLUMN type TYPE "chat-service".conversation_type_enum
                USING type::text::"chat-service".conversation_type_enum;
        END IF;

        DROP TYPE "chat-service".conversation_type_enum_old;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'conversation_member_role_enum'
          AND n.nspname = 'chat-service'
    ) THEN
        CREATE TYPE "chat-service".conversation_member_role_enum AS ENUM ('owner', 'admin', 'member');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'conversation_member_status_enum'
          AND n.nspname = 'chat-service'
    ) THEN
        CREATE TYPE "chat-service".conversation_member_status_enum AS ENUM ('active', 'left', 'removed');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE t.typname = 'message_type_enum'
          AND n.nspname = 'chat-service'
    ) THEN
        CREATE TYPE "chat-service".message_type_enum AS ENUM ('text', 'system');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS "chat-service".conversations (
    id BIGINT PRIMARY KEY CHECK (id > 0),
    type "chat-service".conversation_type_enum NOT NULL,
    direct_key TEXT NULL,
    name VARCHAR(255) NULL,
    created_by BIGINT NOT NULL,
    last_message_id BIGINT NULL,
    last_message_at TIMESTAMPTZ NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ NULL
);

CREATE TABLE IF NOT EXISTS "chat-service".conversation_members (
    id BIGINT PRIMARY KEY CHECK (id > 0),
    conversation_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    role "chat-service".conversation_member_role_enum NOT NULL DEFAULT 'member',
    status "chat-service".conversation_member_status_enum NOT NULL DEFAULT 'active',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ NULL,
    last_read_message_id BIGINT NULL,
    last_read_at TIMESTAMPTZ NULL,
    muted_until TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS "chat-service".messages (
    id BIGINT PRIMARY KEY CHECK (id > 0),
    conversation_id BIGINT NOT NULL,
    sender_id BIGINT NOT NULL,
    type "chat-service".message_type_enum NOT NULL DEFAULT 'text',
    body TEXT NOT NULL,
    reply_to_message_id BIGINT NULL,
    client_message_id VARCHAR(64) NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    edited_at TIMESTAMPTZ NULL,
    deleted_at TIMESTAMPTZ NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_conversation_members_conversation'
          AND conrelid = '"chat-service".conversation_members'::regclass
    ) THEN
        ALTER TABLE "chat-service".conversation_members
            ADD CONSTRAINT fk_conversation_members_conversation
                FOREIGN KEY (conversation_id) REFERENCES "chat-service".conversations(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_conversation_members_conversation_user'
          AND conrelid = '"chat-service".conversation_members'::regclass
    ) THEN
        ALTER TABLE "chat-service".conversation_members
            ADD CONSTRAINT uq_conversation_members_conversation_user
                UNIQUE (conversation_id, user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_conversation_members_status_left_at'
          AND conrelid = '"chat-service".conversation_members'::regclass
    ) THEN
        ALTER TABLE "chat-service".conversation_members
            ADD CONSTRAINT chk_conversation_members_status_left_at
                CHECK (
                    (status = 'active' AND left_at IS NULL)
                    OR
                    (status IN ('left', 'removed') AND left_at IS NOT NULL)
                );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_messages_conversation'
          AND conrelid = '"chat-service".messages'::regclass
    ) THEN
        ALTER TABLE "chat-service".messages
            ADD CONSTRAINT fk_messages_conversation
                FOREIGN KEY (conversation_id) REFERENCES "chat-service".conversations(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_messages_reply_to'
          AND conrelid = '"chat-service".messages'::regclass
    ) THEN
        ALTER TABLE "chat-service".messages
            ADD CONSTRAINT fk_messages_reply_to
                FOREIGN KEY (reply_to_message_id) REFERENCES "chat-service".messages(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_messages_body_for_text'
          AND conrelid = '"chat-service".messages'::regclass
    ) THEN
        ALTER TABLE "chat-service".messages
            ADD CONSTRAINT chk_messages_body_for_text
                CHECK (
                    (type = 'text' AND COALESCE(LENGTH(BTRIM(body)), 0) > 0)
                    OR
                    (type = 'system' AND COALESCE(LENGTH(BTRIM(body)), 0) > 0)
                );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_conversations_last_message'
          AND conrelid = '"chat-service".conversations'::regclass
    ) THEN
        ALTER TABLE "chat-service".conversations
            ADD CONSTRAINT fk_conversations_last_message
                FOREIGN KEY (last_message_id) REFERENCES "chat-service".messages(id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_conversation_members_last_read_message'
          AND conrelid = '"chat-service".conversation_members'::regclass
    ) THEN
        ALTER TABLE "chat-service".conversation_members
            ADD CONSTRAINT fk_conversation_members_last_read_message
                FOREIGN KEY (last_read_message_id) REFERENCES "chat-service".messages(id);
    END IF;
END $$;

ALTER TABLE "chat-service".messages
    DROP CONSTRAINT IF EXISTS fk_messages_sender;

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_direct_key_unique
    ON "chat-service".conversations (direct_key)
    WHERE type = 'direct' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at
    ON "chat-service".conversations (last_message_at DESC NULLS LAST);

CREATE INDEX IF NOT EXISTS idx_conversation_members_user_active
    ON "chat-service".conversation_members (user_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_conversation_members_conversation_active
    ON "chat-service".conversation_members (conversation_id, status);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_created_at
    ON "chat-service".messages (conversation_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_messages_sender_created_at
    ON "chat-service".messages (sender_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_client_message_id
    ON "chat-service".messages (conversation_id, client_message_id)
    WHERE client_message_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_system_owner_name_unique
    ON "chat-service".conversations (created_by, name)
    WHERE type = 'system' AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS "chat-service".processed_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_processed_events_event_type_processed_at
    ON "chat-service".processed_events (event_type, processed_at DESC);

CREATE SEQUENCE IF NOT EXISTS "chat-service".system_chat_id_seq START WITH 1 INCREMENT BY 1;

CREATE OR REPLACE FUNCTION "chat-service".validate_direct_membership_limit()
RETURNS TRIGGER AS $$
DECLARE
    conversation_type "chat-service".conversation_type_enum;
    active_member_count INTEGER;
BEGIN
    SELECT type
    INTO conversation_type
    FROM "chat-service".conversations
    WHERE id = NEW.conversation_id;

    IF conversation_type = 'direct' AND NEW.status = 'active' THEN
        SELECT COUNT(*)
        INTO active_member_count
        FROM "chat-service".conversation_members
        WHERE conversation_id = NEW.conversation_id
          AND status = 'active'
          AND id <> NEW.id;

        IF active_member_count >= 2 THEN
            RAISE EXCEPTION 'direct conversation % cannot have more than 2 active members', NEW.conversation_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_direct_membership_limit ON "chat-service".conversation_members;
CREATE TRIGGER trg_validate_direct_membership_limit
BEFORE INSERT OR UPDATE ON "chat-service".conversation_members
FOR EACH ROW
EXECUTE FUNCTION "chat-service".validate_direct_membership_limit();

CREATE OR REPLACE FUNCTION "chat-service".validate_member_last_read_message()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.last_read_message_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM "chat-service".messages m
        WHERE m.id = NEW.last_read_message_id
          AND m.conversation_id = NEW.conversation_id
    ) THEN
        RAISE EXCEPTION 'last_read_message_id % does not belong to conversation %', NEW.last_read_message_id, NEW.conversation_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_member_last_read_message ON "chat-service".conversation_members;
CREATE TRIGGER trg_validate_member_last_read_message
BEFORE INSERT OR UPDATE ON "chat-service".conversation_members
FOR EACH ROW
EXECUTE FUNCTION "chat-service".validate_member_last_read_message();

CREATE OR REPLACE FUNCTION "chat-service".validate_message_sender_membership()
RETURNS TRIGGER AS $$
DECLARE
    conversation_type "chat-service".conversation_type_enum;
BEGIN
    SELECT type
    INTO conversation_type
    FROM "chat-service".conversations
    WHERE id = NEW.conversation_id
      AND deleted_at IS NULL;

    IF conversation_type IS NULL THEN
        RAISE EXCEPTION 'conversation % does not exist', NEW.conversation_id;
    END IF;

    IF NEW.sender_id = 0 THEN
        IF conversation_type <> 'system' THEN
            RAISE EXCEPTION 'backend sender is only allowed in system conversations';
        END IF;
    ELSE
        IF NOT EXISTS (
            SELECT 1
            FROM "chat-service".conversation_members cm
            WHERE cm.conversation_id = NEW.conversation_id
              AND cm.user_id = NEW.sender_id
              AND cm.status = 'active'
        ) THEN
            RAISE EXCEPTION 'sender % is not an active member of conversation %', NEW.sender_id, NEW.conversation_id;
        END IF;
    END IF;

    IF NEW.reply_to_message_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM "chat-service".messages m
        WHERE m.id = NEW.reply_to_message_id
          AND m.conversation_id = NEW.conversation_id
    ) THEN
        RAISE EXCEPTION 'reply_to_message_id % does not belong to conversation %', NEW.reply_to_message_id, NEW.conversation_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_message_sender_membership ON "chat-service".messages;
CREATE TRIGGER trg_validate_message_sender_membership
BEFORE INSERT ON "chat-service".messages
FOR EACH ROW
EXECUTE FUNCTION "chat-service".validate_message_sender_membership();

CREATE OR REPLACE FUNCTION "chat-service".sync_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE "chat-service".conversations
    SET last_message_id = NEW.id,
        last_message_at = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_conversation_last_message ON "chat-service".messages;
CREATE TRIGGER trg_sync_conversation_last_message
AFTER INSERT ON "chat-service".messages
FOR EACH ROW
EXECUTE FUNCTION "chat-service".sync_conversation_last_message();

-- System conversations are created from user lifecycle events. Keeping this
-- migration local to chat-service avoids cross-database reads of user-service.
