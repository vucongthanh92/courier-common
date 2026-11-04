# AWS Dev Observability

## Purpose and boundary

The AWS development environment runs a small, Kubernetes-native observability
stack in the `courier-observability` namespace:

```text
Courier backend Pods (courier-dev)
        |                         |
        | /metrics                | Kubernetes Pod log API
        v                         v
  Prometheus                 Grafana Alloy
        |                         |
        |                         v
        +--------------------> Loki
                  |              |
                  +------> Grafana <------ Traefik Basic Auth
                                  |
                                  v
                 https://courier.io.vn/admin/logging
```

Grafana is the only public component. Prometheus and Loki remain `ClusterIP`
services. The route has two independent login layers: Traefik Basic Auth first,
then Grafana's own administrator login. This is intentionally consistent with
the existing Argo CD operational dashboard.

## Components

| Component | Responsibility | Retention / persistent storage |
| --- | --- | --- |
| Prometheus | Scrapes opted-in backend metrics | 7 days; 2 GiB PVC |
| Loki | Stores backend container logs | 7 days; 5 GiB PVC |
| Grafana Alloy | Reads selected Pod logs through the Kubernetes API and sends them to Loki | no persistent data |
| Grafana | Queries Prometheus and Loki | 1 GiB PVC |

All image versions and resources are committed in
`k8s/overlays/dev/observability`. The three PVCs total 8 GiB. The CPU/memory
requests and limits are a **provisional sizing assumption**, not an EC2
measurement; review them after workload has run on the Application EC2.

The previous `tracing-service` Docker Compose stack is retired for AWS dev and
is not an operational dependency. Grafana Alloy is used instead of Promtail:
Promtail reached end of life on 2026-03-02, and Alloy can tail Kubernetes logs
through the Kubernetes API without a privileged host filesystem mount.

## What is collected now

All four initial backend deployments have the label
`observability.courier.io/logs: "true"`, so Alloy collects their container logs:

- `user-service`
- `chat-service`
- `payment-gateway`
- `agent-gateway`

Alloy adds only bounded, useful labels: `environment=dev`, `namespace`,
`service_name`, and `container`. Never add user IDs, request IDs, access tokens,
or dynamic URLs as Loki labels.

Metrics opt-in is intentionally separate. Prometheus discovers only Services
labeled `observability.courier.io/metrics: "true"` and only their named
`metrics` port. Initial verified targets are:

| Service | Metrics port | Status |
| --- | --- | --- |
| user-service | `8001` | verified from the dev configuration and exposed by the Service |
| chat-service | `8002` | verified from the service configuration and exposed by the Service |
| payment-gateway | — | logs only; metrics endpoint not yet verified |
| agent-gateway | — | logs only; metrics endpoint not yet verified |

When a future service has a verified `/metrics` endpoint, add the named service
port and the metrics label. Do not label an unverified port merely to make it
appear in Prometheus.

## Credentials and deployment

The dashboard has two `SecureString` parameters in AWS Systems Manager Parameter
Store:

```text
/courier/dev/admin-logging/runtime/BASIC_AUTH_USERS
/courier/dev/admin-logging/runtime/GRAFANA_ADMIN_PASSWORD
```

Create both before the first Grafana deployment; the command does not print
passwords or the generated bcrypt hash:

```bash
AWS_PROFILE=courier-terraform make update-logging-dashboard-credentials
```

External Secrets Operator mirrors them into the
`logging-dashboard-credentials` Kubernetes Secret every 15 minutes. After this
branch is merged to `main`, bootstrap its Argo CD Application:

```bash
AWS_PROFILE=courier-terraform make enable-observability
```

Argo CD then owns the whole stack. Verify the `observability-dev` Application
is `Synced` and `Healthy`, then open
`https://courier.io.vn/admin/logging`.

## Initial validation

1. Sign in at the protected dashboard route with the Traefik credential, then
   sign in to Grafana with user `admin` and the Grafana administrator password.
2. In **Connections → Data sources**, verify Prometheus and Loki are healthy.
3. In **Explore**, select Loki and query `{environment="dev"}`. Filter with
   `service_name="user-service"` or another backend service.
4. In **Explore**, select Prometheus and query `up{job="courier-backends"}`.
   `user-service` and `chat-service` should be `1` after their next scrape.
5. Inspect PVC use and resource consumption before changing retention or adding
   more scrape targets.

## Operations and rollback

- Rotate the Traefik Basic Auth credential in Parameter Store; ESO refreshes it
  without storing the value in Git. Grafana reads `GF_SECURITY_ADMIN_PASSWORD`
  only when it creates a new administrator database. Change an existing
  Grafana administrator password in Grafana itself, then update Parameter
  Store as the recovery record; do not expect a Pod restart to reset it.
- To stop collection temporarily, remove the labels or disable the Argo CD
  Application. Do not expose Prometheus or Loki publicly for troubleshooting.
- A Git revert removes the Argo-managed workloads. PVC deletion is deliberately
  a separate, explicit operation because it destroys retained metrics/logs.

## References

- [Grafana Alloy: Kubernetes log source](https://grafana.com/docs/grafana-cloud/send-data/alloy/reference/components/loki/loki.source.kubernetes/)
- [Grafana Loki: Promtail deprecation and Alloy migration](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [Grafana Loki filesystem storage](https://grafana.com/docs/loki/latest/operations/storage/filesystem/)
