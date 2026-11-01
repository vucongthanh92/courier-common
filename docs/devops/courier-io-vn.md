# `courier.io.vn` public endpoint runbook

## Purpose and boundary

`courier.io.vn` is Courier's development public hostname. Its apex will serve
the two static frontend paths:

- `https://courier.io.vn/conversa/`
- `https://courier.io.vn/flikk/`

The Application EC2 is the only internet-facing node. Argo CD, Grafana,
PostgreSQL, Redis, Kafka, and Qdrant remain private and are accessed through
controlled SSM tunnels where required.

## Stable address

Terraform owns the Application Elastic IP. This prevents a stop/start cycle
from changing the DNS target. After Terraform has been applied, obtain the
authoritative value:

```bash
AWS_PROFILE=courier-terraform terraform -chdir=infra/terraform/aws-dev output -raw application_ingress_ip
```

Do not use:

- an EC2 instance's normal public IP, because it can change after stop/start;
- `42.117.138.104`, which is not the Courier Application EC2 ingress address.

## ZoneDNS records

Once `application_ingress_ip` is available, create or update these records in
ZoneDNS:

| Type | Host | Value | TTL |
| --- | --- | --- | --- |
| `A` | `@` | exact `application_ingress_ip` Terraform output | `300` |
| `CNAME` | `www` (optional) | `courier.io.vn` | `300` |

ZoneDNS remains the authoritative DNS provider. Do not move name servers or
create a duplicate Route 53 hosted zone for this domain.

## Rollout order

1. Merge and apply the Terraform change that reserves the Elastic IP.
2. Set the ZoneDNS apex `A` record to `application_ingress_ip`.
3. Wait for DNS propagation and verify it returns the Elastic IP.
4. Configure Traefik entry points and routes for `/conversa/` and `/flikk/`.
5. Issue a TLS certificate after HTTP is reachable for ACME validation.
6. Configure exact OAuth callback URLs and CORS origins only after HTTPS works.

Opening ports 80 and 443 in the AWS security group is necessary for this
sequence, but it does not expose workloads until Traefik is configured to
listen and route traffic.
