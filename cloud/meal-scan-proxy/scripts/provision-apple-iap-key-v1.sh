#!/usr/bin/env bash
set -euo pipefail

readonly PINNED_PROJECT_ID="cyclebalance-prod-20260710"
readonly PINNED_SECRET_NAME="cyclebalance-app-store-iap-private-key"
readonly PINNED_PROXY_SERVICE_ACCOUNT="cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"

PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
SECRET_NAME="${APPLE_IAP_PRIVATE_KEY_SECRET_NAME:-$PINNED_SECRET_NAME}"
PROXY_SERVICE_ACCOUNT="${PROXY_SERVICE_ACCOUNT:-$PINNED_PROXY_SERVICE_ACCOUNT}"
DRY_RUN="${DRY_RUN:-true}"
readonly REQUIRED_APPROVAL="I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1"
P8_FILE="${APPLE_IAP_P8_FILE:-}"
TEMP_ROOT=""

umask 077

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_pinned_identity() {
  [[ "$PROJECT_ID" == "$PINNED_PROJECT_ID" ]] || die "PROJECT_ID is pinned to $PINNED_PROJECT_ID"
  [[ "$SECRET_NAME" == "$PINNED_SECRET_NAME" ]] || die "Apple IAP secret name is pinned"
  [[ "$PROXY_SERVICE_ACCOUNT" == "$PINNED_PROXY_SERVICE_ACCOUNT" ]] || die "proxy service account is pinned"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

cleanup() {
  P8_FILE=""
  unset P8_FILE APPLE_IAP_P8_FILE
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

secret_resource_name() {
  printf 'projects/%s/secrets/%s' "$PROJECT_ID" "$SECRET_NAME"
}

read_secret_inventory() {
  local output_file="$1"
  gcloud secrets list \
    --project "$PROJECT_ID" \
    --filter="name=$SECRET_NAME" \
    --format=json >"$output_file" \
    || die "could not read Apple IAP secret inventory"
  jq -e --arg expected "$(secret_resource_name)" '
    type == "array" and
    length <= 1 and
    all(.[]; (.name? | type == "string") and .name == $expected)
  ' "$output_file" >/dev/null 2>&1 \
    || die "Apple IAP secret inventory was ambiguous or malformed"
}

verify_secret_metadata() {
  local output_file="$1"
  gcloud secrets describe "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --format=json >"$output_file" \
    || die "could not read Apple IAP secret metadata"
  jq -e --arg expected "$(secret_resource_name)" '
    (.name? | type == "string") and .name == $expected
  ' "$output_file" >/dev/null 2>&1 \
    || die "Apple IAP secret metadata did not match the pinned resource"
}

read_versions() {
  local output_file="$1"
  gcloud secrets versions list "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --format=json >"$output_file" \
    || die "could not read Apple IAP secret version metadata"
  jq -e 'type == "array"' "$output_file" >/dev/null 2>&1 \
    || die "Apple IAP secret version metadata was malformed"
}

require_zero_versions() {
  local versions_file="$1"
  jq -e 'length == 0' "$versions_file" >/dev/null 2>&1 \
    || die "Apple IAP secret already has at least one version; refusing to create another"
}

read_iam_policy() {
  local output_file="$1"
  gcloud secrets get-iam-policy "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --format=json >"$output_file" \
    || die "could not read Apple IAP secret IAM metadata"
  jq -e '
    ((.bindings // []) | type == "array") and
    ([.bindings[]?.members[]? | select(. == "allUsers" or . == "allAuthenticatedUsers")] | length == 0)
  ' "$output_file" >/dev/null 2>&1 \
    || die "Apple IAP secret IAM metadata is malformed or contains a public principal"
}

require_exact_proxy_iam() {
  local policy_file="$1"
  local expected_member="serviceAccount:$PROXY_SERVICE_ACCOUNT"
  jq -e --arg expected "$expected_member" '
    ((.bindings // []) | type == "array") and
    (.bindings | length == 1) and
    (.bindings[0].role == "roles/secretmanager.secretAccessor") and
    (.bindings[0].members == [$expected]) and
    ((.bindings[0] | keys - ["members", "role"]) | length == 0) and
    (((.auditConfigs // []) | length) == 0) and
    ([.bindings[]?.members[]? | select(. == "allUsers" or . == "allAuthenticatedUsers")] | length == 0)
  ' "$policy_file" >/dev/null 2>&1 \
    || die "readback did not show exact service-account-only secretAccessor IAM"
}

load_and_validate_p8_file() {
  local file_mode file_size first_line last_line
  if [[ -z "$P8_FILE" ]]; then
    [[ -t 0 ]] || die "APPLE_IAP_P8_FILE must name the owner-only .p8 file for live provisioning"
    read -rsp "Path to the owner-only App Store Connect IAP .p8 file: " P8_FILE
    printf '\n' >/dev/tty
  fi
  [[ -f "$P8_FILE" && -r "$P8_FILE" && ! -L "$P8_FILE" ]] \
    || die "APPLE_IAP_P8_FILE must be a readable regular file, not a symlink"
  [[ "$P8_FILE" == *.p8 ]] || die "APPLE_IAP_P8_FILE must use the .p8 extension"

  file_mode="$(stat -f '%Lp' "$P8_FILE" 2>/dev/null || stat -c '%a' "$P8_FILE" 2>/dev/null)" \
    || die "could not inspect .p8 file permissions"
  [[ "$file_mode" =~ ^[0-7]{3,4}$ ]] || die "could not validate .p8 file permissions"
  (( (8#$file_mode & 077) == 0 )) || die ".p8 file must not be accessible by group or other users"

  file_size="$(wc -c <"$P8_FILE" | tr -d ' ')"
  [[ "$file_size" =~ ^[0-9]+$ ]] || die "could not validate .p8 file size"
  (( file_size >= 100 && file_size <= 10000 )) || die ".p8 file size is outside the expected private-key range"
  first_line="$(head -n 1 "$P8_FILE")"
  last_line="$(tail -n 1 "$P8_FILE")"
  [[ "$first_line" == "-----BEGIN PRIVATE KEY-----" && "$last_line" == "-----END PRIVATE KEY-----" ]] \
    || die ".p8 file did not have the expected private-key envelope"
  [[ "$(grep -c '^-----BEGIN PRIVATE KEY-----$' "$P8_FILE")" == "1" ]] \
    || die ".p8 file must contain exactly one private-key envelope"
  [[ "$(grep -c '^-----END PRIVATE KEY-----$' "$P8_FILE")" == "1" ]] \
    || die ".p8 file must contain exactly one private-key envelope"
}

verify_exact_enabled_v1() {
  local versions_file="$1"
  jq -e '
    length == 1 and
    (.[0].name? | type == "string") and
    ((.[0].name | split("/") | last) == "1") and
    .[0].state == "ENABLED"
  ' "$versions_file" >/dev/null 2>&1 \
    || die "secret must contain exactly one enabled version 1; refusing v2 or any non-enabled state"
}

provision_live() {
  local inventory_file secret_file versions_file iam_file iam_policy_file version_file
  local resource_count secret_existed="false"

  require_command gcloud
  require_command jq
  require_command stat
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-p8-v1.XXXXXX")"
  chmod 0700 "$TEMP_ROOT"
  inventory_file="$TEMP_ROOT/secret-inventory.json"
  secret_file="$TEMP_ROOT/secret.json"
  versions_file="$TEMP_ROOT/versions.json"
  iam_file="$TEMP_ROOT/iam.json"
  iam_policy_file="$TEMP_ROOT/iam-policy.json"
  version_file="$TEMP_ROOT/version-1.json"

  read_secret_inventory "$inventory_file"
  resource_count="$(jq -r 'length' "$inventory_file")"
  if [[ "$resource_count" == "1" ]]; then
    secret_existed="true"
    verify_secret_metadata "$secret_file"
    read_versions "$versions_file"
    require_zero_versions "$versions_file"
    read_iam_policy "$iam_file"
  fi

  load_and_validate_p8_file

  if [[ "$secret_existed" == "false" ]]; then
    gcloud secrets create "$SECRET_NAME" \
      --project "$PROJECT_ID" \
      --replication-policy=automatic >/dev/null \
      || die "could not create the pinned Apple IAP secret resource"
  fi

  # Re-read immediately before the one permitted write so an observed nonzero
  # state always aborts instead of creating another version.
  verify_secret_metadata "$secret_file"
  read_versions "$versions_file"
  require_zero_versions "$versions_file"
  read_iam_policy "$iam_file"

  jq -n --arg member "serviceAccount:$PROXY_SERVICE_ACCOUNT" '{
    version: 1,
    bindings: [{role: "roles/secretmanager.secretAccessor", members: [$member]}]
  }' >"$iam_policy_file"
  chmod 0600 "$iam_policy_file"
  gcloud secrets set-iam-policy "$SECRET_NAME" "$iam_policy_file" \
    --project "$PROJECT_ID" >/dev/null \
    || die "could not set exact proxy-only IAM on the Apple IAP secret"
  read_iam_policy "$iam_file"
  require_exact_proxy_iam "$iam_file"
  read_versions "$versions_file"
  require_zero_versions "$versions_file"

  gcloud secrets versions add "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --data-file="$P8_FILE" >/dev/null \
    || die "could not create Apple IAP secret version 1"

  read_versions "$versions_file"
  verify_exact_enabled_v1 "$versions_file"
  gcloud secrets versions describe 1 \
    --secret "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --format=json >"$version_file" \
    || die "could not read back Apple IAP secret version 1"
  jq -e '
    (select((.name | split("/") | last) == "1" and .state == "ENABLED")) != null
  ' "$version_file" >/dev/null 2>&1 \
    || die "Apple IAP secret version 1 readback was not ENABLED"

  # Confirm no IAM drift occurred while the sole version was created.
  read_iam_policy "$iam_file"
  require_exact_proxy_iam "$iam_file"

  printf '%s\n' \
    "Provisioning verified: the pinned Apple IAP secret has exactly enabled version 1." \
    "IAM verified: secretAccessor is granted to the pinned proxy service account only."
}

print_dry_run() {
  printf '%s\n' \
    "DRY RUN ONLY - no Google Cloud or key-file command was executed." \
    "Pinned project: $PROJECT_ID" \
    "Pinned secret: $SECRET_NAME" \
    "Planned invariant: start with zero versions and create exactly enabled version 1." \
    "Planned IAM invariant: service-account-only secretAccessor for the pinned proxy identity." \
    "Set DRY_RUN=false and provide the exact owner approval to perform the one-time handoff."
}

main() {
  trap cleanup EXIT
  require_pinned_identity
  case "$DRY_RUN" in
    true) print_dry_run ;;
    false)
      [[ "${CONFIRM_APPLE_IAP_P8_V1:-}" == "$REQUIRED_APPROVAL" ]] \
        || die "live provisioning requires CONFIRM_APPLE_IAP_P8_V1=$REQUIRED_APPROVAL"
      provision_live
      ;;
    *) die "DRY_RUN must be true or false" ;;
  esac
}

main "$@"
