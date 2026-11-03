# AWS Parameter Store Runtime Configuration

## Purpose

AWS Systems Manager Parameter Store is the operational source of Courier
runtime configuration. Git contains the configuration structure, deployment
manifests, and parameter names, but never parameter values that are secret.

External Secrets Operator (ESO) periodically mirrors approved Parameter Store
values into Kubernetes Secrets. An init container renders nested YAML fragments
before an application starts. Reloader restarts a workload after a mirrored
Secret or ConfigMap changes so that the new configuration is actually read.

This replaces manual, service-specific `kubectl create secret` synchronization.
SOPS remains supported during the migration for existing full configuration
files and bootstrap-only secrets.

## Naming convention

Every application runtime parameter uses this path:

```text
/courier/<environment>/<service>/runtime/<ENV_VAR_NAME>
```

Examples:

```text
/courier/dev/user-service/runtime/SSO_LOGIN_URL
/courier/dev/user-service/runtime/SSO_CONVERSA_REDIRECT_URI
/courier/dev/user-service/runtime/OAUTH_GOOGLE_CLIENT_SECRET
/courier/dev/chat-service/runtime/COURIER_PUBLIC_ORIGINS
/courier/dev/admin-kafka/runtime/BASIC_AUTH_USERS
```

Use upper-snake-case for `<ENV_VAR_NAME>`, even for a value consumed only by a
YAML renderer. This makes the Parameter Store key, Kubernetes Secret key, and
environment-variable name identical.

Use `String` for non-sensitive values such as URLs, feature flags, client IDs,
and public origins. Use `SecureString` for passwords, private keys, OAuth
client secrets, API keys, and tokens. Do not store a secret in a ConfigMap or
commit it to Git.

## Protected operational dashboards

`/admin/` is reserved for protected operational UIs. The first route is Kafka
UI at `https://courier.io.vn/admin/kafka`. Its Basic Auth credential is stored
as an Apache `htpasswd` bcrypt line in this SecureString:

```text
/courier/dev/admin-kafka/runtime/BASIC_AUTH_USERS
```

Create or rotate it from a workstation without displaying the password or
hash:

```bash
AWS_PROFILE=courier-terraform make update-kafka-admin-basic-auth
```

External Secrets Operator mirrors the parameter into the `users` key of the
`kafka-admin-basic-auth` Kubernetes Secret. Traefik reads that Secret before it
forwards the request. The Kafka broker remains private; this route does not
open port 9092 to the Internet.

Future observability UIs can use a child route below `/admin/` and the same
reverse-proxy/authentication boundary. Do not publish a raw Redis, PostgreSQL,
or Kafka protocol endpoint through `/admin/`; expose only a purpose-built UI
with explicit authentication and a least-privilege backend connection.

Argo CD uses a separate Basic Auth credential because access to GitOps and
cluster operations is more privileged than Kafka inspection:

```text
/courier/dev/admin-argocd/runtime/BASIC_AUTH_USERS
```

Create or rotate it without printing its value:

```bash
AWS_PROFILE=courier-terraform make update-argocd-admin-basic-auth
```

The `argocd-dashboard-dev` Application mirrors this parameter into the
`argocd-admin-basic-auth` Secret in the `argocd` namespace. Traefik uses it
before forwarding `https://courier.io.vn/admin/argocd` to the private
`argocd-server` Service. Argo CD's own login remains a second layer.

## Synchronization model

```text
Parameter Store path
  /courier/dev/user-service/runtime/SSO_LOGIN_URL
                  |
                  v
ExternalSecret (15-minute refresh)
                  |
                  v
user-service-runtime-secrets
                  |
          +-------+--------+
          |                |
          v                v
init container        Reloader restarts Pod
renders config.yaml          |
          |                  v
          +----------> user-service starts with new config
```

`dataFrom.find` discovers all parameters below a service's `runtime` prefix.
The manifest removes the path before creating Secret keys. Adding a new
parameter under the prefix therefore requires no additional one-key mapping in
the manifest, but it still requires a committed YAML template reference if the
application reads the value from nested configuration.

## Initial user-service SSO values

The following non-secret values are required:

| Parameter suffix | Development value |
| --- | --- |
| `SSO_LOGIN_URL` | `https://courier.io.vn/conversa/` |
| `SSO_CONVERSA_CLIENT_ID` | `conversa-web` |
| `SSO_CONVERSA_REDIRECT_URI` | `https://courier.io.vn/conversa/oauth/callback/courier` |
| `SSO_FLIKK_CLIENT_ID` | `flikk-web` |
| `SSO_FLIKK_REDIRECT_URI` | `https://courier.io.vn/flikk/oauth/callback/courier` |

Google OAuth credentials use the same prefix as `SecureString` parameters:

```text
/courier/dev/user-service/runtime/OAUTH_GOOGLE_CLIENT_ID
/courier/dev/user-service/runtime/OAUTH_GOOGLE_CLIENT_SECRET
```

Before applying the new `ExternalSecret`, create or update the required
parameters from a workstation with the Courier AWS profile:

```bash
AWS_PROFILE=courier-terraform make configure-user-service-sso-runtime
```

To make a one-time copy of the existing legacy Google OAuth parameters without
printing them, run:

```bash
AWS_PROFILE=courier-terraform make migrate-user-service-oauth-runtime
```

Thereafter, update the credentials directly in Parameter Store or run:

```bash
AWS_PROFILE=courier-terraform make update-user-service-google-oauth
```

The command does not print values. Values can also be edited in the AWS
Console at **Systems Manager → Parameter Store**. ESO refreshes every 15
minutes; Reloader then performs a rolling restart. For an immediate refresh,
restart the `external-secrets` deployment or annotate the `ExternalSecret`;
do not manually edit the generated Kubernetes Secret because ESO owns it.

The first rollout order is important:

1. Merge the GitOps/Terraform pull request and apply Terraform.
2. Populate the SSO parameters and migrate the existing Google OAuth values.
3. Apply the `external-secrets-dev`, `reloader-dev`, and `runtime-config-dev`
   Argo CD Applications; wait until each is Healthy.
4. Verify `user-service-runtime` has status `SecretSynced`, then allow
   `user-service-dev` to reconcile and become Ready.

This prevents ESO from replacing the existing runtime Secret with an incomplete
one during the migration.

## IAM boundary

The Application EC2 role may read only:

```text
/courier/dev/*
```

This is intentionally a development-only prefix. Production must use a
separate AWS account or role and a distinct `/courier/prod/*` policy; do not
broaden the dev role to every Parameter Store value in the account.

K3s does not provide EKS IRSA. ESO therefore obtains AWS credentials through
the Application EC2 instance role. Treat the node as a privileged boundary and
run only trusted workloads there.

## Adding another service or environment

1. Add parameters below `/courier/<environment>/<service>/runtime/`.
2. Add or reuse an `ExternalSecret` targeting that service's runtime Secret.
3. Reference the required variables in the service's non-secret YAML overlay.
4. Add `reloader.stakater.com/auto: "true"` to the Pod template.
5. Validate that ESO reports `SecretSynced`, then verify the workload rolls
   out and becomes Ready without printing Secret contents.

For a new environment, create a separate `SecretStore`/overlay with its AWS
region and restrict its IAM role to `/courier/<environment>/*`.
