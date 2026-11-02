#!/usr/bin/env bash

# Runs on the Application EC2. It reads only the approved SSM parameters and
# applies them as a Kubernetes Secret without writing or printing their values.
set -euo pipefail

readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly CLIENT_ID_PARAMETER="${CLIENT_ID_PARAMETER:-/courier/dev/user-service/oauth/google/client-id}"
readonly CLIENT_SECRET_PARAMETER="${CLIENT_SECRET_PARAMETER:-/courier/dev/user-service/oauth/google/client-secret}"

client_id=""
client_secret=""
cleanup() { unset client_id client_secret; }
trap cleanup EXIT HUP INT TERM

client_id="$(aws ssm get-parameter --region "${AWS_REGION}" --name "${CLIENT_ID_PARAMETER}" --with-decryption --query Parameter.Value --output text)"
client_secret="$(aws ssm get-parameter --region "${AWS_REGION}" --name "${CLIENT_SECRET_PARAMETER}" --with-decryption --query Parameter.Value --output text)"

[[ -n "${client_id}" && -n "${client_secret}" ]] || {
  echo "OAuth parameters must not be empty." >&2
  exit 1
}

/usr/local/bin/kubectl -n courier-dev create secret generic user-service-runtime-secrets \
  --from-literal=OAUTH_GOOGLE_CLIENT_ID="${client_id}" \
  --from-literal=OAUTH_GOOGLE_CLIENT_SECRET="${client_secret}" \
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f - >/dev/null

/usr/local/bin/kubectl -n courier-dev rollout restart deployment/user-service
/usr/local/bin/kubectl -n courier-dev rollout status deployment/user-service --timeout=180s
echo "Synchronized user-service Google OAuth credentials from SSM."
