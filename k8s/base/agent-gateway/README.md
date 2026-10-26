# agent-gateway Kubernetes configuration

The Deployment mounts `config.yaml` from the SOPS-generated
`agent-gateway-config` Secret. It holds the Qdrant API key and OpenAI API key,
so only ciphertext is committed in the development overlay.

The `/healthz` probe checks Qdrant readiness. Kafka and Qdrant are reached
through the private `kafka` and `qdrant` Services in `courier-dev`.
