# Courier Event Bus

This folder stores broker configuration, event contracts, and routing conventions shared by Courier services. Service-specific business logic belongs in each service.

## Phase 1 Broker

Courier uses Kafka as the main event-driven infrastructure target. Kafka gives Courier a durable event log, partition-level ordering, replay-friendly consumers, and a path toward analytics/audit/event-stream use cases as the platform grows.

RabbitMQ remains a possible alternative for command-like workflows that need simple routing, acknowledgements, and dead-letter queues, but it is not the target for this feature.

## Kafka Conventions

- Bootstrap server: `localhost:9092`
- Dashboard: `http://localhost:8081`
- Email-verification event topic: `courier.user.email-verified.v1`
- Email-verification retry topic: `courier.user.email-verified.retry.v1`
- Email-verification dead-letter topic: `courier.user.email-verified.dlq.v1`
- Chat event topic: `courier.chat.events.v1`
- Assistant request topic: `courier.assistant.requested.v1`
- Assistant response topic: `courier.assistant.responded.v1`
- Assistant retry topic: `courier.assistant.events.retry.v1`
- Assistant dead-letter topic: `courier.assistant.events.dlq.v1`
- Chat consumer group: `chat-service`
- Agent gateway consumer group: `agent-gateway`
- Producer message key: `aggregate_id` or `user_id` so events for the same user stay ordered within a partition.

Consumers must commit offsets only after their database transaction succeeds.

## Chat Events

`courier.chat.events.v1` carries integration events owned by `chat-service`.

Current contract:

```text
contracts/conversation.created.v1.json
```

`conversation.created.v1` is emitted after a conversation is created. `chat-service` consumes this event to create notification-system messages for every member in the new conversation. The event allows this system notification flow to stay asynchronous from the HTTP create-conversation request.

## Topic Definitions

Kafka topics are declared in `event-bus/kafka/topics.json`.

Each topic object uses:

```json
{
  "name": "courier.user.email-verified.v1",
  "partitions": 3,
  "replicationFactor": 1,
  "description": "User email-verification integration events."
}
```

When adding a new topic, add one object to that file and rerun:

```sh
docker compose -f event-bus/kafka/docker-compose.yaml up kafka-init
```

## Event Envelope

All integration events should use this envelope:

```json
{
  "event_id": "unique-event-id",
  "event_type": "user.email_verified",
  "event_version": 1,
  "occurred_at": "2026-07-31T00:00:00Z",
  "source": "user-service",
  "aggregate_type": "user",
  "aggregate_id": "123",
  "payload": {}
}
```

Consumers must be idempotent by `event_id`.

— Nội dung được viết/cập nhật bởi AI (OpenAI Codex).
