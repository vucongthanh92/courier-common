#!/usr/bin/env bash
# Creates or rotates the Traefik Basic Auth credential for the protected Argo CD
# dashboard without printing the password or generated hash.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly PARAMETER_NAME="${PARAMETER_NAME:-/courier/dev/admin-argocd/runtime/BASIC_AUTH_USERS}"
readonly HTTPD_IMAGE="httpd:2.4.65-alpine"

username=""
password=""
users=""

cleanup() {
  unset username password users
}
trap cleanup EXIT HUP INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_command aws
require_command docker

read -r -p "Argo CD dashboard username: " username
read -r -s -p "Argo CD dashboard password: " password
printf '\n'

[[ "${username}" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "Username may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 1
}
[[ -n "${password}" ]] || {
  echo "Password must not be empty." >&2
  exit 1
}

users="$(printf '%s\n' "${password}" | docker run --rm -i --entrypoint htpasswd "${HTTPD_IMAGE}" -inB -C 12 "${username}")"

aws ssm put-parameter \
  --region "${AWS_REGION}" \
  --name "${PARAMETER_NAME}" \
  --type SecureString \
  --value "${users}" \
  --overwrite \
  --no-cli-pager >/dev/null

echo "Updated protected Argo CD dashboard credentials in Parameter Store."
