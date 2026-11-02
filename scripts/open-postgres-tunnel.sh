#!/usr/bin/env bash
# Opens private Courier PostgreSQL databases on localhost through AWS SSM.
#
# Keep this process running while using psql, DBeaver, or TablePlus. The
# database remains private; this script does not create a public security-group
# rule or expose credentials.

set -euo pipefail

AWS_PROFILE="${AWS_PROFILE:-courier-terraform}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
INSTANCE_ID="${INSTANCE_ID:-i-0959faf3ee5a35835}"
REMOTE_PORT=5432
USER_SERVICE_LOCAL_PORT="${USER_SERVICE_LOCAL_PORT:-15432}"
CHAT_SERVICE_LOCAL_PORT="${CHAT_SERVICE_LOCAL_PORT:-15433}"
PAYMENT_GATEWAY_LOCAL_PORT="${PAYMENT_GATEWAY_LOCAL_PORT:-15434}"

for command in aws session-manager-plugin; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" >/dev/null

declare -a tunnel_pids=()

cleanup() {
  trap - EXIT INT TERM
  for pid in "${tunnel_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null || true
}

open_tunnel() {
  local service_name="$1"
  local database_name="$2"
  local local_port="$3"

  echo "$service_name ($database_name): 127.0.0.1:$local_port"
  aws ssm start-session \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters "{\"portNumber\":[\"$REMOTE_PORT\"],\"localPortNumber\":[\"$local_port\"]}" \
    --region "$AWS_REGION" \
    --profile "$AWS_PROFILE" &
  tunnel_pids+=("$!")
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Opening Courier PostgreSQL tunnels. Keep this terminal open; Ctrl-C stops all tunnels."
open_tunnel "user-service" "user_service" "$USER_SERVICE_LOCAL_PORT"
open_tunnel "chat-service" "chat_service" "$CHAT_SERVICE_LOCAL_PORT"
open_tunnel "payment-gateway" "payment_gateway" "$PAYMENT_GATEWAY_LOCAL_PORT"

echo
echo "Examples:"
echo "  psql -h 127.0.0.1 -p $USER_SERVICE_LOCAL_PORT -U courier_app -d user_service"
echo "  psql -h 127.0.0.1 -p $CHAT_SERVICE_LOCAL_PORT -U courier_app -d chat_service"
echo "  psql -h 127.0.0.1 -p $PAYMENT_GATEWAY_LOCAL_PORT -U courier_app -d payment_gateway"

status=0
for pid in "${tunnel_pids[@]}"; do
  wait "$pid" || status=$?
done

exit "$status"
