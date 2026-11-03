# Kafka admin dashboard

## Purpose

Kafka UI provides a browser view of Courier development topics, consumer
groups, offsets, and message payloads. It is a diagnostic tool for checking
event publication and consumption; it is not an application dependency.

The dashboard is available at:

```text
https://courier.io.vn/admin/kafka
```

The `/admin/` path is reserved for future protected operational UIs. It does
not make a database, cache, or broker protocol public.

## Security boundary

Kafka remains private on Data EC2 port `9092`. Kafka UI runs as a K3s workload
on Application EC2, reaches the broker through the private `kafka:9092`
Service, and is exposed only by the existing HTTPS Traefik entry point.

Traefik requires Basic Auth before forwarding any request. Its `htpasswd`
bcrypt entry is an AWS SSM `SecureString` and is synchronized by External
Secrets Operator; neither the password nor its hash is committed to Git.

```text
Browser
  -> HTTPS + Basic Auth at courier.io.vn/admin/kafka
  -> Traefik
  -> kafka-ui Service in K3s
  -> kafka:9092 private Data EC2 broker
```

## Initial setup and credential rotation

Before applying the public route, create the credential from a workstation:

```bash
AWS_PROFILE=courier-terraform make update-kafka-admin-basic-auth
```

The command asks for the dashboard username and password, stores only the
bcrypt `htpasswd` result under
`/courier/dev/admin-kafka/runtime/BASIC_AUTH_USERS`, and prints neither value.

The ExternalSecret refreshes every 15 minutes. To rotate the credential, run
the same command, wait for the refresh, then use the new credentials in the
browser. Do not manually edit the generated Kubernetes Secret because ESO owns
it.

## GitOps rollout

After the credential exists and this change is merged, apply the new Argo CD
Application once from Application EC2. Argo CD then keeps the UI reconciled
from `main`.

```bash
sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  apply -n argocd -f \
  https://raw.githubusercontent.com/vucongthanh92/courier-common/main/argocd/applications/kafka-ui-dev.yaml
```

The existing `public-ingress-dev` Application reconciles the protected route
and ExternalSecret from the same merge. Verify:

```bash
sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n courier-dev get externalsecret kafka-admin-basic-auth
sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n courier-dev get deployment,pod,service -l app=kafka-ui
sudo docker exec courier-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --list
```

An unauthenticated request to `/admin/kafka` must return HTTP `401`; an
authenticated request must display the Kafka UI and the declared Courier
topics. Do not inspect or paste event payloads containing personal data into
issues, pull requests, or logs.

## Topic bootstrap

Kafka automatic topic creation remains disabled. The Data EC2
`courier-data.service` runs the idempotent topic initializer after every start,
using `infra/data-node/topics.json` as the desired topic list. This repairs a
missing declared topic but does not modify an already-created topic's
partitions, replication factor, retention, or message data.

Courier uses event-specific topics for cross-service events. For example,
`user.email_verified.v1` is published only to
`courier.user.email-verified.v1`; consumers do not need to filter unrelated
user events from a shared user-topic stream.
