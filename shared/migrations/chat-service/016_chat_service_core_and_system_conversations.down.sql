DROP TABLE IF EXISTS "chat-service".processed_events;

DROP INDEX IF EXISTS "chat-service".idx_conversations_system_owner_name_unique;

DELETE FROM "chat-service".conversation_members cm
USING "chat-service".conversations c
WHERE cm.conversation_id = c.id
  AND c.type = 'system'
  AND c.name IN ('notification', 'assistant');

DELETE FROM "chat-service".conversations
WHERE type = 'system'
  AND name IN ('notification', 'assistant');

DROP SEQUENCE IF EXISTS "chat-service".system_chat_id_seq;

CREATE OR REPLACE FUNCTION "chat-service".validate_message_sender_membership()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM "chat-service".conversation_members cm
        WHERE cm.conversation_id = NEW.conversation_id
          AND cm.user_id = NEW.sender_id
          AND cm.status = 'active'
    ) THEN
        RAISE EXCEPTION 'sender % is not an active member of conversation %', NEW.sender_id, NEW.conversation_id;
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
