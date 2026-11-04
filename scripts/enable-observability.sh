#!/usr/bin/env bash
# Bootstraps the GitOps Application that manages Courier's AWS dev
# observability stack. The Application itself reconciles from main.
set -euo pipefail

readonly AWS_PROFILE="${AWS_PROFILE:-courier-terraform}"
readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly INSTANCE_ID="${INSTANCE_ID:-i-06109722166dede79}"
readonly APPLICATION_URL="https://raw.githubusercontent.com/vucongthanh92/courier-common/main/argocd/applications/observability-dev.yaml"

for command in aws base64; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Required command not found: $command" >&2
    exit 1
  }
done

aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" >/dev/null

remote_command="sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -n argocd -f $APPLICATION_URL; sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n argocd get application observability-dev"
remote_command_base64="$(printf '%s' "$remote_command" | base64 | tr -d '\n')"

command_id="$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment 'Enable Courier AWS dev observability stack' \
  --parameters "commands=echo $remote_command_base64 | base64 -d | bash" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'Command.CommandId' \
  --output text)"

if ! aws ssm wait command-executed \
  --command-id "$command_id" \
  --instance-id "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"; then
  aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" \
    --query '{status:Status,stdout:StandardOutputContent,stderr:StandardErrorContent}' \
    --output json >&2 || true
  exit 1
fi

echo 'Observability Application is enabled. Wait for it to become Synced, then open https://courier.io.vn/admin/logging'
