#!/usr/bin/env bash
# Creates the declared Kafka topics after the broker is healthy. This runs on
# every courier-data.service start and is safe to repeat because topic creation
# uses --if-not-exists.
set -euo pipefail

readonly compose_bin="/usr/local/bin/docker-compose"
readonly compose_file="/opt/courier/data-node/compose.yaml"
readonly env_file="/etc/courier/data.env"
readonly kafka_container="courier-kafka"
readonly maximum_attempts=30

for attempt in $(seq 1 "${maximum_attempts}"); do
  health_status="$(/usr/bin/docker inspect --format '{{.State.Health.Status}}' "${kafka_container}" 2>/dev/null || true)"
  if [[ "${health_status}" == "healthy" ]]; then
    exec "${compose_bin}" \
      --env-file "${env_file}" \
      -f "${compose_file}" \
      --profile bootstrap \
      run --rm kafka-init
  fi

  sleep 2
done

echo "Kafka did not become healthy after $((maximum_attempts * 2)) seconds." >&2
exit 1
