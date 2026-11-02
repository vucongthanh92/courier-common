# SOPS age secrets for AWS development

Courier AWS development uses SOPS with one age recipient. The public recipient
is in `.sops.yaml`; the private key is stored as an SSM SecureString named
`/courier/dev/argocd/sops-age-key` in `ap-southeast-2`.

Terraform intentionally does not manage the parameter value: Terraform state
must not become a second plaintext copy of the private key.

## Bootstrap the Argo CD key Secret

After the reviewed Terraform policy has been applied, run this through SSM on
the Application EC2. It retrieves the key on that host, creates or replaces
only the `argocd-sops-age` Secret in the `argocd` namespace, and removes its
temporary file before command completion.

```bash
export AWS_PROFILE=courier-terraform
export AWS_REGION=ap-southeast-2
export APPLICATION_INSTANCE_ID=i-06109722166dede79

aws ssm send-command \
  --region "$AWS_REGION" \
  --instance-ids "$APPLICATION_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment 'Bootstrap Argo CD SOPS age key' \
  --parameters 'commands=["set -euo pipefail","key_file=$(mktemp /tmp/courier-sops-age.XXXXXX)","trap '\''rm -f \"$key_file\"'\'' EXIT","aws ssm get-parameter --region ap-southeast-2 --name /courier/dev/argocd/sops-age-key --with-decryption --query Parameter.Value --output text > \"$key_file\"","sudo /usr/local/bin/kubectl -n argocd create secret generic argocd-sops-age --from-file=keys.txt=\"$key_file\" --dry-run=client -o yaml | sudo /usr/local/bin/kubectl apply -f -","sudo /usr/local/bin/kubectl -n argocd get secret argocd-sops-age"]'
```

The command output must identify only the Secret metadata. Do not add a command
that prints the parameter value or Secret data.

## Configure Argo CD KSOPS

Argo CD's repository server uses a dedicated KSOPS Config Management Plugin
sidecar. The sidecar is the only component that mounts `argocd-sops-age`; the
main repository-server container cannot read the age key. Its image is pinned
to `viaductoss/ksops:v4.5.1` and the existing Argo CD `copyutil` init container
supplies the matching `argocd-cmp-server` binary.

The KSOPS image is deliberately minimal and does not provide `sh`. The plugin
therefore invokes its verified `/usr/local/bin/kustomize` binary directly for
rendering; do not change that command to `sh -c`. Discovery is restricted to
an overlay that contains `ksops-generator.yaml`. Public overlays use Argo CD's
built-in Kustomize renderer and encrypted backend overlays name `ksops`
explicitly in their Application manifests. This prevents a public deployment
from consuming CMP CPU or SOPS-key access.

After the bootstrap Secret exists, run the reviewed script on the Application
EC2 as the same operator that administers K3s:

```bash
sudo /usr/local/bin/kubectl apply -f infra/argocd/aws-dev/ksops/plugin-configmap.yaml
sudo /usr/local/bin/kubectl patch deployment argocd-repo-server \
  --namespace argocd \
  --type strategic \
  --patch-file infra/argocd/aws-dev/ksops/repo-server-ksops-patch.yaml
sudo /usr/local/bin/kubectl rollout status deployment/argocd-repo-server \
  --namespace argocd --timeout=5m
```

The equivalent helper is `infra/argocd/aws-dev/ksops/apply.sh` when this
repository is available on the host. Reapply this patch after an Argo CD
reinstallation or a major Argo CD manifest upgrade, then verify the validation
Application below before deploying any service Secret.

## Validate decryption without an application secret

`k8s/overlays/dev/sops-validation/sops-validation.enc.yaml` contains only a
non-sensitive sentinel value. It verifies that Argo CD can render an encrypted
manifest without exposing application credentials. After merging it, apply
`argocd/applications/sops-validation-dev.yaml` and require the Application to
be `Healthy` and `Synced`. The resulting `courier-dev/sops-validation` Secret
is deliberately safe to inspect only for metadata; do not print Secret data.

Each KSOPS generator must declare the KRM exec annotation with `path: ksops`.
That is the supported KSOPS v4 form and resolves the binary from the sidecar
PATH; do not use the legacy plugin-root layout.

## Update Google OAuth credentials for user-service

Run the interactive helper from the repository root when the AWS dev Google
OAuth Web Client changes:

```bash
make update-user-service-google-oauth
```

It prompts for the Client ID and a hidden Client Secret, retrieves the age key
from SSM into a temporary file, updates only `oauth.google` in
`k8s/overlays/dev/user-service/user-service-config.enc.yaml`, validates that
the result decrypts, and removes all temporary files before it exits. It does
not print credential values or create a Git commit.

Review the encrypted diff, commit it on a branch, and open a PR. Once that PR
is merged, Argo CD applies the updated Secret. Restart `user-service` once so
its process reloads the mounted configuration.

## Rotation and recovery

Rotation requires a new age key pair, SSM parameter update, a re-encryption of
every `.enc.yaml` file with both recipients during migration, Argo CD key
Secret refresh, then removal of the old recipient. Test a decrypt/reconcile
before deleting the old key.

If the SSM parameter is lost, encrypted manifests cannot be decrypted. Restore
the parameter from a protected key backup before changing Git history.
