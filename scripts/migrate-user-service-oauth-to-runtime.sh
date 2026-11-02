#!/usr/bin/env bash

# One-time migration of existing user-service Google OAuth SecureStrings to the
# standard runtime prefix. It does not print, delete, or modify old values.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly LEGACY_CLIENT_ID_PARAMETER="${LEGACY_CLIENT_ID_PARAMETER:-/courier/dev/user-service/oauth/google/client-id}"
readonly LEGACY_CLIENT_SECRET_PARAMETER="${LEGACY_CLIENT_SECRET_PARAMETER:-/courier/dev/user-service/oauth/google/client-secret}"
readonly RUNTIME_PARAMETER_PREFIX="${RUNTIME_PARAMETER_PREFIX:-/courier/dev/user-service/runtime}"

client_id=""
client_secret=""

cleanup() {
  unset client_id client_secret
}
trap cleanup EXIT HUP INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

get_parameter() {
  aws ssm get-parameter \
    --region "${AWS_REGION}" \
    --name "$1" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text
}

put_parameter() {
  aws ssm put-parameter \
    --region "${AWS_REGION}" \
    --name "$1" \
    --type SecureString \
    --value "$2" \
    --overwrite \
    --no-cli-pager >/dev/null
}

require_command aws

client_id="$(get_parameter "${LEGACY_CLIENT_ID_PARAMETER}")"
client_secret="$(get_parameter "${LEGACY_CLIENT_SECRET_PARAMETER}")"

[[ -n "${client_id}" && -n "${client_secret}" ]] || {
  echo "Legacy Google OAuth parameters must not be empty." >&2
  exit 1
}

put_parameter "${RUNTIME_PARAMETER_PREFIX}/OAUTH_GOOGLE_CLIENT_ID" "${client_id}"
put_parameter "${RUNTIME_PARAMETER_PREFIX}/OAUTH_GOOGLE_CLIENT_SECRET" "${client_secret}"

echo "Copied Google OAuth credentials to ${RUNTIME_PARAMETER_PREFIX}/ without printing values."
