#!/usr/bin/env bash
# Creates the initial credentials for the protected public Grafana dashboard,
# and can rotate its Traefik Basic Auth credential without printing passwords
# or the generated bcrypt hash. It uses a local Apache htpasswd binary, so
# Docker Desktop is not an operational prerequisite. Grafana uses its admin
# password only on first database initialization; see
# docs/devops/aws-observability.md.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly BASIC_AUTH_PARAMETER="${BASIC_AUTH_PARAMETER:-/courier/dev/admin-logging/runtime/BASIC_AUTH_USERS}"
readonly GRAFANA_PASSWORD_PARAMETER="${GRAFANA_PASSWORD_PARAMETER:-/courier/dev/admin-logging/runtime/GRAFANA_ADMIN_PASSWORD}"
username=""
basic_auth_password=""
grafana_admin_password=""
users=""

cleanup() {
  unset username basic_auth_password grafana_admin_password users
}
trap cleanup EXIT HUP INT TERM

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

require_command aws
require_command htpasswd

read -r -p "Logging dashboard username: " username
read -r -s -p "Logging dashboard Basic Auth password: " basic_auth_password
printf '\n'
read -r -s -p "Grafana admin password: " grafana_admin_password
printf '\n'

[[ "${username}" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "Username may contain only letters, numbers, dot, underscore, and hyphen." >&2
  exit 1
}
[[ -n "${basic_auth_password}" ]] || {
  echo "Basic Auth password must not be empty." >&2
  exit 1
}
[[ -n "${grafana_admin_password}" ]] || {
  echo "Grafana admin password must not be empty." >&2
  exit 1
}

users="$(printf '%s\n' "${basic_auth_password}" | htpasswd -inB -C 12 "${username}")"

aws ssm put-parameter \
  --region "${AWS_REGION}" \
  --name "${BASIC_AUTH_PARAMETER}" \
  --type SecureString \
  --value "${users}" \
  --overwrite \
  --no-cli-pager >/dev/null

aws ssm put-parameter \
  --region "${AWS_REGION}" \
  --name "${GRAFANA_PASSWORD_PARAMETER}" \
  --type SecureString \
  --value "${grafana_admin_password}" \
  --overwrite \
  --no-cli-pager >/dev/null

echo "Updated protected logging dashboard credentials in Parameter Store."
