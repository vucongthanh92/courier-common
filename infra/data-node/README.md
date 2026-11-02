# Courier Data EC2 stack

This directory defines the private, single-node development data plane:
PostgreSQL, Redis, Kafka in KRaft mode, and Qdrant. It is intentionally not a
Kubernetes workload: persistent state remains on Data EC2's `/data` EBS volume.

## Security model

- Secrets are four AWS SSM SecureString parameters below `/courier/dev/data`.
  They are read by the Data EC2 role only, written to `/etc/courier/data.env`
  with mode `0600`, and never committed here.
- The Docker host ports are reachable only from the Application security group.
  Data EC2 has no public inbound security-group rule.
- PostgreSQL uses SCRAM authentication. Redis requires a password. Qdrant
  requires an API key. Kafka is plaintext because it is a private development
  network; it must not be exposed publicly.

## Capacity baseline

The Compose memory ceilings total 3,072 MiB: PostgreSQL 768 MiB, Redis 256 MiB,
Kafka 1,280 MiB, and Qdrant 768 MiB. This leaves about 1 GiB for Amazon Linux,
Docker, filesystem cache, and bursts on the 4 GiB `t4g.medium` Data EC2.

Kafka UI deliberately runs on the Application EC2 Kubernetes node rather than
this Data EC2. It reaches the broker through the private `kafka:9092` service
and is routed through Traefik with authentication. This preserves the Data
EC2's limited memory for stateful workloads.

This is a **decision pending measurement**, not a verified runtime result.
Kafka is the largest risk; do not increase a ceiling without recording EC2
memory, CPU, disk growth, and consumer lag under an actual Courier workload.

## Kafka topic bootstrap

`courier-data.service` starts only persistent containers. After Kafka reports
healthy, its `ExecStartPost` runs `initialize-kafka-topics.sh`, which invokes
the one-shot `kafka-init` Compose service. Topic creation is idempotent via
`--if-not-exists`, so every service restart also repairs missing declared
topics without deleting messages or changing existing topic settings.

Declared topics live in `topics.json`. Add a reviewed topic there before a
service publishes or consumes it; do not rely on Kafka automatic topic
creation, which is intentionally disabled.

## First provision after Terraform applies the IAM policy

Run the following from an administrator profile. It creates values locally in
shell variables and sends them directly to Parameter Store; it never prints the
secret values. Run it only once for a fresh data plane. Replacing a value after
PostgreSQL's first initialization does not change its database password.

```bash
set -euo pipefail
generate_parameter() {
  local name="$1"
  local value
  value="$(openssl rand -base64 48 | tr -d '\n')"
  aws ssm put-parameter \
    --region ap-southeast-2 \
    --profile courier-terraform \
    --name "/courier/dev/data/${name}" \
    --type SecureString \
    --value "$value" \
    --overwrite \
    --no-cli-pager >/dev/null
}
generate_parameter postgres-admin-password
generate_parameter courier-app-password
generate_parameter redis-password
generate_parameter qdrant-api-key
```

After this branch is merged, set `COURIER_REF` to that merge commit. Use SSM to
download that exact source archive, install the files, and start the stack:

```bash
COURIER_REF=<merged-commit-sha>
aws ssm send-command \
  --region ap-southeast-2 \
  --profile courier-terraform \
  --instance-ids i-0959faf3ee5a35835 \
  --document-name AWS-RunShellScript \
  --comment 'Install Courier Data EC2 stack' \
  --parameters "commands=[\"set -euo pipefail\",\"workdir=\\$(mktemp -d)\",\"trap 'rm -rf \\\\$workdir' EXIT\",\"curl --fail --location --silent --show-error https://github.com/vucongthanh92/courier/archive/\\${COURIER_REF}.tar.gz --output \\\\$workdir/courier.tar.gz\",\"tar --extract --gzip --file \\\\$workdir/courier.tar.gz --directory \\\\$workdir\",\"sudo \\\\$workdir/courier-\\${COURIER_REF}/infra/data-node/scripts/install-data-node.sh --start\"]"
```

Use `aws ssm get-command-invocation` to inspect status, then verify only
container metadata and health states. Do not run `docker inspect` on a container
with its full output because environment variables contain secrets.

## Recovery and backup

`courier-postgres-backup.timer` runs a `pg_dumpall` backup daily with a small
random delay. It writes a temporary compressed file below `/data/backups` and
uploads it to the pre-provisioned backups S3 bucket using the Data EC2 IAM role.
S3 versioning/lifecycle remains Terraform-owned. A stopped EC2 does not run the
timer; `Persistent=true` causes one missed timer execution to run after the
machine next starts.

The backup is a recovery foundation, not proof of recovery. Before treating the
stack as accepted, restore one backup into a disposable PostgreSQL instance and
record the result in issue #96.
