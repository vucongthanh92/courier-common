# Development Commands

This document lists the commands that are commonly useful when working in the courier repository.

## Root Commands

Run from the repository root.

| Command | Purpose |
| --- | --- |
| `make kind-create` | Create the local kind cluster `courier-dev`. |
| `make kind-delete` | Delete the local kind cluster. |
| `make kind-load-user-service` | Build and load the `user-service:dev` image into kind. |
| `make kind-apply-argocd` | Install Argo CD into the local cluster. |
| `make kind-apply-user-service` | Apply the Argo CD user-service app manifest. |
| `make dev-user-up` | Build/load user-service and apply local Argo CD resources. |
| `make start-argocd` | Port-forward Argo CD server to `https://localhost:8080`. |
| `make update-argocd-admin-basic-auth` | Create or rotate the Basic Auth credential for `https://courier.io.vn/admin/argocd`; it never prints the password or hash. |
| `make enable-argocd-public-dashboard` | Bootstrap the GitOps Application for the protected public Argo CD dashboard. |
| `make start-postgres` | Open private PostgreSQL SSM tunnels: `user_service` on `127.0.0.1:15432`, `chat_service` on `:15433`, and `payment_gateway` on `:15434`. |
| `make configure-user-service-sso-runtime` | Create/update non-secret user-service SSO runtime parameters in AWS Parameter Store. |
| `make migrate-user-service-oauth-runtime` | Copy existing Google OAuth SecureStrings into the standard user-service runtime prefix without printing them. |
| `make update-user-service-google-oauth` | Interactively update Google OAuth credentials in the standard runtime prefix. |
| `make update-kafka-admin-basic-auth` | Create or rotate the AWS Parameter Store credential for `https://courier.io.vn/admin/kafka`; it never prints the password or hash. |
| `make update-logging-dashboard-credentials` | Create or rotate the Basic Auth and Grafana administrator credentials for `https://courier.io.vn/admin/logging`; it never prints them. |
| `make enable-observability` | Bootstrap the GitOps Application for the AWS dev Prometheus, Loki, Alloy, and Grafana stack. |

## user-service Commands

Run from `user-service/`.

| Command | Purpose |
| --- | --- |
| `make install` | Install local tooling from `install.sh`. |
| `make run-local` | Run user-service with `config/local/config.yaml`. |
| `make run-user` | Run user-service and append logs under `../logs/`. |
| `make wire` | Regenerate Wire dependency injection. |
| `make swagger` | Regenerate Swagger docs. |
| `make proto-gen` | Generate service-local proto files from `pkg/grpc/proto`. |
| `make migrate-file filename=<name>` | Create a new migration file pair. |
| `make compose` | Start local Docker Compose stack. |
| `make compose-dev` | Start dev Docker Compose stack. |
| `make test` | Run `go test -v ./...`. |
| `make build-image` | Build `courier/user-service`. |
| `make get-env` | Pull selected GitHub environment variables into `.env.local`. |

## chat-service Commands

Run from `chat-service/`.

| Command | Purpose |
| --- | --- |
| `make run-local` | Run chat-service with `config/local/config.yaml`. |
| `make wire` | Regenerate Wire dependency injection. |
| `make migrate-file filename=<name>` | Create a new migration file pair. |
| `make test` | Run `go test -v ./...`. |

## Shared gRPC Commands

Run from `shared/` when regenerating shared contracts.

```bash
PATH=$HOME/go/bin:$PATH protoc \
  --go_out=<contract>/gen \
  --go_opt=paths=source_relative \
  --go-grpc_out=<contract>/gen \
  --go-grpc_opt=paths=source_relative,require_unimplemented_servers=false \
  -I <contract>/proto \
  <contract>/proto/*.proto
```

After regenerating shared contracts, run `go mod vendor` in services that import `shared`.

## Build Cache Workaround

If Go commands fail with permission errors under `~/Library/Caches/go-build`, use a workspace-local cache:

```bash
GOCACHE=$(pwd)/../.cache/go-build go build ./...
```

From repository root:

```bash
GOCACHE=/Users/vucongthanh/Documents/workspace/golang/courier/.cache/go-build go build ./...
```
