# AWS Dev Environment Plan

For a visual, operations-oriented overview of this plan and its current
implementation state, read [AWS Dev Platform Guide](devops/aws-dev-platform-guide.md).

## Status and scope

This is the technical source of truth for Courier's agreed AWS development
environment. It is based on the Notion plan, read on 2026-10-15, and on a
source review of the `main` branch of every Courier repository. It covers a
continuously running development and demo environment, not a production HA
environment.

Constraints that are already agreed:

- AWS credit: USD 200; target ongoing AWS budget: at most USD 100/month.
- Kubernetes: K3s on EC2 first. EKS is a later upgrade option, not the
  baseline.
- CI: GitHub Actions. Image registry: ECR. CD: Argo CD. Argo CD does not build
  images.
- P0/P1 did not create AWS resources or purchase a domain. The later P2
  rollout uses the purchased `courier.io.vn` domain; DNS remains in ZoneDNS.
- All deployable repositories release from `main`.
- Go dependencies are resolved from committed `go.mod` and `go.sum`; service
  repositories do not commit `vendor/` as the normal CI/CD dependency source.
- Runtime CPU/RAM/disk baseline is deferred to the initial AWS EC2 environment;
  local runtime profiling is not a P0 gate.

Source: [Courier Project — AWS dev plan](https://app.notion.com/p/1d3bf04e79af80958d25e047feca89c3).

## Evidence classification

`Verified` means checked against the named repository's local `main` snapshot
on 2026-10-15, or executed from an isolated archive of that snapshot. It does
not mean the service has been run against a real AWS environment.

`Assumption / decision pending` is a proposed implementation detail that needs
measurement, a cost estimate, or an explicit decision before it becomes a
deployment commitment.

## Verified source inventory

| Component | Repository / branch reviewed | Build result | Runtime dependencies observed |
| --- | --- | --- | --- |
| Shared contracts, migrations, Kafka, tracing, initial K8s/Argo | `courier` (`courier-common`) / `main` | Shared module not independently tested | PostgreSQL migrations, Kafka, observability stack |
| Identity / SSO | `courier-user-svc` / `main` | `go test -mod=vendor ./...` passed | PostgreSQL, Redis, Kafka, Loki, OAuth providers |
| Chat / WebSocket | `courier-chat-svc` / `main` | `go test -mod=vendor ./...` passed | PostgreSQL, Redis, Kafka, user-service gRPC, Loki |
| Payments | `courier-payment-gateway` / `main` | `go test ./...` passed; `go build -mod=vendor` failed because vendor metadata is stale | PostgreSQL, Redis, Kafka, user-service gRPC, SePay Sandbox, Loki |
| Agent | `courier-agent-gateway` / `main` | `go test -mod=vendor ./...` passed | Kafka, Qdrant, OpenAI-compatible API |
| Conversa | `courier-conversa-app` / `main` | `pnpm install --frozen-lockfile && pnpm run build` passed | API/WSS endpoints supplied at frontend build time |
| Flikk | `courier-flikk-app` / `main` | `pnpm install --frozen-lockfile && pnpm run build` passed | API/WSS endpoints supplied at frontend build time |

The two frontend production artifacts measured from that build were 2.9 MiB
(Conversa) and 256 KiB (Flikk), including generated source maps/assets. These
are artifact-size observations, **not** a memory or capacity baseline.

Native ARM64 build artifacts measured 81 MiB (user), 65 MiB (chat), 54 MiB
(payment), and 12 MiB (agent). These are local Mach-O executable sizes and
must not be used as Linux container image sizes.

### Verified deployment readiness gaps

- Only user-service and agent-gateway have Dockerfiles in their service repos.
  Chat, payment, Conversa, and Flikk need reproducible production image
  definitions before they can be deployed by the planned pipeline.
- User and chat currently use a local `replace` for
  `github.com/vucongthanh92/courier/shared` to
  `../courier-common/shared`. Payment pins a pseudo-version instead. CI must
  build every service from a clean checkout, so all consumers need a released
  or pinned shared-module version; a `go.work` file is for local development
  only.
- Payment's checked-in `vendor/modules.txt` is inconsistent with `go.mod`:
  `go build -mod=vendor` fails. The agreed remediation is to stop tracking and
  relying on vendored dependencies in service repos, then enforce
  `go mod download`, `go mod verify`, and `go test/build -mod=readonly` in CI.
  A future air-gapped requirement would be an explicit exception: commit a
  complete, regenerated vendor tree and use it consistently.
- The existing monorepo workflow builds only user-service, pushes to GHCR, and
  also tags `latest`. It is not the ECR + SHA/digest + GitOps PR workflow
  agreed for AWS dev.
- The current Kustomize/Argo material deploys only user-service. It uses
  `latest`, TCP probes, and has no resource requests or limits.
- Kafka's current compose definition has no persistent Kafka data volume and
  advertises `localhost` externally. It cannot be used unchanged by K3s pods.
- User, chat, and payment local configs expose HTTP/gRPC/health/metrics ports
  and use PostgreSQL, Redis, Kafka, and Loki. Agent adds Qdrant and an AI
  provider. These are the minimum data and secret inventories for P0.
- User and chat configuration declares database pools up to 200 open
  connections per read and write pool; payment declares the same. These are
  configured ceilings, not observed usage, and must be reduced or justified
  against the selected PostgreSQL connection budget.
- User and chat startup use machine ID `1`; payment uses `3`. Replica-safe ID
  allocation must be resolved before horizontal scaling.

## Target architecture

| Layer | Initial plan | Boundary / rationale |
| --- | --- | --- |
| Application cluster | One EC2 K3s server running Argo CD, ingress, API deployments, and frontend static-web deployments | Deliberately non-HA for dev; must recover after reboot |
| Stateful data | Separate EC2 data node for PostgreSQL, Redis, one Kafka broker, and Qdrant with persistent gp3 volumes | Keeps state off application pods; each single-node service remains a known SPOF |
| Database decision | PostgreSQL on the data node with external S3 backup and restore verification | Replaces the prior RDS option to fit the USD 50/month target |
| Ingress | Traefik with cert-manager/one coordinated ACME writer | HTTPS after domain/DNS are approved; raw data-service protocols remain private, while purpose-built admin UIs may use authenticated `/admin/` routes |
| Delivery | GitHub Actions builds ECR images using OIDC, then opens a GitOps image-update PR; Argo CD syncs merged Git | Immutable SHA/digest tags; no `latest` deployments |
| Configuration / secrets | Non-secret config in Kustomize ConfigMaps; secrets from an approved secret mechanism | Never commit credentials; frontend values are build-time values |
| Observability | Prometheus, Grafana, Loki, Grafana Alloy, and Pyroscope in K3s; logs, metrics, and profiles have bounded retention | Grafana is the protected `/admin/logging` operational UI; Pyroscope is private and only enabled per service with runtime flags |
| Backup | EBS/S3 and database backup, with restore drills | A volume is not a backup |

### Runtime configuration standard (approved; rollout pending)

AWS Systems Manager Parameter Store is the operational source of development
runtime configuration. The shared naming contract is:

```text
/courier/<environment>/<service>/runtime/<ENV_VAR_NAME>
```

External Secrets Operator (ESO) mirrors each service prefix into a
service-scoped Kubernetes Secret; a small init container renders nested YAML
where environment variables cannot represent arrays or maps; Reloader rolls
the workload after a synchronized Secret changes. The Application EC2 role is
restricted to `/courier/dev/*`; a production environment must use a separate
role and prefix. SOPS remains only for bootstrap and not-yet-migrated base
configuration during the transition. See
[AWS Parameter Store Runtime Configuration](devops/aws-parameter-store-runtime-config.md).

### P2 sizing and cost decisions (2026-10-16)

The following decisions are agreed for the initial development environment.
They are a cost-constrained baseline, not a capacity guarantee; runtime
measurements on EC2 remain required before scaling.

| Component | Decision |
| --- | --- |
| Region | `ap-southeast-2` (Sydney); selected because the Organization SCP already permits it |
| Operating schedule | Start the two EC2 instances for development work and stop them afterward; planning baseline is 120 instance-hours/month each (4 hours/day × 30 days) |
| Application EC2 | `t4g.large` (2 vCPU, 8 GiB): K3s, Traefik, Argo CD, four backend services, two static frontends, and a compact Prometheus/Grafana setup |
| Data EC2 | `t4g.medium` (2 vCPU, 4 GiB): PostgreSQL, Redis, one Kafka broker, and Qdrant |
| EBS | gp3: 25 GiB application root, 25 GiB data root, and 60 GiB data volume (110 GiB total) |
| Object storage | Two S3 buckets: one for files and one for backups |
| Public boundary | HTTPS only; databases and data-service protocols remain private. The Argo CD dashboard and Grafana dashboard are explicitly authenticated operational UIs at `https://courier.io.vn/admin/argocd` and `https://courier.io.vn/admin/logging`; both use Traefik Basic Auth, while Grafana additionally requires its own login. |
| Cost guardrails | AWS Budget alerts at USD 25, 40, and 47; disk-usage alerts at 70% and 85%; short log retention and backup lifecycle transitions |

The current compute estimate is USD 10.18/month for the application node and
USD 5.09/month for the data node. At the selected 110 GiB gp3 baseline, EBS is
estimated at USD 10.56/month. These estimates assume no NAT Gateway and do not
make stopped EBS volumes, public IPv4 addresses, S3 objects, or logs free.
The working all-in target is approximately USD 47/month with a hard operating
budget of USD 50/month. Network egress, logs, and backup growth must be watched
because the remaining buffer is small.

## Network, DNS, and security plan

- `courier.io.vn` is the selected development domain and ZoneDNS is its
  authoritative DNS provider. The initial frontend routes are
  `/conversa/` and `/flikk/`; the Application EC2 Elastic IP is the only DNS
  target. See [the public endpoint runbook](devops/courier-io-vn.md).
- Public access is limited to the HTTPS frontends, required APIs, and validated
  webhooks. PostgreSQL, Redis, Kafka, Qdrant, Argo CD, Grafana, and pprof stay
  private or are accessed through a controlled tunnel/VPN.
- Before OAuth/SSO/webhook acceptance: configure exact CORS origins, trusted
  proxy settings, callback allowlists, PKCE/state validation, Secure/HttpOnly/
  SameSite cookies, and no token-bearing WebSocket query values in access logs.
- Use separate least-privilege IAM roles for GitHub OIDC image publishing and
  Argo CD repository read access. Terraform owns AWS; Argo CD owns Kubernetes
  resources.

### AWS dev observability (implemented; validation pending)

The GitOps overlay `k8s/overlays/dev/observability` deploys Prometheus, Loki,
Grafana Alloy, and Grafana to `courier-observability`. Grafana is exposed only
through the protected `/admin/logging` route; Prometheus and Loki are
ClusterIP-only. Logs are collected from the four initial backend services, and
metrics are scraped only from the verified `user-service` (port `8001`) and
`chat-service` (port `8002`) endpoints. Payment Gateway and Agent Gateway are
log-only until their metrics endpoints are implemented and verified.

The stack uses 7-day Prometheus and Loki retention and requests 8 GiB across
three gp3-backed PVCs. Its CPU, memory, and storage figures are planning
assumptions; actual EC2 measurements, scrape health, and disk growth remain
pending after the Application is synchronized. Operations are documented in
[AWS Dev Observability](devops/aws-observability.md).

## Delivery, migration, and rollback rules

1. A pull request runs repository-local lint/test/build checks.
2. A merge to `main` builds the exact commit, pushes an immutable ECR tag or
   digest using GitHub OIDC, and opens a GitOps update PR.
3. After the GitOps PR is merged, Argo CD reconciles the Kustomize overlay.
4. Migrations run once, serially, from the matching `shared/migrations`
   revision, under a lock. Application startup must not race on shared
   migrations.
5. Use expand/contract migrations. An image rollback does not automatically
   roll back schema or data.
6. A rollout requires readiness, bounded startup/liveness behavior, smoke
   tests, and a Git revert path to the prior image.

## P0 — inventory, clean builds, and measurement

### Completed in this iteration

- Read all existing repository instructions: only this repository currently
  contains an `AGENTS.md` in the reviewed Courier workspace.
- Reviewed the specified seven repository `main` branches without treating
  dirty local worktrees or feature branches as `main` evidence.
- Recorded build and dependency evidence above from isolated `git archive`
  snapshots.
- Identified configuration surfaces and secret categories: database DSNs,
  Redis, Kafka, OAuth, SMTP/Slack/Loki, SePay, Qdrant, and AI-provider keys.
- Confirmed local Docker daemon access is unavailable in the present execution
  environment. Local image builds and runtime profiling were not run; runtime
  profiling is intentionally deferred to EC2.

### Still required before selecting AWS sizes

| Measurement | Method | Status |
| --- | --- | --- |
| Idle CPU/RAM per service and shared platform | Sample process/container RSS, CPU, and goroutines after warm-up on the initial EC2 environment | Deferred to EC2 by decision |
| Load CPU/RAM, latency, error rate | Run incremental authenticated API/WSS/chat/payment scenarios on EC2; record p50/p95/p99, CPU, RSS, DB connections, Redis memory, Kafka lag, and Qdrant memory | Deferred to EC2 by decision |
| Disk growth | Record PostgreSQL/Kafka/Qdrant volume growth, image sizes, Prometheus/Loki/tracing retention, and backup sizes on EC2 | Deferred to EC2 by decision |
| Connection budgets | Capture observed PostgreSQL and Redis connections on EC2 while all services are live; set pools/requests/limits accordingly | Deferred to EC2 by decision |
| Image build/runtime | Build each production image for the chosen architecture, scan its size, run as non-root where appropriate, and execute health probes | Blocked locally by Docker daemon access and missing Dockerfiles |
| AWS estimate | Enter final measured sizes and final region into AWS Pricing Calculator; compare gross usage to the USD 100/month target | Not started; no AWS resource created |

P0 does **not** approve provisioning. It produces the evidence needed for the
P1 fixes and then a costed P2 decision.

### P1 configuration order (agreed)

Proceed before EC2 sizing with non-secret development configuration for the
four backend services: user-service, chat-service, payment-gateway, and
agent-gateway. The work must make service-to-service names, ports, external
endpoints, ConfigMap values, and required secret keys explicit without placing
secret values in Git. Runtime requests/limits remain provisional until the EC2
measurements are collected.

#### Backend configuration contract

| Service | Verified application ports | In-cluster dependency names | Secret inputs that must stay out of Git | P1 implementation note |
| --- | --- | --- | --- | --- |
| user-service | HTTP `5001`, gRPC `6001`, health `7001`, metrics `8001` | PostgreSQL, `redis:6379`, `kafka:9092` | PostgreSQL DSN, Redis password, OAuth client credentials, SMTP/Slack credentials | Render or mount a full dev config file; the existing Kubernetes deployment declares `5000`/`5001`, which conflicts with its checked-in dev configuration. |
| chat-service | HTTP `5002`, gRPC `6002`, health `7002`, metrics `8002` | PostgreSQL, `redis:6379`, `kafka:9092`, `user-service:6001` | PostgreSQL DSN, Redis password | Add its image and manifest, then mount a full dev config file. Kafka producer code that hard-codes `localhost:9092` must be switched to configuration. |
| payment-gateway | HTTP `5003`, gRPC `6003`, health `5103` | PostgreSQL, `redis:6379`, `kafka:9092`, `user-service:6001` | PostgreSQL DSN, Redis password, SePay merchant/secret/webhook values | Its loader expands configured environment-variable placeholders; create an image and mount config plus a secret reference. |
| agent-gateway | HTTP `5010` | `qdrant:6333`, `kafka:9092` | Qdrant API key, AI-provider API key | Its loader has explicit environment overrides; create config/secret references and retain concurrency/timeouts as provisional values. |

Do not rely on a bare `envFrom` ConfigMap to override user/chat nested YAML
settings: their current Viper-based loading unmarshals the file configuration
and does not bind each environment key. P1 must either mount a rendered config
file plus an approved secret source, or change and test the loaders to bind the
documented environment variables. This is a verified implementation constraint,
not an assumption.

## Sequenced implementation plan

### P1 — source and build readiness

#### Current implementation status (2026-10-15)

- **Verified — user-service clean-build baseline:** its isolated P1 branch pins
  `github.com/vucongthanh92/courier/shared` to
  `v0.0.0-20261011113145-43c7030c3c51`, removes the local `replace`, ignores
  `vendor/`, and removes the tracked vendor tree. `go mod verify` and
  `go test -mod=readonly ./...` pass without a sibling checkout.
- **Verified — health/config contract:** the dev deployment now exposes HTTP
  `5001`, gRPC `6001`, health `7001`, and metrics `8001`; mounts the complete
  `config.yaml` from the manually provisioned `user-service-config` Secret;
  and uses `/live` for startup/liveness and `/ready` for readiness. Readiness
  now includes asynchronous read/write database pings.
- **Verified — deployment tag policy:** the base manifest no longer declares
  `latest`; the dev overlay supplies the temporary `dev` tag. CI-to-ECR/Argo
  CD must replace it with an immutable commit-SHA digest before a real deploy.
- **Not yet verified:** no Docker image was built locally because the Docker
  daemon is unavailable; no Kubernetes cluster, AWS resource, domain, or
  secret value has been created.
- **Verified — chat-service clean-build baseline:** its isolated P1 branch
  likewise removes the local shared-module `replace` and tracked `vendor/`,
  adds CI and a multi-stage Dockerfile, routes Kafka fallback to `kafka:9092`,
  and starts `/live` plus database-backed `/ready` health endpoints. `go mod
  verify`, `go test -mod=readonly ./...`, and `go build -mod=readonly ./...`
  pass. Its dev Kustomize overlay follows the same complete-config Secret
  mount model as user-service.

#### P1 source-readiness closure record (2026-10-15)

The source/build portion of P1 is complete for the six deployable application
repositories. The following is verified from GitHub, rather than inferred from
local worktrees: each P1 pull request was merged, and the most recent `CI`
workflow triggered by the resulting push to `main` completed successfully.

| Repository | Merged P1 pull request | Verified CI result on `main` | P1 result |
| --- | --- | --- | --- |
| `courier-user-svc` | [#4](https://github.com/vucongthanh92/courier-user-svc/pull/4) | [successful run](https://github.com/vucongthanh92/courier-user-svc/actions/runs/38705667421) | Clean Go dependency resolution, image build definition, CI, and health/config contract |
| `courier-chat-svc` | [#4](https://github.com/vucongthanh92/courier-chat-svc/pull/4) | [successful run](https://github.com/vucongthanh92/courier-chat-svc/actions/runs/38710826544) | Clean Go dependency resolution, image build definition, CI, and health/config contract |
| `courier-payment-gateway` | [#1](https://github.com/vucongthanh92/courier-payment-gateway/pull/1) | [successful run](https://github.com/vucongthanh92/courier-payment-gateway/actions/runs/38709108284) | Clean Go dependency resolution, image build definition, CI, and health/config contract |
| `courier-agent-gateway` | [#1](https://github.com/vucongthanh92/courier-agent-gateway/pull/1) | [successful run](https://github.com/vucongthanh92/courier-agent-gateway/actions/runs/38711265380) | Clean Go dependency resolution, image build definition, and CI |
| `courier-conversa-app` | [#1](https://github.com/vucongthanh92/courier-conversa-app/pull/1) | [successful run](https://github.com/vucongthanh92/courier-conversa-app/actions/runs/38747384166) | Reproducible pnpm build, container build, and CI; workspace settings permit `esbuild` in both CI and Docker builds |
| `courier-flikk-app` | [#1](https://github.com/vucongthanh92/courier-flikk-app/pull/1) | [successful run](https://github.com/vucongthanh92/courier-flikk-app/actions/runs/38747829784) | Reproducible pnpm build, container build, and CI; workspace settings permit `esbuild` in both CI and Docker builds |

The initial failed frontend CI attempts are superseded by the successful runs
above. Their root causes and permanent fixes were: valid block-form YAML for
the Docker tag, `pnpm/action-setup` before `setup-node` cache initialization,
a root package declaration in `pnpm-workspace.yaml`, and copying that workspace
file before Docker's dependency-install layer.

This closure record does **not** claim that the applications run on Kubernetes
or AWS. No ECR registry, AWS resource, domain, production secret, Kubernetes
cluster, or live image deployment has been created. The existing Kustomize
config-file Secret mount has been prepared for user, chat, and payment only;
agent and frontend deployment manifests, image publishing, GitOps promotion,
runtime sizing, and AWS cost approval are subsequent work.

1. Pin the shared Go module for clean CI builds; retain `go.work` only as an
   optional developer convenience.
2. Add production Dockerfiles for chat, payment, Conversa, and Flikk; update
   existing Dockerfiles for pinned bases, compatible target architecture, and
   non-root execution where practical.
3. Move all deploy-time endpoints/secrets to the approved configuration model;
   make frontend public values explicit at build time.
4. Make machine ID assignment replica-safe and ensure graceful shutdown/
   connection draining.
5. Add app manifests with HTTP health semantics, startup/readiness/liveness
   probes, requests/limits, and immutable images.

### P2–P7 — infrastructure and acceptance

- **P2:** Terraform for IAM/MFA, VPC/security groups, EC2/EBS/ECR/S3, billing
  alerts, and the chosen database; only after a regional estimate is approved.
- **P3:** K3s, PostgreSQL/migration ownership, persistent Redis/Kafka/Qdrant,
  ingress, TLS, backup/restore drill.
- **P4:** user-service plus both frontends; prove cross-app SSO under the real
  HTTPS domain.
- **P5:** chat Redis fanout/WSS reconnect and SePay sandbox idempotency tests.
- **P6:** agent Kafka/Qdrant/AI controls plus metrics/logs/traces.
- **P7:** GitOps for every app, rollback, controlled node reboot/restore, and
  scaling exercises.

### P2 execution record (2026-10-16 to 2026-10-23)

- **Verified:** the Terraform remote-state bucket
  `courier-dev-tfstate-016170038458-ap-southeast-2` and DynamoDB lock table
  `courier-dev-terraform-lock` were created in Sydney. The bucket is the
  shared Terraform state store; the table prevents concurrent Terraform
  changes. Neither stores Courier application data or secrets.
- **Verified:** after the required IAM permission was granted, the reviewed
  runtime Terraform apply completed. It created the agreed VPC, two ARM64 EC2
  instances, 110 GiB of encrypted gp3, ECR repositories, the files and backup
  S3 buckets, SSM/IAM roles, and budget/disk alerts in `ap-southeast-2`.
- **Verified:** Application EC2 is `t4g.large` and Data EC2 is `t4g.medium`.
  Both use stable private addresses in the Courier VPC and can be stopped and
  started through EC2 to control compute cost. Their public IPv4 addresses are
  expected to change after a stop/start cycle and are never deployment
  configuration.
- **Verified:** the Terraform state backend and DynamoDB lock table remain in
  use. Terraform currently emits a deprecation warning for its
  `dynamodb_table` backend setting; this is a future backend-maintenance task,
  not a deployment failure.

#### K3s network correction

The initial Application EC2 bootstrap exposed a configuration collision:
Courier's VPC is `10.42.0.0/16`, which overlaps K3s's default pod CIDR
`10.42.0.0/16`. This prevents pod-to-Service-IP traffic, including the
Kubernetes API service used by metrics-server. The corrected K3s configuration
uses `10.244.0.0/16` for pods and `10.245.0.0/16` for services, installs the
required `iptables-nft`/`nftables` utilities before K3s, and disables EC2
source/destination checking on the application node. Replacing the Application
EC2 is safe before application workloads or secrets are installed; the Data
EC2 and its persistent volume remain intact.

**Verified after replacement:** the Application K3s node is `Ready`; CoreDNS,
metrics-server, and Traefik are `Running`; `kubectl top nodes` works. The
default Kubernetes Service endpoint is in `10.245.0.0/16`, confirming that
the service network no longer collides with the Courier VPC.

### P3 GitOps bootstrap (in progress)

- **Prepared, not yet applied:** the repository pins Argo CD `v3.5.6` for the
  non-HA AWS development control plane. It is installed as a `ClusterIP`
  service and accessed only through an SSM tunnel; no Argo CD Security Group
  ingress rule or Traefik route is planned.
- **Not yet deployed:** Argo CD repository credentials, SOPS keys and
  encrypted application secrets, ECR pull authentication for K3s, data-node
  workloads, and Courier application manifests/images. No application secret
  values have been placed in Git or provisioned to AWS.

## Acceptance gates

No phase may claim production-grade HA. The required AWS-dev gates are:

- Cross-frontend SSO works through HTTPS with direct-entry callback, expiry,
  logout, and invalid-state coverage.
- Chat survives a rolling deployment with reconnect/backoff, missed-message
  recovery, deduplication, and Redis fanout across replicas.
- Payment webhook delivery is signature/timestamp checked and idempotent under
  duplicate/concurrent events and transaction failures.
- Deployments do not route to unready pods; rollback, pod loss, controlled
  reboot, and a backup restore have documented, tested runbooks.

## Explicit non-actions

The completed P2 work created the reviewed AWS dev resources described above.
It did not purchase a domain or write application credentials into the
repository.
