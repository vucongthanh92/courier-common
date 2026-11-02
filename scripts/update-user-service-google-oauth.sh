#!/usr/bin/env bash

# Update the Google OAuth credentials in the encrypted AWS dev user-service
# configuration. Credentials are requested interactively and never echoed.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly TARGET_RELATIVE_PATH="k8s/overlays/dev/user-service/user-service-config.enc.yaml"
readonly TARGET_FILE="${REPOSITORY_ROOT}/${TARGET_RELATIVE_PATH}"
readonly SOPS_CONFIG_FILE="${REPOSITORY_ROOT}/.sops.yaml"
readonly AWS_REGION="${AWS_REGION:-ap-southeast-2}"
readonly SOPS_AGE_KEY_PARAMETER="${SOPS_AGE_KEY_PARAMETER:-/courier/dev/argocd/sops-age-key}"

key_file=""
plaintext_file=""
updated_file=""
encrypted_file=""
client_id=""
client_secret=""

cleanup() {
  unset client_id client_secret OAUTH_GOOGLE_CLIENT_ID OAUTH_GOOGLE_CLIENT_SECRET
  rm -f "${key_file}" "${plaintext_file}" "${updated_file}" "${encrypted_file}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

usage() {
  cat <<'EOF'
Usage: ./scripts/update-user-service-google-oauth.sh

Prompts for the AWS dev Google OAuth Client ID and Client Secret, retrieves the
SOPS age key temporarily from AWS SSM, and updates the encrypted user-service
configuration. It never prints either credential.

Optional environment variables:
  AWS_PROFILE                 AWS CLI profile (default: AWS CLI default)
  AWS_REGION                  AWS region (default: ap-southeast-2)
  SOPS_AGE_KEY_PARAMETER      SSM parameter (default: /courier/dev/argocd/sops-age-key)
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

require_command aws
require_command ruby
require_command sops

[[ -f "${TARGET_FILE}" ]] || {
  echo "Encrypted user-service config not found: ${TARGET_FILE}" >&2
  exit 1
}

[[ -f "${SOPS_CONFIG_FILE}" ]] || {
  echo "SOPS configuration not found: ${SOPS_CONFIG_FILE}" >&2
  exit 1
}

trap cleanup EXIT HUP INT TERM

read -r -p "Google OAuth Client ID (AWS dev): " client_id
read -r -s -p "Google OAuth Client Secret (AWS dev): " client_secret
printf '\n'

[[ -n "${client_id}" ]] || {
  echo "Google OAuth Client ID must not be empty." >&2
  exit 1
}

[[ -n "${client_secret}" ]] || {
  echo "Google OAuth Client Secret must not be empty." >&2
  exit 1
}

key_file="$(mktemp "${TMPDIR:-/tmp}/courier-sops-age.XXXXXX")"
plaintext_file="$(mktemp "${TMPDIR:-/tmp}/courier-user-service-config.XXXXXX.yaml")"
updated_file="$(mktemp "${TMPDIR:-/tmp}/courier-user-service-config-updated.XXXXXX.yaml")"
encrypted_file="$(mktemp "${TMPDIR:-/tmp}/courier-user-service-config-encrypted.XXXXXX.yaml")"
chmod 600 "${key_file}" "${plaintext_file}" "${updated_file}" "${encrypted_file}"

aws ssm get-parameter \
  --region "${AWS_REGION}" \
  --name "${SOPS_AGE_KEY_PARAMETER}" \
  --with-decryption \
  --query Parameter.Value \
  --output text > "${key_file}"

SOPS_AGE_KEY_FILE="${key_file}" \
  sops --config "${SOPS_CONFIG_FILE}" --decrypt "${TARGET_FILE}" > "${plaintext_file}"

export OAUTH_GOOGLE_CLIENT_ID="${client_id}"
export OAUTH_GOOGLE_CLIENT_SECRET="${client_secret}"

ruby - "${plaintext_file}" "${updated_file}" <<'RUBY'
require "yaml"

source_path, output_path = ARGV
document = YAML.load_file(source_path)
config_text = document.dig("stringData", "config.yaml")
abort("Expected stringData.config.yaml in decrypted Secret") unless config_text.is_a?(String)

config = YAML.load(config_text)
abort("Expected oauth.google in user-service config") unless config.dig("oauth", "google").is_a?(Hash)

config["oauth"]["google"]["client_id"] = ENV.fetch("OAUTH_GOOGLE_CLIENT_ID")
config["oauth"]["google"]["client_secret"] = ENV.fetch("OAUTH_GOOGLE_CLIENT_SECRET")
config["oauth"]["google"]["redirect_uri"] = "https://courier.io.vn/api/user/api/v1/auth/identity/google/callback"

document["stringData"]["config.yaml"] = YAML.dump(config).sub(/\A---\s*\n/, "")
File.write(output_path, YAML.dump(document))
RUBY

SOPS_AGE_KEY_FILE="${key_file}" \
  sops --config "${SOPS_CONFIG_FILE}" \
    --filename-override "${TARGET_RELATIVE_PATH}" \
    --encrypt --input-type yaml --output-type yaml "${updated_file}" > "${encrypted_file}"

SOPS_AGE_KEY_FILE="${key_file}" \
  sops --config "${SOPS_CONFIG_FILE}" --decrypt "${encrypted_file}" >/dev/null

mv "${encrypted_file}" "${TARGET_FILE}"
encrypted_file=""

echo "Updated encrypted AWS dev Google OAuth configuration."
echo "Review the encrypted diff, commit it on a branch, and open a pull request."
