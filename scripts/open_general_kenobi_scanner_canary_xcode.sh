#!/usr/bin/env bash
# Safe local staging handoff for the General Kenobi scanner canary scheme.
set -euo pipefail

readonly PINNED_PROXY_URL="https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app"
readonly PINNED_PROXY_XCCONFIG_VALUE='https:/$()/cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app'
readonly SCHEME_NAME="PCOS General Kenobi Scanner Canary"
readonly DEVICE_NAME="General Kenobi"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly LOCAL_SECRETS_CONFIG="$ROOT/Config/LocalSecrets.xcconfig"
readonly PROJECT_PATH="$ROOT/PCOS.xcodeproj"
readonly SHARED_SCHEME_PATH="$ROOT/PCOS.xcodeproj/xcshareddata/xcschemes/PCOS General Kenobi Scanner Canary.xcscheme"

OPEN_PROJECT=true
RELEASE_SETTINGS_FILE=""
SCANNER_CANARY_SETTINGS_FILE=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
xcconfig_value() {
  awk -F= -v key="$2" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { value=$2; sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); print value; exit }' "$1"
}
build_setting() {
  awk -F ' = ' -v key="$2" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' "$1"
}
require_setting() {
  local file="$1" key="$2" expected="$3" actual
  actual="$(build_setting "$file" "$key")"
  [[ "$actual" == "$expected" ]] || die "$key expected $expected, found ${actual:-missing}"
}

usage() {
  note "Usage: ./scripts/open_general_kenobi_scanner_canary_xcode.sh [--no-open]"
  note "Stages a local Xcode signing/launch rehearsal for the General Kenobi scanner canary."
  note "This command does not mutate cloud or device state."
}

cleanup() {
  [[ -z "$RELEASE_SETTINGS_FILE" ]] || rm -f "$RELEASE_SETTINGS_FILE"
  [[ -z "$SCANNER_CANARY_SETTINGS_FILE" ]] || rm -f "$SCANNER_CANARY_SETTINGS_FILE"
}

if (( $# > 1 )); then
  usage >&2
  die "Accepts only --no-open or --help"
fi

case "${1:-}" in
  "") ;;
  --no-open) OPEN_PROJECT=false ;;
  --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "Unknown argument: $1"
    ;;
esac

require_command git
require_command xcodegen
require_command xcodebuild
require_command awk
require_command grep
require_command mktemp
require_command rm
if [[ "$OPEN_PROJECT" == true ]]; then
  require_command open
fi

cd "$ROOT"

[[ -z "$(git status --porcelain --untracked-files=all)" ]] || die "Worktree must be clean before staging Xcode"
[[ -f "$LOCAL_SECRETS_CONFIG" ]] || die "Missing ignored local Xcode configuration"
git check-ignore -q "$LOCAL_SECRETS_CONFIG" || die "Local Xcode configuration must remain ignored"

revenuecat_key="$(xcconfig_value "$LOCAL_SECRETS_CONFIG" REVENUECAT_PUBLIC_SDK_KEY)"
[[ -n "$revenuecat_key" ]] || die "RevenueCat public SDK configuration is missing"

proxy_url="$(xcconfig_value "$LOCAL_SECRETS_CONFIG" MEAL_SCAN_PROXY_BASE_URL)"
if [[ "$proxy_url" == "$PINNED_PROXY_XCCONFIG_VALUE" ]]; then
  proxy_url="$PINNED_PROXY_URL"
fi
[[ "$proxy_url" == "$PINNED_PROXY_URL" ]] || die "Meal Scan proxy configuration is not pinned"
unset revenuecat_key proxy_url

if ! DRY_RUN=true cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh >/dev/null 2>&1; then
  die "Positive-canary dry-run validation failed"
fi

if ! xcodegen generate >/dev/null 2>&1; then
  die "Xcode project generation failed"
fi

trap cleanup EXIT
RELEASE_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/cyclebalance-release-settings.XXXXXX")"
SCANNER_CANARY_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/cyclebalance-scanner-canary-settings.XXXXXX")"

if ! xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration Release -showBuildSettings CODE_SIGNING_ALLOWED=NO >"$RELEASE_SETTINGS_FILE" 2>&1; then
  die "Unable to inspect Release build settings"
fi
if ! xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration ScannerCanary -showBuildSettings CODE_SIGNING_ALLOWED=NO >"$SCANNER_CANARY_SETTINGS_FILE" 2>&1; then
  die "Unable to inspect ScannerCanary build settings"
fi

require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_UI_ENABLED NO
require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_GEMINI_ENABLED NO
require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED NO
require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED NO
require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED NO
require_setting "$RELEASE_SETTINGS_FILE" MEAL_SCAN_RELEASE_SIMILARITY_ENABLED NO

require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_UI_ENABLED YES
require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_GEMINI_ENABLED YES
require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED NO
require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED NO
require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED NO
require_setting "$SCANNER_CANARY_SETTINGS_FILE" MEAL_SCAN_RELEASE_SIMILARITY_ENABLED NO

[[ -f "$SHARED_SCHEME_PATH" ]] || die "Generated shared scanner-canary scheme is missing"
grep -Fq '<ArchiveAction' "$SHARED_SCHEME_PATH" || die "Scanner-canary scheme Archive action is missing"
awk '
  /<ArchiveAction/ { in_archive = 1 }
  in_archive && /buildConfiguration = "Release"/ { found = 1 }
  in_archive && /<\/ArchiveAction>/ { exit(found ? 0 : 1) }
  END { if (!found) exit 1 }
' "$SHARED_SCHEME_PATH" || die "Scanner-canary Archive must remain on Release"

note "Xcode staging checks passed."
note "Scheme: PCOS General Kenobi Scanner Canary"
note "Device: General Kenobi"
note "Run: Product > Run"
note "This is a local signing/launch rehearsal only; Cloud Run remains disabled/private."
note "Use the audited terminal harness separately for the real AI scan."

if [[ "$OPEN_PROJECT" == true ]]; then
  open "$ROOT/PCOS.xcodeproj"
fi
