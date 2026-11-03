# Argo CD on AWS development K3s

This runbook installs the non-HA Argo CD control plane on the Courier
Application EC2. `argocd-server` remains a Kubernetes `ClusterIP` Service and
no AWS security-group rule is added. The dashboard is exposed only through the
existing Traefik HTTPS entry point at `/admin/argocd`, protected by Traefik
Basic Auth and then the normal Argo CD login.

The pinned version is `v3.5.6`. Upgrade it only by changing
`infra/argocd/aws-dev/kustomization.yaml` and `bootstrap.sh` in the same
reviewed pull request.

## Prerequisites

- Application EC2 is running and visible as `Online` in Systems Manager.
- AWS CLI uses the `courier-terraform` profile and `ap-southeast-2` region.
- K3s system pods are healthy.

Set the instance ID once for the commands below:

```bash
export AWS_PROFILE=courier-terraform
export AWS_REGION=ap-southeast-2
export APPLICATION_INSTANCE_ID=i-06109722166dede79
```

The instance ID is stable across stop/start cycles. Its public IP is not.

## Install or upgrade the pinned release

Run this through SSM instead of opening SSH. The command downloads the pinned
official manifest directly on the Application EC2 and applies CRDs server-side.

```bash
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$APPLICATION_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment 'Install pinned Argo CD for Courier AWS dev' \
  --parameters 'commands=["sudo /usr/local/bin/kubectl create namespace argocd --dry-run=client -o yaml | sudo /usr/local/bin/kubectl apply -f -","curl --fail --location --show-error --silent https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml | sudo /usr/local/bin/kubectl apply --server-side --force-conflicts -n argocd -f -","sudo /usr/local/bin/kubectl rollout status deployment/argocd-server -n argocd --timeout=5m","sudo /usr/local/bin/kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=5m","sudo /usr/local/bin/kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=5m","sudo /usr/local/bin/kubectl get pods -n argocd"]'
```

Record the returned command ID, then read its result:

```bash
aws ssm get-command-invocation \
  --region "$AWS_REGION" \
  --command-id '<command-id>' \
  --instance-id "$APPLICATION_INSTANCE_ID"
```

## Enable the protected HTTPS dashboard

Create a dedicated Basic Auth credential first. It is stored as a bcrypt
`htpasswd` entry in Parameter Store and the command never prints the password
or hash:

```bash
AWS_PROFILE=courier-terraform make update-argocd-admin-basic-auth
```

After the GitOps change is merged, bootstrap its Argo CD Application once:

```bash
AWS_PROFILE=courier-terraform make enable-argocd-public-dashboard
```

Wait for the `argocd-dashboard-dev` Application to become `Synced`, then open:

```text
https://courier.io.vn/admin/argocd
```

The browser must pass both layers:

1. Traefik Basic Auth, using the credential stored at
   `/courier/dev/admin-argocd/runtime/BASIC_AUTH_USERS`.
2. Argo CD login, normally with username `admin` and its separately managed
   Argo CD password.

TLS terminates at Traefik; `argocd-server` receives HTTP only on the private
K3s Service. The server is configured with `server.basehref` and
`server.rootpath` set to `/admin/argocd`, so assets, API requests, and browser
navigation stay below that prefix.

## Open the dashboard through the private fallback

First start a temporary loopback-only port-forward process on the node:

```bash
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$APPLICATION_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment 'Create private temporary Argo CD port forward' \
  --parameters 'commands=["sudo pkill -f \"kubectl.*argocd-server.*8080:443\" || true","sudo nohup /usr/local/bin/kubectl port-forward --address 127.0.0.1 -n argocd svc/argocd-server 8080:443 >/var/log/argocd-port-forward.log 2>&1 &","sleep 2","sudo ss -ltnp | grep 127.0.0.1:8080"]'
```

In a separate local terminal, tunnel that loopback port over SSM:

```bash
aws ssm start-session \
  --target "$APPLICATION_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}' \
  --region "$AWS_REGION"
```

Open <https://localhost:8080> and accept the initial self-signed certificate
warning. The username is `admin`.

Retrieve the one-time bootstrap password only in a trusted terminal. Treat the
command output as a secret; do not paste it into an issue, pull request, or
repository file:

```bash
aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$APPLICATION_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment 'Read Argo CD initial administrator password' \
  --parameters 'commands=["sudo /usr/local/bin/kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 --decode; echo"]'
```

After the first login, rotate the `admin` password and configure repository
credentials before creating application resources. Do not give Argo CD an AWS
security-group ingress rule; all public access stays behind the authenticated
Traefik route.

## Verify the private boundary

```bash
sudo /usr/local/bin/kubectl get svc -n argocd argocd-server
```

Expected service type is `ClusterIP`, never `LoadBalancer` or `NodePort`.
