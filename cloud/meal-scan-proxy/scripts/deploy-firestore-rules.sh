#!/usr/bin/env bash
set -euo pipefail

PINNED_PROJECT_ID="cyclebalance-prod-20260710"
PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_FILE="${RULES_FILE:-$SCRIPT_DIR/../firestore.rules}"
RELEASE_ID="cloud.firestore"
API_ROOT="https://firebaserules.googleapis.com/v1/projects/$PROJECT_ID"

if [[ "$PROJECT_ID" != "$PINNED_PROJECT_ID" ]]; then
  echo "PROJECT_ID is pinned to the production project: $PINNED_PROJECT_ID" >&2
  exit 1
fi

for command in curl gcloud jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

if [[ ! -f "$RULES_FILE" ]]; then
  echo "Missing Firestore rules file: $RULES_FILE" >&2
  exit 1
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-firestore-rules.XXXXXX")"
chmod 700 "$TEMP_ROOT"
cleanup() {
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT INT TERM

auth_header_curl_config() {
  local access_token="$1"
  local config_path="$2"

  umask 077
  printf 'header = "Authorization: Bearer %s"\n' "$access_token" >"$config_path"
  printf 'header = "x-goog-user-project: %s"\n' "$PROJECT_ID" >>"$config_path"
  chmod 600 "$config_path"
}

api_request() {
  local method="$1"
  local url="$2"
  local output_path="$3"
  local body_path="${4:-}"
  local http_code
  local curl_arguments=(
    --config "$AUTH_CONFIG"
    --silent
    --show-error
    --request "$method"
    --output "$output_path"
    --write-out "%{http_code}"
    --header "Content-Type: application/json; charset=utf-8"
  )

  if [[ -n "$body_path" ]]; then
    curl_arguments+=(--data-binary "@$body_path")
  fi

  http_code="$(curl "${curl_arguments[@]}" "$url")"
  printf '%s' "$http_code"
}

require_success() {
  local http_code="$1"
  local response_path="$2"
  local operation="$3"

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "$operation failed with HTTP $http_code" >&2
    jq -c '{error: (.error.message // "unknown")}' "$response_path" >&2 2>/dev/null || true
    exit 1
  fi
}

ACCESS_TOKEN="$(gcloud auth print-access-token --quiet)"
AUTH_CONFIG="$TEMP_ROOT/auth.conf"
auth_header_curl_config "$ACCESS_TOKEN" "$AUTH_CONFIG"
unset ACCESS_TOKEN

RULESET_PAYLOAD="$TEMP_ROOT/ruleset-request.json"
jq -n --rawfile content "$RULES_FILE" '{source: {files: [{name: "firestore.rules", content: $content}]}}' >"$RULESET_PAYLOAD"

RULESET_RESPONSE="$TEMP_ROOT/ruleset-response.json"
RULESET_STATUS="$(api_request POST "$API_ROOT/rulesets" "$RULESET_RESPONSE" "$RULESET_PAYLOAD")"
require_success "$RULESET_STATUS" "$RULESET_RESPONSE" "Ruleset creation"
RULESET_NAME="$(jq -er '.name' "$RULESET_RESPONSE")"

RELEASE_NAME="projects/$PROJECT_ID/releases/$RELEASE_ID"
RELEASE_URL="$API_ROOT/releases/$RELEASE_ID"
CURRENT_RELEASE="$TEMP_ROOT/current-release.json"
CURRENT_STATUS="$(api_request GET "$RELEASE_URL" "$CURRENT_RELEASE")"

RELEASE_PAYLOAD="$TEMP_ROOT/release-request.json"
RELEASE_RESPONSE="$TEMP_ROOT/release-response.json"
if [[ "$CURRENT_STATUS" == "404" ]]; then
  jq -n \
    --arg name "$RELEASE_NAME" \
    --arg rulesetName "$RULESET_NAME" \
    '{name: $name, rulesetName: $rulesetName}' >"$RELEASE_PAYLOAD"
  RELEASE_STATUS="$(api_request POST "$API_ROOT/releases" "$RELEASE_RESPONSE" "$RELEASE_PAYLOAD")"
  require_success "$RELEASE_STATUS" "$RELEASE_RESPONSE" "Firestore release creation"
elif [[ "$CURRENT_STATUS" -ge 200 && "$CURRENT_STATUS" -lt 300 ]]; then
  jq -n \
    --arg name "$RELEASE_NAME" \
    --arg rulesetName "$RULESET_NAME" \
    '{release: {name: $name, rulesetName: $rulesetName}, updateMask: "rulesetName"}' >"$RELEASE_PAYLOAD"
  RELEASE_STATUS="$(api_request PATCH "$RELEASE_URL" "$RELEASE_RESPONSE" "$RELEASE_PAYLOAD")"
  require_success "$RELEASE_STATUS" "$RELEASE_RESPONSE" "Firestore release update"
else
  require_success "$CURRENT_STATUS" "$CURRENT_RELEASE" "Firestore release lookup"
fi

jq -e --arg expected "$RULESET_NAME" '.rulesetName == $expected' "$RELEASE_RESPONSE" >/dev/null

VERIFIED_RELEASE="$TEMP_ROOT/verified-release.json"
VERIFY_RELEASE_STATUS="$(api_request GET "$RELEASE_URL" "$VERIFIED_RELEASE")"
require_success "$VERIFY_RELEASE_STATUS" "$VERIFIED_RELEASE" "Firestore release verification"
jq -e --arg expected "$RULESET_NAME" '.rulesetName == $expected' "$VERIFIED_RELEASE" >/dev/null

VERIFIED_RULESET="$TEMP_ROOT/verified-ruleset.json"
VERIFY_RULESET_STATUS="$(api_request GET "https://firebaserules.googleapis.com/v1/$RULESET_NAME" "$VERIFIED_RULESET")"
require_success "$VERIFY_RULESET_STATUS" "$VERIFIED_RULESET" "Firestore ruleset verification"
jq -e --rawfile expected "$RULES_FILE" '.source.files[] | select(.name == "firestore.rules") | .content == $expected' "$VERIFIED_RULESET" >/dev/null

echo "Firestore mobile/web access is denied by release $RELEASE_NAME."
echo "Verified ruleset: $RULESET_NAME"
