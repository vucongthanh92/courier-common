# AWS Dev Continuous Profiling

## Purpose

Continuous profiling helps diagnose CPU saturation, allocation pressure,
goroutine growth, mutex contention, and blocked execution in the four Go
backends without exposing Go's `/debug/pprof` endpoints publicly.

The dev implementation uses the **Pyroscope Go SDK push model**. It is separate
from log collection and does not alter application API traffic.

```text
user/chat/payment/agent Pod
  | Pyroscope Go SDK, only when PROFILING_ENABLED=true
  | private HTTP in K3s
  v
Pyroscope (courier-observability, ClusterIP, 3-day retention, PVC)
  ^
  | Grafana datasource
Grafana Profile Drilldown
  |
https://courier.io.vn/admin/logging
```

Pyroscope has no Traefik route, public hostname, or load balancer. Grafana is
the only browser UI and retains the existing Basic Auth plus Grafana login
protection.

## Runtime configuration

Each backend reads two environment variables. Source defaults to **disabled**,
so local execution and environments that omit the values do not profile.

| Parameter Store name | Kubernetes environment variable | Meaning |
| --- | --- | --- |
| `/courier/dev/<service>/runtime/PROFILING_ENABLED` | `PROFILING_ENABLED` | Literal `true` enables SDK profiling; `false` disables it. |
| `/courier/dev/<service>/runtime/PROFILING_SERVER_ADDRESS` | `PROFILING_SERVER_ADDRESS` | Private in-cluster Pyroscope URL. |

`<service>` is one of `user-service`, `chat-service`, `payment-gateway`, or
`agent-gateway`. They are ordinary `String` parameters, not credentials. They
still live in Parameter Store so that all dev runtime configuration has one
consistent owner and External Secrets Operator can update Pods safely.

After this GitOps change and the service image changes have reached `main`,
write the initial dev values from `courier-common`:

```bash
AWS_PROFILE=courier-terraform make configure-continuous-profiling
```

That command enables all four services. To stop profile collection without a
code/image change:

```bash
AWS_PROFILE=courier-terraform PROFILING_ENABLED=false make configure-continuous-profiling
```

ESO polls on a 15-minute interval. Reloader restarts the matching Deployment
after its Kubernetes Secret changes; an Argo CD restart can be used when an
immediate rollout is needed. Never put user IDs, emails, tokens, request IDs, URLs containing IDs,
or message content in profiling labels.

## What is collected

When enabled, the SDK sends bounded labels only:

- `service_name`
- `environment`

It collects CPU, allocation object/space, and in-use object/space profiles.
Request-level tags are intentionally excluded because high-cardinality labels
would increase storage and could expose personal or secret data.

## Operating Grafana

1. Visit `https://courier.io.vn/admin/logging` and complete both login layers.
2. Open **Drilldown → Profiles** (or **Explore → Pyroscope**).
3. Select a service and a recent time range, then start with the CPU flame
   graph. Compare two time ranges when investigating a regression.
4. Review allocation/in-use profiles next. An allocation-heavy profile is not
   automatically a leak; compare in-use space and goroutines before acting.

The profiles do not replace Prometheus. Use Prometheus for CPU/memory trends,
and Pyroscope to explain where the Go process spent CPU or allocated memory.

## Capacity and retention

The K3s manifest pins `grafana/pyroscope:2.4.3`, uses a 5 GiB local PVC, and
retains profiles for 3 days. It requests `100m` CPU and `256Mi` memory, with
limits of `500m` and `768Mi`.

These values are **assumptions**, not measured workload requirements. Pyroscope
single-node filesystem storage is appropriate only for the current one-node dev
cluster. Measure its PVC growth and Application EC2 pressure after real
traffic; do not copy this storage mode to a production multi-node deployment.

## Validation after deployment

1. Argo CD reports `observability-dev` Healthy and the `pyroscope` Pod Ready.
2. The four runtime ExternalSecrets show `SecretSynced` after the parameters
   exist.
3. Trigger a small amount of traffic for one enabled service.
4. In Grafana, find that service under the Pyroscope datasource and open a
   profile.
5. Confirm `https://courier.io.vn/debug/pprof/` and any Pyroscope hostname are
   unavailable; no profiling endpoint must be public.

## References

- [Grafana Pyroscope](https://grafana.com/docs/pyroscope/latest/)
- [Pyroscope Go SDK](https://github.com/grafana/pyroscope-go)
- [Grafana Pyroscope datasource](https://grafana.com/docs/grafana/latest/datasources/pyroscope/)
