#!/usr/bin/env bash

# Writes AWS dev Google OAuth credentials to the standard runtime prefix. The
# values are read by External Secrets Operator and are never committed to Git.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly PARAMETER_PREFIX="${PARAMETER_PREFIX:-/courier/dev/user-service/runtime}"

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

put_parameter() {
  local name="$1"
  local value="$2"

  aws ssm put-parameter \
    --region "${AWS_REGION}" \
    --name "${PARAMETER_PREFIX}/${name}" \
    --type SecureString \
    --value "${value}" \
    --overwrite \
    --no-cli-pager >/dev/null
}

require_command aws

read -r -p "Google OAuth Client ID (AWS dev): " client_id
read -r -s -p "Google OAuth Client Secret (AWS dev): " client_secret
printf '\n'

[[ -n "${client_id}" && -n "${client_secret}" ]] || {
  echo "Google OAuth Client ID and Client Secret must not be empty." >&2
  exit 1
}

put_parameter OAUTH_GOOGLE_CLIENT_ID "${client_id}"
put_parameter OAUTH_GOOGLE_CLIENT_SECRET "${client_secret}"

echo "Updated Google OAuth runtime parameters under ${PARAMETER_PREFIX}/."
