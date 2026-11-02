#!/usr/bin/env bash

# Creates the non-secret SSO runtime values that External Secrets Operator
# mirrors from Parameter Store into the user-service Kubernetes Secret.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly PARAMETER_PREFIX="${PARAMETER_PREFIX:-/courier/dev/user-service/runtime}"
readonly SSO_LOGIN_URL="${SSO_LOGIN_URL:-https://courier.io.vn/conversa/}"
readonly SSO_CONVERSA_CLIENT_ID="${SSO_CONVERSA_CLIENT_ID:-conversa-web}"
readonly SSO_CONVERSA_REDIRECT_URI="${SSO_CONVERSA_REDIRECT_URI:-https://courier.io.vn/conversa/oauth/callback/courier}"
readonly SSO_FLIKK_CLIENT_ID="${SSO_FLIKK_CLIENT_ID:-flikk-web}"
readonly SSO_FLIKK_REDIRECT_URI="${SSO_FLIKK_REDIRECT_URI:-https://courier.io.vn/flikk/oauth/callback/courier}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

put_parameter() {
  local name="$1"
  local value="$2"

  [[ -n "${value}" ]] || {
    echo "Parameter value must not be empty: ${name}" >&2
    exit 1
  }

  aws ssm put-parameter \
    --region "${AWS_REGION}" \
    --name "${PARAMETER_PREFIX}/${name}" \
    --type String \
    --value "${value}" \
    --overwrite \
    --no-cli-pager >/dev/null
}

require_command aws

put_parameter SSO_LOGIN_URL "${SSO_LOGIN_URL}"
put_parameter SSO_CONVERSA_CLIENT_ID "${SSO_CONVERSA_CLIENT_ID}"
put_parameter SSO_CONVERSA_REDIRECT_URI "${SSO_CONVERSA_REDIRECT_URI}"
put_parameter SSO_FLIKK_CLIENT_ID "${SSO_FLIKK_CLIENT_ID}"
put_parameter SSO_FLIKK_REDIRECT_URI "${SSO_FLIKK_REDIRECT_URI}"

echo "Updated user-service SSO runtime parameters under ${PARAMETER_PREFIX}/."
