#!/usr/bin/env bash
# Opens the private Courier PostgreSQL endpoint on localhost through AWS SSM.
#
# Keep this process running while using psql, DBeaver, or TablePlus. The
# database remains private; this script does not create a public security-group
# rule or expose credentials.

set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-courier-terraform}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
INSTANCE_ID="${INSTANCE_ID:-i-0959faf3ee5a35835}"
LOCAL_PORT="${LOCAL_PORT:-15432}"
REMOTE_PORT=5432

for command in aws session-manager-plugin; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" >/dev/null

echo "PostgreSQL is available at 127.0.0.1:$LOCAL_PORT while this terminal stays open."
echo "Example: psql -h 127.0.0.1 -p $LOCAL_PORT -U courier_app -d user_service"

exec aws ssm start-session \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE"
