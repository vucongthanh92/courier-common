#!/usr/bin/env bash

# Enables or disables continuous Go profiling through AWS Parameter Store.
# External Secrets Operator mirrors each service path into its Pod environment.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly ENVIRONMENT="${ENVIRONMENT:-dev}"
readonly PROFILING_ENABLED="${PROFILING_ENABLED:-true}"
readonly PROFILING_SERVER_ADDRESS="${PROFILING_SERVER_ADDRESS:-http://pyroscope.courier-observability.svc.cluster.local:4040}"
readonly SERVICES=(user-service chat-service payment-gateway agent-gateway)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

validate_boolean() {
  case "${1}" in
    true|false) ;;
    *)
      echo "PROFILING_ENABLED must be true or false." >&2
      exit 1
      ;;
  esac
}

put_parameter() {
  local service="$1"
  local name="$2"
  local value="$3"

  aws ssm put-parameter \
    --region "${AWS_REGION}" \
    --name "/courier/${ENVIRONMENT}/${service}/runtime/${name}" \
    --type String \
    --value "${value}" \
    --overwrite \
    --no-cli-pager >/dev/null
}

require_command aws
validate_boolean "${PROFILING_ENABLED}"

for service in "${SERVICES[@]}"; do
  put_parameter "${service}" PROFILING_ENABLED "${PROFILING_ENABLED}"
  put_parameter "${service}" PROFILING_SERVER_ADDRESS "${PROFILING_SERVER_ADDRESS}"
done

echo "Continuous profiling is set to ${PROFILING_ENABLED} for ${ENVIRONMENT}."
echo "External Secrets Operator may take up to 15 minutes to refresh; restart a Deployment to apply immediately."
