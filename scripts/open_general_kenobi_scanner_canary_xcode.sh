#!/usr/bin/env bash
# Safe local staging handoff for the General Kenobi scanner canary scheme.
set -euo pipefail

readonly PINNED_PROXY_URL="https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app"
readonly PINNED_PROXY_XCCONFIG_VALUE='https:/$()/cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app'
readonly SCHEME_NAME="PCOS General Kenobi Scanner Canary"
readonly DEVICE_NAME="General Kenobi"
readonly BILLING_BACKEND_MODE_ARGUMENT="-billing.backendMode"
readonly BILLING_PROVIDER_ARGUMENT="revenuecat"
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
require_clean_worktree() {
  local dirty_error="$1" status
  if ! status="$(git status --porcelain --untracked-files=all)"; then
    die "Unable to inspect worktree state"
  fi
  [[ -z "$status" ]] || die "$dirty_error"
}
xcconfig_value() {
  awk -F= -v key="$2" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" { value=$2; sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value); print value; exit }' "$1"
}
build_setting() {
  awk -F ' = ' -v key="$2" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' "$1"
}
require_setting() {
  local file="$1" key="$2" expected="$3" actual
  actual="$(build_setting "$file" "$key")"
  [[ "$actual" == "$expected" ]] || die "$key does not match required staging policy"
}
require_effective_configuration() {
  local file="$1" configuration="$2" proxy_url revenuecat_key
  proxy_url="$(build_setting "$file" MEAL_SCAN_PROXY_BASE_URL)"
  [[ "$proxy_url" == "$PINNED_PROXY_URL" ]] || die "$configuration effective MEAL_SCAN_PROXY_BASE_URL is not pinned"
  revenuecat_key="$(build_setting "$file" REVENUECAT_PUBLIC_SDK_KEY)"
  [[ -n "$revenuecat_key" ]] || die "$configuration effective REVENUECAT_PUBLIC_SDK_KEY is missing"
}
scheme_action_block() {
  local action="$1"
  awk -v action="$action" '
    BEGIN {
      open_pattern = "<" action "([[:space:]>]|$)"
      close_pattern = "</" action ">"
    }
    {
      remainder = $0
      line_open_count = 0
      while (match(remainder, open_pattern)) {
        line_open_count++
        remainder = substr(remainder, RSTART + RLENGTH)
      }
      if (line_open_count > 0) {
        action_count += line_open_count
        if (in_action || line_open_count != 1) malformed = 1
        in_action = 1
      }

      if (in_action) print

      remainder = $0
      line_close_count = 0
      while (match(remainder, close_pattern)) {
        line_close_count++
        remainder = substr(remainder, RSTART + RLENGTH)
      }
      if (line_close_count > 0) {
        if (!in_action || line_close_count != 1) malformed = 1
        in_action = 0
      }
    }
    END {
      if (action_count != 1 || in_action || malformed) exit 1
    }
  ' "$SHARED_SCHEME_PATH"
}
require_scheme_action_configuration() {
  local action="$1" expected="$2" block
  if ! block="$(scheme_action_block "$action")"; then
    die "$action is missing or duplicated"
  fi
  if ! printf '%s\n' "$block" | awk -v expected="$expected" '
    BEGIN {
      declaration_pattern = "(^|[[:space:]])buildConfiguration[[:space:]]*="
      expected_pattern = declaration_pattern "[[:space:]]*\"" expected "\"([[:space:]>]|$)"
    }
    in_opening != 0 || NR == 1 {
      in_opening = 1
      line = $0
      while (match(line, declaration_pattern)) {
        declaration_count++
        line = substr(line, RSTART + RLENGTH)
      }
      if ($0 ~ expected_pattern) expected_count++
      if ($0 ~ />/) {
        opening_closed = 1
        in_opening = 0
        exit
      }
    }
    END { exit(opening_closed && declaration_count == 1 && expected_count == 1 ? 0 : 1) }
  '; then
    die "$action build configuration is invalid"
  fi
}
require_launch_argument_contract() {
  local launch_block
  if ! launch_block="$(scheme_action_block LaunchAction)"; then
    die "LaunchAction is missing or duplicated"
  fi
  if ! printf '%s\n' "$launch_block" | awk \
    -v backend_argument="$BILLING_BACKEND_MODE_ARGUMENT" \
    -v provider_argument="$BILLING_PROVIDER_ARGUMENT" '
    function count_matches(text, pattern, remainder, count) {
      remainder = text
      while (match(remainder, pattern)) {
        count++
        remainder = substr(remainder, RSTART + RLENGTH)
      }
      return count
    }
    function reset_argument() {
      argument_attribute_count = 0
      enabled_attribute_count = 0
      argument_kind = ""
      enabled = 0
    }
    function finish_argument() {
      if (argument_attribute_count != 1 || enabled_attribute_count != 1 || !enabled) invalid = 1
      if (argument_kind == "billing") {
        billing_count++
      } else if (argument_kind == "revenuecat") {
        revenuecat_count++
      } else {
        invalid = 1
      }
    }
    BEGIN {
      container_open_pattern = "<CommandLineArguments([[:space:]>]|$)"
      container_close_pattern = "</CommandLineArguments>"
      argument_open_pattern = "<CommandLineArgument([[:space:]>]|$)"
      argument_close_pattern = "</CommandLineArgument>"
    }
    {
      container_opens = count_matches($0, container_open_pattern)
      if (container_opens > 0) {
        container_open_count += container_opens
        if (in_container || container_opens != 1) invalid = 1
        in_container = 1
      }

      argument_opens = count_matches($0, argument_open_pattern)
      if (argument_opens > 0) {
        argument_count += argument_opens
        if (!in_container || in_argument || argument_opens != 1) invalid = 1
        in_argument = 1
        reset_argument()
      }

      if (in_argument && $0 ~ /^[[:space:]]*argument[[:space:]]*=/) {
        argument_attribute_count++
        argument_value = $0
        sub(/^[[:space:]]*argument[[:space:]]*=[[:space:]]*"/, "", argument_value)
        if (!sub(/"[[:space:]>]*$/, "", argument_value)) invalid = 1
        if (argument_value == backend_argument) {
          argument_kind = "billing"
        } else if (argument_value == provider_argument) {
          argument_kind = "revenuecat"
        }
      }
      if (in_argument && $0 ~ /^[[:space:]]*isEnabled[[:space:]]*=/) {
        enabled_attribute_count++
        if ($0 ~ /^[[:space:]]*isEnabled[[:space:]]*=[[:space:]]*"YES"([[:space:]>]|$)/) enabled = 1
      }

      argument_closes = count_matches($0, argument_close_pattern)
      if (argument_closes > 0) {
        if (!in_argument || argument_closes != 1) invalid = 1
        finish_argument()
        in_argument = 0
      }

      container_closes = count_matches($0, container_close_pattern)
      if (container_closes > 0) {
        container_close_count += container_closes
        if (!in_container || in_argument || container_closes != 1) invalid = 1
        in_container = 0
      }
    }
    END {
      if (in_container || in_argument || invalid || container_open_count != 1 || container_close_count != 1 || argument_count != 2 || billing_count != 1 || revenuecat_count != 1) exit 1
    }
  '; then
    die "LaunchAction command-line argument contract is invalid"
  fi
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
    die "Unknown argument"
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

require_clean_worktree "Worktree must be clean before staging Xcode"
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
require_clean_worktree "Xcode project generation changed tracked or untracked files"

[[ -f "$SHARED_SCHEME_PATH" ]] || die "Generated shared scanner-canary scheme is missing"
grep -Fq 'storeKitConfiguration' "$SHARED_SCHEME_PATH" && die "Generated scanner-canary scheme must not contain a StoreKit configuration"
require_scheme_action_configuration LaunchAction ScannerCanary
require_scheme_action_configuration ProfileAction ScannerCanary
require_scheme_action_configuration AnalyzeAction ScannerCanary
require_scheme_action_configuration ArchiveAction Release
require_launch_argument_contract

trap cleanup EXIT
RELEASE_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/cyclebalance-release-settings.XXXXXX")"
SCANNER_CANARY_SETTINGS_FILE="$(mktemp "${TMPDIR:-/tmp}/cyclebalance-scanner-canary-settings.XXXXXX")"

if ! xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration Release -showBuildSettings CODE_SIGNING_ALLOWED=NO >"$RELEASE_SETTINGS_FILE" 2>&1; then
  die "Unable to inspect Release build settings"
fi
if ! xcodebuild -project "$PROJECT_PATH" -scheme "$SCHEME_NAME" -configuration ScannerCanary -showBuildSettings CODE_SIGNING_ALLOWED=NO >"$SCANNER_CANARY_SETTINGS_FILE" 2>&1; then
  die "Unable to inspect ScannerCanary build settings"
fi

require_effective_configuration "$RELEASE_SETTINGS_FILE" Release
require_effective_configuration "$SCANNER_CANARY_SETTINGS_FILE" ScannerCanary

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

note "Xcode staging checks passed."
note "Scheme: PCOS General Kenobi Scanner Canary"
note "Device: General Kenobi"
note "Run: Product > Run"
note "This is a local signing/launch rehearsal only; Cloud Run remains disabled/private."
note "Use the audited terminal harness separately for the real AI scan."

if [[ "$OPEN_PROJECT" == true ]]; then
  open "$ROOT/PCOS.xcodeproj"
fi
