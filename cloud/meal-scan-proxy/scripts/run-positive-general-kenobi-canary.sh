#!/usr/bin/env bash
# Approval-gated positive CycleBalance meal-scan canary for General Kenobi.
# The default path is a protocol-only dry run. Live use requires an exact owner confirmation.
set -euo pipefail

readonly PINNED_PROJECT_ID="cyclebalance-prod-20260710"
readonly PINNED_REGION="us-central1"
readonly PINNED_SERVICE_NAME="cyclebalance-meal-scan-proxy"
readonly PINNED_SERVICE_URL="https://cyclebalance-meal-scan-proxy-mdd7lrfyqa-uc.a.run.app"
readonly PINNED_APP_BUNDLE_ID="alex.PCOS"
readonly PINNED_APPLE_TEAM_ID="2PW989LA87"
readonly PINNED_DEVICE_NAME="General Kenobi"
readonly PINNED_DEVICE_ID="0C663BE9-3804-587C-BD8A-A2B4D38F998A"
readonly PINNED_BRANCH="codex/cyclebalance-1.0.5-rc"
readonly PINNED_FIREBASE_APP_ID="1:947929010052:ios:6e68c8645a6a6b5e3057d1"
readonly PINNED_APPLE_APP_ID="6760353511"
readonly PINNED_APPLE_PRODUCT_IDS="cyclebalance.premium.monthly,cyclebalance.premium.annual"
readonly PINNED_REVENUECAT_PROJECT_ID="proj8da4e000"
readonly PINNED_REVENUECAT_ENTITLEMENT_ID="CycleBalance Unlimited"
readonly PINNED_REVENUECAT_OFFERING_ID="default"
readonly PINNED_GEMINI_SECRET_NAME="cyclebalance-gemini-api-key"
readonly PINNED_PRINCIPAL_HMAC_SECRET_NAME="cyclebalance-meal-scan-principal-hmac"
readonly PINNED_APPLE_IAP_PRIVATE_KEY_SECRET_NAME="cyclebalance-app-store-iap-private-key"
readonly PINNED_REVENUECAT_SECRET_NAME="cyclebalance-revenuecat-secret-api-key"
readonly PINNED_PRINCIPAL_HMAC_SECRET_VERSION="1"
readonly PINNED_APPLE_IAP_PRIVATE_KEY_SECRET_VERSION="1"
readonly LIVE_CONFIRMATION_VALUE="I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN"
readonly MEAL_SCAN_ROLLING_QUOTA_COLLECTION="mealScanRollingQuota"
readonly MAX_LOG_ENTRIES=200
readonly MAX_FIRESTORE_SNAPSHOT_PAGES=100
readonly FIRESTORE_SNAPSHOT_PAGE_SIZE=100
readonly RESCAN_INGESTION_SKEW_BUFFER_SECONDS="600"
readonly CANARY_RECEIPT_ROOT="$HOME/Library/Application Support/CycleBalance/PositiveCanary"
readonly CANARY_RECEIPT_PATH="$CANARY_RECEIPT_ROOT/seed-receipt.json"

PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
REGION="${REGION:-$PINNED_REGION}"
SERVICE_NAME="${SERVICE_NAME:-$PINNED_SERVICE_NAME}"
SERVICE_URL="${SERVICE_URL:-$PINNED_SERVICE_URL}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-$PINNED_APP_BUNDLE_ID}"
DEVICE_NAME="${DEVICE_NAME:-$PINNED_DEVICE_NAME}"
DEVICE_ID="${DEVICE_ID:-$PINNED_DEVICE_ID}"
DRY_RUN="${DRY_RUN:-true}"
CANARY_PHASE="${CANARY_PHASE:-seed}"
CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY="${CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY:-}"
APPROVED_SOURCE_COMMIT="${APPROVED_SOURCE_COMMIT:-}"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROXY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "$PROXY_DIR/../.." && pwd)"
readonly PROJECT_YML="$REPOSITORY_ROOT/project.yml"
readonly DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-cloud-run.sh"
readonly EVIDENCE_HELPER="$SCRIPT_DIR/positive-canary-evidence.mjs"
readonly REVENUECAT_OFFERING_VERIFIER="$SCRIPT_DIR/verify-revenuecat-offering-v2.sh"
readonly APPLE_IAP_V1_PROVISIONER="$SCRIPT_DIR/provision-apple-iap-key-v1.sh"

TEMP_ROOT=""
EVIDENCE_DIR=""
EVIDENCE_SUMMARY=""
PROJECT_YML_SHA_BEFORE=""
XCODE_DEVICE_UDID=""
CANARY_APP_PATH=""
CANARY_REVISION=""
ROLLBACK_ARMED=false
ROLLBACK_COMPLETE=false
APP_WAS_INSTALLED=""
CANARY_APP_INSTALL_STARTED=false
CANARY_RUN_COMPLETED=false
CANARY_ID=""
CANARY_CORRELATION_ID=""
CANARY_QUOTA_TAG=""
LAST_FRESH_OPERATION_TAG=""
DEVICE_CONSOLE_PID=""
DEVICE_CONSOLE_LOG=""
DEVICE_CONSOLE_OFFSET=0
INITIAL_IAM_POLICY_FILE=""
INITIAL_IAM_POLICY_DIGEST=""
INITIAL_DISABLED_REVISION=""
FINAL_DISABLED_REVISION=""
ORIGINAL_APP_VERSION=""
ORIGINAL_APP_BUILD=""
ORIGINAL_APP_SIGNING_STATE=""
ORIGINAL_APP_DATA_BACKUP_STATE="none"
ORIGINAL_APP_DATA_BACKUP_PATH=""
CANARY_APP_VERSION=""
CANARY_APP_BUILD=""
CANARY_SIGNING_STATE=""
SEED_ROLLBACK_COMPLETED_EPOCH=""
SEED_RECEIPT_PENDING=false
RESCAN_RECEIPT_LOADED=false
GEMINI_SECRET_VERSION=""
PRINCIPAL_HMAC_SECRET_VERSION="$PINNED_PRINCIPAL_HMAC_SECRET_VERSION"
APPLE_IAP_PRIVATE_KEY_SECRET_VERSION="$PINNED_APPLE_IAP_PRIVATE_KEY_SECRET_VERSION"
REVENUECAT_SECRET_VERSION=""
APPLE_IAP_KEY_ID_VALUE=""
APPLE_IAP_ISSUER_ID_VALUE=""

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_equal() {
  local actual="$1"
  local expected="$2"
  local description="$3"
  [[ "$actual" == "$expected" ]] || die "$description (expected $expected, found $actual)"
}

require_unchanged() {
  local after="$1"
  local before="$2"
  local description="$3"
  [[ "$after" == "$before" ]] || die "$description"
}

sha256_text() {
  printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
}

receipt_rescan_is_due() {
  local receipt_file="$1"
  local now_epoch="${2:-$(date -u +%s)}"
  jq -e --argjson now "$now_epoch" '
    .schemaVersion == 1 and
    .lifecycle == "seed_rolled_back" and
    (.rescanNotBeforeEpoch | type == "number") and
    $now >= .rescanNotBeforeEpoch
  ' "$receipt_file" >/dev/null
}

canonical_iam_policy() {
  local policy_file="$1"
  jq -cS '{
    version: (.version // 1),
    bindings: ((.bindings // []) | map(
      {role, members: ((.members // []) | sort)} +
      (if .condition == null then {} else {condition: .condition} end)
    ) | sort_by(.role, (.condition.expression // ""))),
    auditConfigs: ((.auditConfigs // []) | sort_by(.service // ""))
  }' "$policy_file"
}

iam_policy_is_private() {
  local policy_file="$1"
  jq -e '
    [(.bindings // [])[]?.members[]?] as $members |
    ($members | index("allUsers") == null) and
    ($members | index("allAuthenticatedUsers") == null)
  ' "$policy_file" >/dev/null
}

invoker_iam_check_is_enabled() {
  local service_file="$1"
  jq -e '(.metadata.annotations["run.googleapis.com/invoker-iam-disabled"] // "false") != "true"' \
    "$service_file" >/dev/null
}

private_invoker_gate_rejects_status() {
  [[ "$1" == "403" || "$1" == "404" ]]
}

validate_pinned_identity() {
  require_equal "$PROJECT_ID" "$PINNED_PROJECT_ID" "The canary project is pinned"
  require_equal "$REGION" "$PINNED_REGION" "The canary region is pinned"
  require_equal "$SERVICE_NAME" "$PINNED_SERVICE_NAME" "The canary service is pinned"
  require_equal "$SERVICE_URL" "$PINNED_SERVICE_URL" "The canary endpoint is pinned"
  require_equal "$APP_BUNDLE_ID" "$PINNED_APP_BUNDLE_ID" "The canary bundle identity is pinned"
  require_equal "$DEVICE_NAME" "$PINNED_DEVICE_NAME" "The canary device name is pinned"
  require_equal "$DEVICE_ID" "$PINNED_DEVICE_ID" "The General Kenobi device identity is pinned"
  [[ -z "${DEVICE_UDID:-}" ]] || die "DEVICE_UDID overrides are not accepted; General Kenobi is pinned and Xcode identity is resolved uniquely"
  [[ "$CANARY_PHASE" == "seed" || "$CANARY_PHASE" == "rescan" ]] || die "CANARY_PHASE must be seed or rescan"
}

print_apple_iap_provisioning_handoff() {
  note "Owner-only Apple IAP provisioning handoff (staged; this canary never performs it):"
  note "- Inspect the non-mutating plan: DRY_RUN=true $APPLE_IAP_V1_PROVISIONER"
  note "- If and only if metadata proves zero existing versions, run the dedicated exact zero-to-enabled-v1 provisioner with its printed owner approval. It aborts on any existing version, prevents v2, and read-backs proxy-service-account-only secretAccessor IAM."
  note "- Enter the matching App Store IAP key ID and issuer ID only through the live canary's hidden terminal prompts; neither value is echoed or persisted."
  note "- Do not re-prompt, rotate, or replace the existing Gemini, RevenueCat, or principal-HMAC secrets. The live canary pipes only the pinned RevenueCat version memory-only into its read-only offering verifier."
  note "- The principal-HMAC resource is expected at pinned version $PINNED_PRINCIPAL_HMAC_SECRET_VERSION; its value and the Gemini key are never read by this harness."
}

verify_live_revenuecat_configuration() {
  note "Checking the live RevenueCat offering through read-only API v2 endpoints."
  gcloud secrets versions access "$REVENUECAT_SECRET_VERSION" \
    --secret "$PINNED_REVENUECAT_SECRET_NAME" \
    --project "$PROJECT_ID" | \
    DRY_RUN=false REVENUECAT_PROJECT_ID="$PINNED_REVENUECAT_PROJECT_ID" \
      "$REVENUECAT_OFFERING_VERIFIER" \
    || die "Live RevenueCat default/monthly/annual/entitlement verification failed closed"
  append_summary "Machine-read RevenueCat configuration: read-only API v2 verified current default, exact monthly/annual packages and products, and CycleBalance Unlimited attachments; API key was memory-only and not retained."
}

print_dry_run() {
  note "DRY RUN ONLY: no cloud, device, build, installation, backup, secret, or publication mutation will run."
  note "Pinned target: project $PROJECT_ID; region $REGION; service $SERVICE_NAME; endpoint $SERVICE_URL."
  note "Pinned app/device: $APP_BUNDLE_ID on $DEVICE_NAME ($DEVICE_ID)."
  note "1. Require exact live confirmation $LIVE_CONFIRMATION_VALUE before any live preflight or mutation."
  note "2. Require a full owner-approved source commit equal to clean HEAD, including no untracked files, and canonical project.yml Release scanner flags still NO."
  note "3. Snapshot canonical Cloud Run IAM, reject allUsers/allAuthenticatedUsers, require the invoker IAM check, MEAL_SCAN_ENABLED=false, normal budget, and pinned identifiers."
  note "4. Verify numeric secret-version metadata; then pipe only the pinned RevenueCat key memory-only into read-only default/monthly/annual/CycleBalance Unlimited configuration checks."
  print_apple_iap_provisioning_handoff
  note "5. Verify $DEVICE_NAME is uniquely resolved, paired, in Developer Mode, DDI-ready, and explicitly unlocked."
  note "6. On seed, record whether the app was initially present, its version/build/signing state, and a protected data backup; preserve the installed canary and local state through rescan."
  note "7. On seed only, build a nondistributable development-signed Release canary from the approved source, enabling only MEAL_SCAN_RELEASE_UI_ENABLED=YES and MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES."
  note "8. Strictly verify code signing, team/application ID, General Kenobi provisioning, bundle/endpoint, production App Attest, and locked-off mock/debug-direct/fallback/similarity settings."
  note "9. Recheck source/device, arm rollback, then temporarily deploy the App Check-protected endpoint enabled/public."
  note "10. Keep owner-observed UI evidence separate from machine-read evidence; an Enter key never proves a result."
  note "11. Guide active monthly/annual sandbox access, photo consent, editable review, adjustment, save/persistence, exact reuse, Scan as New, relaunch, camera denial/recovery, offline/timeout/retry, entitlement loss, quota, kill switch, barcode, and manual fallbacks."
  note "12. Bind fresh operations to a random development-only canary ID and request hash; require affirmative App Check, StoreKit JWS, current Apple status, RevenueCat, exact quota, cache, and provider evidence."
  note "13. Require exact local reuse to emit zero correlated events of every outcome and leave the exact correlated quota snapshot unchanged."
  note "14. Require Scan as New to add exactly one correlated quota delta, fresh dispatch, completed request, and provider start/completion; a server cache hit fails."
  note "After seed rollback, write a mode-0600 content-free receipt and keep the canary installed. Rescan stays blocked until the 24-hour TTL plus a 10-minute ingestion/skew buffer."
  note "The verified disabled/private rollback between the seed and rescan windows is mandatory; neither phase may span one invocation."
  note "15. Project logs through a strict field allowlist before persistence and reject unexpected fields, tokens, JWS/JWT, identifiers, PEM/OAuth/RevenueCat keys, photos/base64, or high-entropy payloads."
  note "16. On success, failure, signal, or interruption, use canary-only deploy mode, restore exact initial IAM, and verify private disabled transport. After final rescan restore the initially absent state or stop with an explicit manual binary/data restore handoff."
  note "This protocol prepares but does not itself close the positive sandbox-JWS real-device TestFlight, 80-image/120-call benchmark, or App Store distribution-profile gates."
}

resolve_xcode_device_udid() {
  local xcdevice_json="$1"
  local expected_name="$2"
  jq -er --arg expected_name "$expected_name" '
    [
      .[] |
      select(
        .name == $expected_name and
        .available == true and
        .simulator == false and
        .platform == "com.apple.platform.iphoneos" and
        (.identifier | type == "string") and
        (.identifier | length > 0)
      )
    ] |
    if length == 1 then .[0].identifier else empty end
  ' "$xcdevice_json"
}

device_lock_is_verified_unlocked() {
  local lock_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("passcodeRequired") and (.passcodeRequired | type == "boolean")
        then (.passcodeRequired == false) else empty end),
      (if has("isLocked") and (.isLocked | type == "boolean")
        then (.isLocked == false) else empty end),
      (if has("lockState") and (.lockState | type == "string") and
          ((.lockState | ascii_downcase) == "locked" or (.lockState | ascii_downcase) == "unlocked")
        then ((.lockState | ascii_downcase) == "unlocked") else empty end)
    ] as $states |
    (($states | length) > 0 and all($states[]; . == true))
  ' "$lock_json" >/dev/null
}

device_details_are_paired() {
  local details_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("isPaired") and (.isPaired | type == "boolean") then .isPaired else empty end),
      (if has("paired") and (.paired | type == "boolean") then .paired else empty end),
      (if has("pairingState") and (.pairingState | type == "string") and
          ((.pairingState | ascii_downcase) == "paired" or (.pairingState | ascii_downcase) == "unpaired")
        then ((.pairingState | ascii_downcase) == "paired") else empty end)
    ] as $states |
    (($states | length) > 0 and all($states[]; . == true))
  ' "$details_json" >/dev/null
}

device_details_have_developer_mode() {
  local details_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("developerModeEnabled") and (.developerModeEnabled | type == "boolean") then .developerModeEnabled else empty end),
      (if has("isDeveloperModeEnabled") and (.isDeveloperModeEnabled | type == "boolean") then .isDeveloperModeEnabled else empty end),
      (if has("developerModeStatus") and (.developerModeStatus | type == "string") and
          ((.developerModeStatus | ascii_downcase) == "enabled" or (.developerModeStatus | ascii_downcase) == "disabled")
        then ((.developerModeStatus | ascii_downcase) == "enabled") else empty end)
    ] as $states |
    (($states | length) > 0 and all($states[]; . == true))
  ' "$details_json" >/dev/null
}

device_ddi_is_usable() {
  local ddi_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("ddiMetadata") and (.ddiMetadata | type == "object") and
          (.ddiMetadata.isUsable | type == "boolean") and
          (.ddiMetadata.contentIsCompatible | type == "boolean")
        then (.ddiMetadata.isUsable == true and .ddiMetadata.contentIsCompatible == true)
      elif has("services") and (.services | type == "array") then (.services | length > 0)
      else empty end)
    ] as $states |
    (($states | length) > 0 and all($states[]; . == true))
  ' "$ddi_json" >/dev/null
}

device_app_inventory_is_valid() {
  local apps_json="$1"
  jq -e '
    .info.outcome == "success" and
    (.result.apps | type == "array") and
    all(.result.apps[]; (.bundleIdentifier | type == "string"))
  ' "$apps_json" >/dev/null
}

device_has_installed_app() {
  local apps_json="$1"
  local bundle_id="$2"
  jq -e --arg bundle_id "$bundle_id" 'any(.result.apps[]; .bundleIdentifier == $bundle_id)' "$apps_json" >/dev/null
}

release_override_allowlist_is_valid() {
  [[ "$#" -eq 2 ]] || return 1
  local saw_ui=false saw_gemini=false override
  for override in "$@"; do
    case "$override" in
      MEAL_SCAN_RELEASE_UI_ENABLED=YES) saw_ui=true ;;
      MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES) saw_gemini=true ;;
      *) return 1 ;;
    esac
  done
  [[ "$saw_ui" == true && "$saw_gemini" == true ]]
}

assert_canonical_release_flags() {
  local key value count
  for key in \
    MEAL_SCAN_RELEASE_UI_ENABLED \
    MEAL_SCAN_RELEASE_GEMINI_ENABLED \
    MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED \
    MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED \
    MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED \
    MEAL_SCAN_RELEASE_SIMILARITY_ENABLED; do
    value="$(awk -v key="$key" '$1 == key ":" { gsub(/["'\'' ]/, "", $2); print $2 }' "$PROJECT_YML")"
    count="$(awk -v key="$key" '$1 == key ":" { count += 1 } END { print count + 0 }' "$PROJECT_YML")"
    require_equal "$count" "1" "$key must appear exactly once in project.yml"
    require_equal "$value" "NO" "$key must remain canonically disabled"
  done
}

assert_no_prohibited_content() {
  local file="$1"
  ! LC_ALL=C grep -Eiq \
    'Authorization:[[:space:]]*Bearer|x-firebase-appcheck|app_?check_?token|signed_?transaction_?jws|store_?kit_?jws|original_?transaction_?id|transaction_?id|meal_name|mealName|display_name|data:image|/9j/|iVBORw0KGgo|-----BEGIN|ya29\.|sk_[[:alnum:]_-]{16,}|AIza[[:alnum:]_-]+' \
    "$file"
}

verify_phase_evidence() {
  local phase="$1"
  local evidence_file="$2"
  case "$phase" in
    exact-reuse)
      jq -e '
        .phase == "exact-reuse" and
        .eventCount == 0 and
        .quotaUnchanged == true
      ' "$evidence_file" >/dev/null
      ;;
    fresh-scan|scan-as-new)
      jq -e --arg phase "$phase" '
        .phase == $phase and
        .requestCompleted == 1 and
        .providerStarted == 1 and
        .providerCompleted == 1 and
        .quotaDelta == 1 and
        .cacheFreshDispatch == 1 and
        .authorizationControls == [
          "app_check",
          "storekit_jws",
          "apple_current_status",
          "revenuecat_subscription"
        ] and
        (.canaryQuotaTag | test("^[a-f0-9]{64}$"))
      ' "$evidence_file" >/dev/null
      ;;
    *) return 1 ;;
  esac
}

cleanup_temp() {
  [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]] && rm -rf "$TEMP_ROOT"
}

append_summary() {
  [[ -n "$EVIDENCE_SUMMARY" ]] || return 0
  printf '%s\n' "$*" >>"$EVIDENCE_SUMMARY"
  chmod 0600 "$EVIDENCE_SUMMARY"
}

prepare_evidence_directory() {
  local root
  root="$HOME/Library/Logs/CycleBalance/PositiveCanary"
  EVIDENCE_DIR="$root/$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  mkdir -p "$EVIDENCE_DIR"
  chmod 0700 "$root" "$EVIDENCE_DIR"
  EVIDENCE_SUMMARY="$EVIDENCE_DIR/evidence-summary.txt"
  : >"$EVIDENCE_SUMMARY"
  chmod 0600 "$EVIDENCE_SUMMARY"
  append_summary "CycleBalance positive canary evidence"
  append_summary "Evidence classification: machine-read aggregates and owner-observed UI notes are separate."
  append_summary "No photo, meal, token, JWS, transaction, purchase principal, or raw log content is retained."
}

load_seed_receipt() {
  [[ -f "$CANARY_RECEIPT_PATH" ]] || die "Rescan requires the owner-only seed receipt at $CANARY_RECEIPT_PATH"
  [[ "$(stat -f '%Lp' "$CANARY_RECEIPT_PATH")" == "600" ]] || die "Seed receipt permissions must be 0600"
  [[ "$(stat -f '%Lp' "$CANARY_RECEIPT_ROOT")" == "700" ]] || die "Seed receipt directory permissions must be 0700"
  jq -e \
    --arg project "$PINNED_PROJECT_ID" \
    --arg service "$PINNED_SERVICE_NAME" \
    --arg device "$PINNED_DEVICE_ID" '
      .schemaVersion == 1 and
      .lifecycle == "seed_rolled_back" and
      .projectId == $project and
      .serviceName == $service and
      .deviceCoreDeviceId == $device and
      (.approvedSourceCommit | test("^[a-f0-9]{40}$")) and
      (.canaryId | test("^[a-f0-9-]{36}$")) and
      (.canaryCorrelationId | test("^[a-f0-9]{64}$")) and
      (.canaryQuotaTag | test("^[a-f0-9]{64}$")) and
      (.iamPolicyDigest | test("^[a-f0-9]{64}$")) and
      (.seedRollbackCompletedEpoch | type == "number") and
      (.rescanNotBeforeEpoch | type == "number") and
      (.appInitiallyInstalled | type == "boolean") and
      (.originalApp | type == "object") and
      (.canaryApp | type == "object")
    ' "$CANARY_RECEIPT_PATH" >/dev/null || die "Seed receipt failed its strict content-free schema"
  receipt_rescan_is_due "$CANARY_RECEIPT_PATH" || die "Rescan is blocked until the 24-hour TTL plus ingestion/skew buffer has elapsed"

  CANARY_ID="$(jq -er '.canaryId' "$CANARY_RECEIPT_PATH")"
  CANARY_CORRELATION_ID="$(jq -er '.canaryCorrelationId' "$CANARY_RECEIPT_PATH")"
  CANARY_QUOTA_TAG="$(jq -er '.canaryQuotaTag' "$CANARY_RECEIPT_PATH")"
  APPROVED_SOURCE_COMMIT="$(jq -er '.approvedSourceCommit' "$CANARY_RECEIPT_PATH")"
  INITIAL_IAM_POLICY_DIGEST="$(jq -er '.iamPolicyDigest' "$CANARY_RECEIPT_PATH")"
  INITIAL_DISABLED_REVISION="$(jq -er '.disabledServiceRevision' "$CANARY_RECEIPT_PATH")"
  SEED_ROLLBACK_COMPLETED_EPOCH="$(jq -er '.seedRollbackCompletedEpoch' "$CANARY_RECEIPT_PATH")"
  XCODE_DEVICE_UDID="$(jq -er '.deviceXcodeUdid' "$CANARY_RECEIPT_PATH")"
  APP_WAS_INSTALLED="$(jq -er '.appInitiallyInstalled' "$CANARY_RECEIPT_PATH")"
  ORIGINAL_APP_VERSION="$(jq -er '.originalApp.version' "$CANARY_RECEIPT_PATH")"
  ORIGINAL_APP_BUILD="$(jq -er '.originalApp.build' "$CANARY_RECEIPT_PATH")"
  ORIGINAL_APP_SIGNING_STATE="$(jq -er '.originalApp.signingState' "$CANARY_RECEIPT_PATH")"
  ORIGINAL_APP_DATA_BACKUP_STATE="$(jq -er '.originalApp.dataBackupState' "$CANARY_RECEIPT_PATH")"
  ORIGINAL_APP_DATA_BACKUP_PATH="$(jq -er '.originalApp.dataBackupPath' "$CANARY_RECEIPT_PATH")"
  CANARY_APP_VERSION="$(jq -er '.canaryApp.version' "$CANARY_RECEIPT_PATH")"
  CANARY_APP_BUILD="$(jq -er '.canaryApp.build' "$CANARY_RECEIPT_PATH")"
  CANARY_SIGNING_STATE="$(jq -er '.canaryApp.signingState' "$CANARY_RECEIPT_PATH")"
  RESCAN_RECEIPT_LOADED=true
  append_summary "Machine-read lifecycle: content-free owner receipt loaded; buffered rescan boundary satisfied."
}

write_seed_receipt() {
  [[ "$CANARY_PHASE" == "seed" && "$SEED_RECEIPT_PENDING" == true ]] || return 0
  [[ -n "$CANARY_QUOTA_TAG" && -n "$FINAL_DISABLED_REVISION" ]] || return 1
  local now_epoch not_before receipt_temp
  now_epoch="$(date -u +%s)"
  not_before=$((now_epoch + 86400 + RESCAN_INGESTION_SKEW_BUFFER_SECONDS))
  umask 077
  mkdir -p "$CANARY_RECEIPT_ROOT"
  chmod 0700 "$CANARY_RECEIPT_ROOT"
  [[ ! -e "$CANARY_RECEIPT_PATH" ]] || return 1
  receipt_temp="$CANARY_RECEIPT_ROOT/.seed-receipt.$$.tmp"
  jq -n \
    --arg lifecycle "seed_rolled_back" \
    --arg project "$PROJECT_ID" \
    --arg service "$SERVICE_NAME" \
    --arg source "$APPROVED_SOURCE_COMMIT" \
    --arg canary_id "$CANARY_ID" \
    --arg correlation "$CANARY_CORRELATION_ID" \
    --arg quota_tag "$CANARY_QUOTA_TAG" \
    --arg enabled_revision "$CANARY_REVISION" \
    --arg disabled_revision "$FINAL_DISABLED_REVISION" \
    --arg iam_digest "$INITIAL_IAM_POLICY_DIGEST" \
    --arg core_device "$DEVICE_ID" \
    --arg xcode_udid "$XCODE_DEVICE_UDID" \
    --argjson installed "$APP_WAS_INSTALLED" \
    --arg original_version "$ORIGINAL_APP_VERSION" \
    --arg original_build "$ORIGINAL_APP_BUILD" \
    --arg original_signing "$ORIGINAL_APP_SIGNING_STATE" \
    --arg backup_state "$ORIGINAL_APP_DATA_BACKUP_STATE" \
    --arg backup_path "$ORIGINAL_APP_DATA_BACKUP_PATH" \
    --arg canary_version "$CANARY_APP_VERSION" \
    --arg canary_build "$CANARY_APP_BUILD" \
    --arg canary_signing "$CANARY_SIGNING_STATE" \
    --argjson rollback_epoch "$now_epoch" \
    --argjson rescan_epoch "$not_before" '
      {
        schemaVersion: 1,
        lifecycle: $lifecycle,
        projectId: $project,
        serviceName: $service,
        approvedSourceCommit: $source,
        canaryId: $canary_id,
        canaryCorrelationId: $correlation,
        canaryQuotaTag: $quota_tag,
        enabledServiceRevision: $enabled_revision,
        disabledServiceRevision: $disabled_revision,
        iamPolicyDigest: $iam_digest,
        seedRollbackCompletedEpoch: $rollback_epoch,
        rescanNotBeforeEpoch: $rescan_epoch,
        deviceCoreDeviceId: $core_device,
        deviceXcodeUdid: $xcode_udid,
        appInitiallyInstalled: $installed,
        originalApp: {
          version: $original_version,
          build: $original_build,
          signingState: $original_signing,
          binaryRestorable: false,
          dataBackupState: $backup_state,
          dataBackupPath: $backup_path
        },
        canaryApp: {
          version: $canary_version,
          build: $canary_build,
          signingState: $canary_signing
        }
      }
    ' >"$receipt_temp"
  chmod 0600 "$receipt_temp"
  mv "$receipt_temp" "$CANARY_RECEIPT_PATH"
  SEED_RECEIPT_PENDING=false
  append_summary "Machine-read lifecycle: owner-only content-free seed receipt persisted after verified rollback."
}

service_json() {
  gcloud run services describe "$SERVICE_NAME" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --format=json
}

service_env_value() {
  local service_file="$1"
  local name="$2"
  jq -er --arg name "$name" '
    [.spec.template.spec.containers[].env[]? | select(.name == $name) | .value] |
    if length == 1 and (.[0] | type == "string") then .[0] else empty end
  ' "$service_file"
}

single_enabled_secret_version() {
  local secret_name="$1"
  local versions
  versions="$(gcloud secrets versions list "$secret_name" \
    --project "$PROJECT_ID" \
    --filter='state=ENABLED' \
    --format='value(name)' | sed 's#.*/##')" || return 1
  [[ "$(printf '%s\n' "$versions" | sed '/^$/d' | wc -l | tr -d ' ')" == "1" ]] || return 1
  printf '%s\n' "$versions" | sed '/^$/d'
}

verify_secret_version_metadata() {
  local secret_name="$1"
  local version="$2"
  [[ "$version" =~ ^[1-9][0-9]*$ ]] || die "Secret $secret_name must use a pinned numeric version"
  gcloud secrets describe "$secret_name" --project "$PROJECT_ID" --format='value(name)' >/dev/null \
    || die "Secret resource $secret_name is missing. Use the owner-only provisioning handoff; never paste a secret into chat or arguments."
  require_equal "$(gcloud secrets versions describe "$version" --secret "$secret_name" --project "$PROJECT_ID" --format='value(state)')" \
    "ENABLED" "Secret $secret_name version $version must exist and be ENABLED"
}

load_and_verify_secret_metadata() {
  note "Checking secret resources and numeric versions without reading any values."
  GEMINI_SECRET_VERSION="$(single_enabled_secret_version "$PINNED_GEMINI_SECRET_NAME")" \
    || die "Gemini must have exactly one enabled numeric secret version; do not rotate it from this harness"
  REVENUECAT_SECRET_VERSION="$(single_enabled_secret_version "$PINNED_REVENUECAT_SECRET_NAME")" \
    || die "RevenueCat must have exactly one enabled numeric secret version; do not rotate it from this harness"
  verify_secret_version_metadata "$PINNED_GEMINI_SECRET_NAME" "$GEMINI_SECRET_VERSION"
  verify_secret_version_metadata "$PINNED_PRINCIPAL_HMAC_SECRET_NAME" "$PRINCIPAL_HMAC_SECRET_VERSION"
  verify_secret_version_metadata "$PINNED_APPLE_IAP_PRIVATE_KEY_SECRET_NAME" "$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION"
  verify_secret_version_metadata "$PINNED_REVENUECAT_SECRET_NAME" "$REVENUECAT_SECRET_VERSION"
  append_summary "Machine-read secret metadata: required resources and pinned numeric versions exist; values were not accessed."
}

read_hidden_apple_iap_identifiers() {
  local service_file="$1"
  APPLE_IAP_KEY_ID_VALUE="$(service_env_value "$service_file" APPLE_IAP_KEY_ID 2>/dev/null || true)"
  APPLE_IAP_ISSUER_ID_VALUE="$(service_env_value "$service_file" APPLE_IAP_ISSUER_ID 2>/dev/null || true)"

  if [[ ! "$APPLE_IAP_KEY_ID_VALUE" =~ ^[A-Za-z0-9]{4,128}$ ]]; then
    [[ -t 0 ]] || die "App Store IAP key ID is not configured; rerun interactively for the hidden owner-only handoff"
    read -rsp "App Store IAP key ID (hidden; not persisted): " APPLE_IAP_KEY_ID_VALUE
    printf '\n' >/dev/tty
  fi
  if [[ ! "$APPLE_IAP_ISSUER_ID_VALUE" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    [[ -t 0 ]] || die "App Store IAP issuer ID is not configured; rerun interactively for the hidden owner-only handoff"
    read -rsp "App Store IAP issuer ID (hidden; not persisted): " APPLE_IAP_ISSUER_ID_VALUE
    printf '\n' >/dev/tty
  fi
  [[ "$APPLE_IAP_KEY_ID_VALUE" =~ ^[A-Za-z0-9]{4,128}$ ]] || die "App Store IAP key ID format is invalid"
  [[ "$APPLE_IAP_ISSUER_ID_VALUE" =~ ^[0-9a-fA-F-]{36}$ ]] || die "App Store IAP issuer ID format is invalid"
  append_summary "Owner-only Apple IAP metadata: key and issuer identifiers were supplied through hidden input and not persisted."
}

firestore_document_json() {
  local collection="$1"
  local document_id="$2"
  local access_token response_file status
  access_token="$(gcloud auth print-access-token)" || return 1
  response_file="$(mktemp "$TEMP_ROOT/firestore-response.XXXXXX")" || return 1
  chmod 0600 "$response_file"
  status="$(printf 'header = "Authorization: Bearer %s"\n' "$access_token" | \
    curl --silent --show-error --config - --output "$response_file" --write-out '%{http_code}' \
      "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/$collection/$document_id")" || return 1
  unset access_token
  case "$status" in
    200) jq -c . "$response_file" ;;
    404) printf '{"__notFound":true}' ;;
    *) return 1 ;;
  esac
  rm -f "$response_file"
}

effective_budget_mode_from_json() {
  jq -er '
    def rank:
      if . == "normal" then 0
      elif . == "alert" then 1
      elif . == "degraded" then 2
      elif . == "disabled" then 3
      else -1 end;
    select(.__notFound != true) |
    [.fields.manualMode.stringValue?, .fields.billingMode.stringValue?] |
    map(select(rank >= 0)) |
    if length == 0 then empty else max_by(rank) end
  '
}

read_budget_mode() {
  local document
  document="$(firestore_document_json mealScanControls global)" || return 1
  effective_budget_mode_from_json <<<"$document"
}

verify_source_preconditions() {
  note "Checking current RC branch/source and canonical Release flags."
  local head_commit source_status
  require_equal "$(git rev-parse --show-toplevel)" "$REPOSITORY_ROOT" "Unexpected repository root"
  require_equal "$(git branch --show-current)" "$PINNED_BRANCH" "Unexpected canary branch"
  [[ "$APPROVED_SOURCE_COMMIT" =~ ^[a-f0-9]{40}$ ]] || die "Live canary requires APPROVED_SOURCE_COMMIT as a full reviewed commit"
  head_commit="$(git rev-parse HEAD)"
  require_equal "$head_commit" "$APPROVED_SOURCE_COMMIT" "Approved canary source commit must equal HEAD"
  source_status="$(git status --porcelain --untracked-files=all)"
  [[ -z "$source_status" ]] || die "Live canary requires a clean tracked and untracked worktree"
  assert_canonical_release_flags
  PROJECT_YML_SHA_BEFORE="$(shasum -a 256 "$PROJECT_YML" | awk '{print $1}')"
  append_summary "Machine-read source: clean pinned RC branch, approved commit matched HEAD, and canonical Release scanner flags NO."
}

verify_initial_cloud_state() {
  note "Checking Google Cloud service, pinned identifiers, private transport, disabled flag, and normal budget."
  local service_file service_url budget_mode unauthenticated_status response_file raw_iam_file
  local observed_iam_digest observed_revision expected_iam_digest expected_revision
  service_file="$TEMP_ROOT/initial-service.json"
  service_json >"$service_file"
  chmod 0600 "$service_file"
  require_equal "$(gcloud projects describe "$PROJECT_ID" --format='value(projectId)')" "$PROJECT_ID" "Unexpected Google Cloud project"
  service_url="$(jq -er '.status.url' "$service_file")"
  require_equal "$service_url" "$PINNED_SERVICE_URL" "Cloud Run URL drifted from the pinned endpoint"
  require_equal "$(service_env_value "$service_file" MEAL_SCAN_ENABLED)" "false" "MEAL_SCAN_ENABLED must initially be false"
  require_equal "$(service_env_value "$service_file" APP_CHECK_REQUIRED)" "true" "App Check must be required"
  require_equal "$(service_env_value "$service_file" FIREBASE_APP_ID)" "$PINNED_FIREBASE_APP_ID" "Firebase app ID mismatch"
  require_equal "$(service_env_value "$service_file" APPLE_BUNDLE_ID)" "$PINNED_APP_BUNDLE_ID" "Apple bundle ID mismatch"
  require_equal "$(service_env_value "$service_file" APPLE_APP_ID)" "$PINNED_APPLE_APP_ID" "Apple app ID mismatch"
  require_equal "$(service_env_value "$service_file" APPLE_ALLOWED_PRODUCT_IDS)" "$PINNED_APPLE_PRODUCT_IDS" "Apple product IDs mismatch"
  require_equal "$(service_env_value "$service_file" REVENUECAT_PROJECT_ID)" "$PINNED_REVENUECAT_PROJECT_ID" "RevenueCat project mismatch"
  require_equal "$(service_env_value "$service_file" REVENUECAT_ENTITLEMENT_ID)" "$PINNED_REVENUECAT_ENTITLEMENT_ID" "RevenueCat entitlement mismatch"
  invoker_iam_check_is_enabled "$service_file" || die "Cloud Run invoker IAM check must be enabled"
  read_hidden_apple_iap_identifiers "$service_file"

  budget_mode="$(read_budget_mode)" || die "Unable to read the Firestore budget control"
  require_equal "$budget_mode" "normal" "Budget mode must be normal before the canary"
  raw_iam_file="$TEMP_ROOT/initial-iam-raw.json"
  INITIAL_IAM_POLICY_FILE="$TEMP_ROOT/initial-iam-policy.json"
  gcloud run services get-iam-policy "$SERVICE_NAME" \
    --project "$PROJECT_ID" --region "$REGION" --format=json >"$raw_iam_file"
  chmod 0600 "$raw_iam_file"
  iam_policy_is_private "$raw_iam_file" \
    || die "Cloud Run IAM must reject allUsers and allAuthenticatedUsers before the canary"
  canonical_iam_policy "$raw_iam_file" >"$INITIAL_IAM_POLICY_FILE"
  chmod 0600 "$INITIAL_IAM_POLICY_FILE"
  rm -f "$raw_iam_file"
  observed_iam_digest="$(shasum -a 256 "$INITIAL_IAM_POLICY_FILE" | awk '{print $1}')"
  observed_revision="$(jq -er '.status.latestReadyRevisionName' "$service_file")"
  if [[ "$CANARY_PHASE" == "rescan" ]]; then
    expected_iam_digest="$INITIAL_IAM_POLICY_DIGEST"
    expected_revision="$INITIAL_DISABLED_REVISION"
    require_equal "$observed_iam_digest" "$expected_iam_digest" "Disabled-window IAM policy digest changed"
    require_equal "$observed_revision" "$expected_revision" "Disabled-window Cloud Run revision changed"
  fi
  INITIAL_IAM_POLICY_DIGEST="$observed_iam_digest"
  INITIAL_DISABLED_REVISION="$observed_revision"

  response_file="$TEMP_ROOT/initial-private-response.txt"
  unauthenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST "$SERVICE_URL/v1/meal-scans/estimate")" || die "Unable to verify private Cloud Run transport"
  private_invoker_gate_rejects_status "$unauthenticated_status" \
    || die "Private Cloud Run must reject anonymous transport with 403 or concealed 404"
  append_summary "Machine-read initial cloud: exact IAM snapshot private, invoker check enabled, disabled, normal budget, App Check required, pinned public identifiers."
}

verify_dormant_window_continuity() {
  [[ "$CANARY_PHASE" == "rescan" && "$RESCAN_RECEIPT_LOADED" == true ]] || return 0
  local audit_start audit_end_epoch audit_end audit_file
  audit_start="$(date -u -r "$SEED_ROLLBACK_COMPLETED_EPOCH" '+%Y-%m-%dT%H:%M:%SZ')"
  audit_end_epoch=$(($(date -u +%s) - RESCAN_INGESTION_SKEW_BUFFER_SECONDS))
  (( audit_end_epoch > SEED_ROLLBACK_COMPLETED_EPOCH )) || die "Dormant-window audit interval is not mature"
  audit_end="$(date -u -r "$audit_end_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
  audit_file="$TEMP_ROOT/dormant-cloud-run-audit.json"
  gcloud logging read \
    "protoPayload.serviceName=\"run.googleapis.com\" AND timestamp>=\"$audit_start\" AND timestamp<=\"$audit_end\" AND (protoPayload.methodName:\"Services.UpdateService\" OR protoPayload.methodName:\"Services.ReplaceService\" OR protoPayload.methodName:\"SetIamPolicy\")" \
    --project "$PROJECT_ID" \
    --limit=50 \
    --format=json >"$audit_file" || die "Unable to query the dormant Cloud Run audit interval"
  chmod 0600 "$audit_file"
  jq -e 'length == 0' "$audit_file" >/dev/null \
    || die "Cloud Run or IAM mutations were observed during the disabled/private dormant interval"
  rm -f "$audit_file"
  append_summary "Machine-read continuity: no Cloud Run service or IAM mutations were observed in the queried post-seed interval after excluding the ingestion/skew tail; current revision and IAM digest also match. This is bounded evidence, not an absolute audit proof."
}

verify_device_preconditions() {
  note "Checking pinned General Kenobi state without requesting a passcode."
  local devices_json details_json lock_json ddi_json xcdevice_json resolved_xcode_udid expected_xcode_udid
  devices_json="$TEMP_ROOT/devices.json"
  details_json="$TEMP_ROOT/device-details.json"
  lock_json="$TEMP_ROOT/device-lock.json"
  ddi_json="$TEMP_ROOT/device-ddi.json"
  xcdevice_json="$TEMP_ROOT/xcdevice.json"
  xcrun devicectl list devices --json-output "$devices_json" >/dev/null
  jq -e --arg device_id "$DEVICE_ID" --arg name "$DEVICE_NAME" '
    .. | objects | select((.identifier? // .udid? // "") == $device_id) |
    [.. | strings | select(. == $name)] | length > 0
  ' "$devices_json" >/dev/null || die "Pinned General Kenobi device identity was not found"
  xcrun devicectl device info details --device "$DEVICE_ID" --json-output "$details_json" >/dev/null
  device_details_are_paired "$details_json" || die "General Kenobi is not paired"
  device_details_have_developer_mode "$details_json" || die "General Kenobi Developer Mode is not enabled"
  xcrun devicectl device info lockState --device "$DEVICE_ID" --json-output "$lock_json" >/dev/null
  device_lock_is_verified_unlocked "$lock_json" || die "General Kenobi must be explicitly reported unlocked"
  xcrun devicectl device info ddiServices --auto-mount-ddis --device "$DEVICE_ID" --json-output "$ddi_json" >/dev/null \
    || die "Developer disk image could not be mounted"
  device_ddi_is_usable "$ddi_json" || die "Developer disk image services are not usable"
  xcrun xcdevice list >"$xcdevice_json" || die "Xcode could not list devices"
  expected_xcode_udid="$XCODE_DEVICE_UDID"
  resolved_xcode_udid="$(resolve_xcode_device_udid "$xcdevice_json" "$DEVICE_NAME")" \
    || die "Expected exactly one available physical Xcode destination named General Kenobi"
  if [[ "$CANARY_PHASE" == "rescan" ]]; then
    require_equal "$resolved_xcode_udid" "$expected_xcode_udid" "Xcode hardware UDID changed since the seed receipt"
  fi
  XCODE_DEVICE_UDID="$resolved_xcode_udid"
  jq -e --arg core_device_id "$DEVICE_ID" --arg xcode_udid "$XCODE_DEVICE_UDID" '
    [.. | objects |
      select((.identifier? // "") == $core_device_id) |
      [.. | strings] |
      select(index($xcode_udid) != null)
    ] | length == 1
  ' "$devices_json" >/dev/null \
    || die "CoreDevice identity did not cross-check to the uniquely resolved Xcode hardware UDID"
  append_summary "Machine-read device: paired, Developer Mode enabled, DDI usable, explicitly unlocked, and CoreDevice/Xcode identities cross-checked."
}

backup_app_data() {
  local apps_json backup_root backup_dir app_entry
  apps_json="$TEMP_ROOT/device-apps.json"
  xcrun devicectl device info apps --device "$DEVICE_ID" --json-output "$apps_json" >/dev/null \
    || die "CoreDevice could not read the app inventory"
  device_app_inventory_is_valid "$apps_json" || die "CoreDevice returned an invalid app inventory"
  if ! device_has_installed_app "$apps_json" "$APP_BUNDLE_ID"; then
    APP_WAS_INSTALLED=false
    ORIGINAL_APP_VERSION="absent"
    ORIGINAL_APP_BUILD="absent"
    ORIGINAL_APP_SIGNING_STATE="absent"
    ORIGINAL_APP_DATA_BACKUP_STATE="not_present"
    ORIGINAL_APP_DATA_BACKUP_PATH=""
    append_summary "Machine-read app backup: no existing app was installed; no data container was present."
    return
  fi
  APP_WAS_INSTALLED=true
  app_entry="$(jq -cer --arg bundle_id "$APP_BUNDLE_ID" '
    [.result.apps[] | select(.bundleIdentifier == $bundle_id)] |
    if length == 1 then .[0] else empty end
  ' "$apps_json")" || die "Existing app inventory was ambiguous"
  ORIGINAL_APP_VERSION="$(jq -er '.version // .shortVersion // .bundleShortVersion // "unknown"' <<<"$app_entry")"
  ORIGINAL_APP_BUILD="$(jq -er '.buildVersion // .bundleVersion // "unknown"' <<<"$app_entry")"
  ORIGINAL_APP_SIGNING_STATE="$(jq -er '
    if (.isDeveloperApp | type) == "boolean" then
      (if .isDeveloperApp then "developer" else "distribution_or_store" end)
    else "unknown" end
  ' <<<"$app_entry")"
  backup_root="$HOME/Library/Application Support/CycleBalance/DeviceBackups"
  backup_dir="$backup_root/$(date -u +%Y%m%dT%H%M%SZ)-positive-canary"
  umask 077
  mkdir -p "$backup_dir"
  chmod 0700 "$backup_root" "$backup_dir"
  xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --source . \
    --destination "$backup_dir" >/dev/null \
    || die "App-data backup failed; stop and complete an encrypted Finder backup before retrying"
  find "$backup_dir" -mindepth 1 -print -quit | grep -q . || die "App-data backup was empty"
  chmod -R go-rwx "$backup_dir"
  ORIGINAL_APP_DATA_BACKUP_STATE="app_data_container_copied"
  ORIGINAL_APP_DATA_BACKUP_PATH="$backup_dir"
  append_summary "Machine-read app backup: existing app data copied before installation with restrictive permissions."
}

app_attest_environment_from_app() {
  local app_path="$1"
  codesign --display --xml --entitlements - "$app_path" 2>/dev/null | \
    plutil -extract 'com\.apple\.developer\.devicecheck\.appattest-environment' raw -
}

build_setting_from_file() {
  local settings_file="$1"
  local key="$2"
  awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' "$settings_file"
}

build_and_inspect_release_canary() {
  local -a release_feature_overrides=(
    MEAL_SCAN_RELEASE_UI_ENABLED=YES
    MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES
  )
  release_override_allowlist_is_valid "${release_feature_overrides[@]}" \
    || die "Release canary feature override allowlist failed"

  note "Building Release canary from current RC without archive/export or provisioning updates."
  local build_settings app_path bundle_id proxy_url ui_enabled gemini_enabled app_attest profile_plist signing_log
  build_settings="$TEMP_ROOT/release-build-settings.txt"
  xcodebuild \
    -project "$REPOSITORY_ROOT/PCOS.xcodeproj" \
    -scheme PCOS \
    -configuration Release \
    -sdk iphoneos \
    -destination "platform=iOS,id=$XCODE_DEVICE_UDID" \
    -derivedDataPath "$TEMP_ROOT/DerivedData" \
    "${release_feature_overrides[@]}" \
    -showBuildSettings >"$build_settings"
  for key in \
    MEAL_SCAN_RELEASE_MOCK_DATA_ENABLED \
    MEAL_SCAN_RELEASE_DEBUG_DIRECT_ENABLED \
    MEAL_SCAN_RELEASE_FALLBACK_MODEL_ENABLED \
    MEAL_SCAN_RELEASE_SIMILARITY_ENABLED; do
    require_equal "$(build_setting_from_file "$build_settings" "$key")" "NO" "$key must stay disabled in the canary build"
  done
  require_equal "$(build_setting_from_file "$build_settings" MEAL_SCAN_PROXY_BASE_URL)" "$PINNED_SERVICE_URL" \
    "Release proxy URL must already be configured to the pinned production endpoint"

  xcodebuild \
    -project "$REPOSITORY_ROOT/PCOS.xcodeproj" \
    -scheme PCOS \
    -configuration Release \
    -sdk iphoneos \
    -destination "platform=iOS,id=$XCODE_DEVICE_UDID" \
    -derivedDataPath "$TEMP_ROOT/DerivedData" \
    "${release_feature_overrides[@]}" \
    build

  app_path="$(find "$TEMP_ROOT/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name 'PCOS.app' -print -quit)"
  [[ -n "$app_path" ]] || die "Release build did not produce PCOS.app"
  CANARY_APP_PATH="$app_path"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
  proxy_url="$(/usr/libexec/PlistBuddy -c 'Print :MEAL_SCAN_PROXY_BASE_URL' "$app_path/Info.plist")"
  ui_enabled="$(/usr/libexec/PlistBuddy -c 'Print :MealScanReleaseUIEnabled' "$app_path/Info.plist")"
  gemini_enabled="$(/usr/libexec/PlistBuddy -c 'Print :MealScanReleaseGeminiEnabled' "$app_path/Info.plist")"
  require_equal "$bundle_id" "$PINNED_APP_BUNDLE_ID" "Unexpected Release bundle ID"
  require_equal "${proxy_url%/}" "$PINNED_SERVICE_URL" "Unexpected Release proxy URL"
  require_equal "$ui_enabled" "true" "Built product scanner UI flag must be enabled"
  require_equal "$gemini_enabled" "true" "Built product Gemini flag must be enabled"
  CANARY_APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Info.plist")"
  CANARY_APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Info.plist")"
  codesign --verify --deep --strict --verbose=4 "$app_path" \
    || die "Release canary failed strict code-signature verification"
  app_attest="$(app_attest_environment_from_app "$app_path")" || die "Unable to inspect App Attest entitlement"
  require_equal "$app_attest" "production" "Release canary must use production App Attest"

  profile_plist="$TEMP_ROOT/embedded-profile.plist"
  security cms -D -i "$app_path/embedded.mobileprovision" >"$profile_plist" 2>/dev/null \
    || die "Release canary is missing a readable development provisioning profile"
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile_plist" | grep -qx true \
    || die "Release canary must be development signed with get-task-allow=true"
  /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile_plist" >/dev/null \
    || die "Release canary profile must contain ProvisionedDevices"
  plutil -extract TeamIdentifier json -o - "$profile_plist" | \
    jq -e --arg team "$PINNED_APPLE_TEAM_ID" 'length == 1 and .[0] == $team' >/dev/null \
    || die "Release canary profile TeamIdentifier is not the pinned CycleBalance team"
  require_equal \
    "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist")" \
    "$PINNED_APPLE_TEAM_ID.$PINNED_APP_BUNDLE_ID" \
    "Release canary application-identifier mismatch"
  require_equal \
    "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$profile_plist")" \
    "$PINNED_APPLE_TEAM_ID" \
    "Release canary signed team entitlement mismatch"
  plutil -extract ProvisionedDevices json -o - "$profile_plist" | \
    jq -e --arg udid "$XCODE_DEVICE_UDID" 'index($udid) != null' >/dev/null \
    || die "Release canary provisioning profile does not include General Kenobi's Xcode UDID"
  ! /usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$profile_plist" >/dev/null 2>&1 \
    || die "Enterprise provisioning is not allowed"
  ! /usr/libexec/PlistBuddy -c 'Print :Entitlements:beta-reports-active' "$profile_plist" 2>/dev/null | grep -qx true \
    || die "App Store/TestFlight distribution provisioning is not allowed"
  signing_log="$TEMP_ROOT/codesign-display.txt"
  codesign --display --verbose=4 "$app_path" >"$signing_log" 2>&1
  grep -q '^Authority=Apple Development:' "$signing_log" || die "Release canary must be signed by Apple Development"
  CANARY_SIGNING_STATE="apple_development_get_task_allow"

  assert_canonical_release_flags
  require_unchanged "$(shasum -a 256 "$PROJECT_YML" | awk '{print $1}')" "$PROJECT_YML_SHA_BEFORE" "project.yml changed during the canary build"
  append_summary "Machine-read build: development-signed Release app, pinned bundle/endpoint, production App Attest, only UI/Gemini signed gates enabled."
}

install_release_canary() {
  [[ -n "$CANARY_APP_PATH" ]] || die "Release canary product is missing"
  note "Installing the development-signed Release canary on General Kenobi."
  CANARY_APP_INSTALL_STARTED=true
  xcrun devicectl device install app --device "$DEVICE_ID" "$CANARY_APP_PATH" --quiet --timeout 60 \
    || die "Canary app installation failed"
  append_summary "Machine-read installation: development-signed Release canary installed after backup preflight."
}

verify_installed_canary_continuity() {
  local apps_json app_entry observed_version observed_build observed_signing
  apps_json="$TEMP_ROOT/canary-apps.json"
  xcrun devicectl device info apps --device "$DEVICE_ID" --json-output "$apps_json" >/dev/null \
    || die "CoreDevice could not verify the installed canary"
  device_app_inventory_is_valid "$apps_json" || die "CoreDevice returned an invalid app inventory"
  app_entry="$(jq -cer --arg bundle_id "$APP_BUNDLE_ID" '
    [.result.apps[] | select(.bundleIdentifier == $bundle_id)] |
    if length == 1 then .[0] else empty end
  ' "$apps_json")" || die "The installed CycleBalance canary is missing or ambiguous"
  observed_version="$(jq -er '.version // .shortVersion // .bundleShortVersion // "unknown"' <<<"$app_entry")"
  observed_build="$(jq -er '.buildVersion // .bundleVersion // "unknown"' <<<"$app_entry")"
  observed_signing="$(jq -er '
    if (.isDeveloperApp | type) == "boolean" and .isDeveloperApp then
      "apple_development_get_task_allow"
    else "unknown_or_distribution" end
  ' <<<"$app_entry")"
  require_equal "$observed_version" "$CANARY_APP_VERSION" "Installed canary version changed"
  require_equal "$observed_build" "$CANARY_APP_BUILD" "Installed canary build changed"
  require_equal "$observed_signing" "$CANARY_SIGNING_STATE" "Installed canary signing state changed"
  append_summary "Machine-read app continuity: canary version, build, and development-signing state match the seed record."
}

launch_canary_with_console() {
  [[ -n "$CANARY_ID" ]] || die "Canary launch ID is missing"
  DEVICE_CONSOLE_LOG="$TEMP_ROOT/device-console.log"
  : >"$DEVICE_CONSOLE_LOG"
  chmod 0600 "$DEVICE_CONSOLE_LOG"
  xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --terminate-existing \
    --console \
    --timeout 7200 \
    "$APP_BUNDLE_ID" \
    --cyclebalance-meal-scan-canary-id "$CANARY_ID" \
    >"$DEVICE_CONSOLE_LOG" 2>&1 &
  DEVICE_CONSOLE_PID=$!
  sleep 3
  kill -0 "$DEVICE_CONSOLE_PID" 2>/dev/null \
    || die "The nondistributable canary did not remain attached to the device console"
  DEVICE_CONSOLE_OFFSET="$(wc -c <"$DEVICE_CONSOLE_LOG" | tr -d ' ')"
  append_summary "Machine-read launch: development-signed canary accepted the non-feature launch nonce path; only operation hashes may enter the console evidence window."
}

stop_device_console() {
  [[ -n "$DEVICE_CONSOLE_PID" ]] || return 0
  if kill -0 "$DEVICE_CONSOLE_PID" 2>/dev/null; then
    kill -TERM "$DEVICE_CONSOLE_PID" 2>/dev/null || true
    wait "$DEVICE_CONSOLE_PID" 2>/dev/null || true
  fi
  DEVICE_CONSOLE_PID=""
}

device_console_operation_for_phase() {
  local phase="$1"
  local segment_file tags count current_size
  segment_file="$TEMP_ROOT/${phase}-device-console-segment.txt"
  tail -c "+$((DEVICE_CONSOLE_OFFSET + 1))" "$DEVICE_CONSOLE_LOG" >"$segment_file"
  tags="$(sed -nE 's/^.*CYCLEBALANCE_CANARY_OPERATION tag=([a-f0-9]{64}).*$/\1/p' "$segment_file" | sort -u)"
  rm -f "$segment_file"
  current_size="$(wc -c <"$DEVICE_CONSOLE_LOG" | tr -d ' ')"
  DEVICE_CONSOLE_OFFSET="$current_size"
  count="$(grep -c . <<<"$tags" || true)"
  if [[ "$phase" == "exact-reuse" ]]; then
    [[ -z "$tags" ]] || die "Exact local reuse unexpectedly reached the proxy-client dispatch boundary"
    [[ -n "$LAST_FRESH_OPERATION_TAG" ]] || die "Exact reuse has no prior fresh operation tag for its zero-event query"
    printf '%s\n' "$LAST_FRESH_OPERATION_TAG"
    return
  fi
  [[ "$count" == "1" && "$tags" =~ ^[a-f0-9]{64}$ ]] \
    || die "$phase must emit exactly one content-free operation hash immediately before network dispatch"
  LAST_FRESH_OPERATION_TAG="$tags"
  printf '%s\n' "$tags"
}

deploy_environment() {
  local enabled="$1"
  local allow_unauthenticated="$2"
  (
    cd "$PROXY_DIR"
    PROJECT_ID="$PROJECT_ID" \
    REGION="$REGION" \
    SERVICE_NAME="$SERVICE_NAME" \
    FIREBASE_APP_ID="$PINNED_FIREBASE_APP_ID" \
    APPLE_BUNDLE_ID="$PINNED_APP_BUNDLE_ID" \
    APPLE_APP_ID="$PINNED_APPLE_APP_ID" \
    APPLE_ALLOWED_PRODUCT_IDS="$PINNED_APPLE_PRODUCT_IDS" \
    APPLE_IAP_KEY_ID="$APPLE_IAP_KEY_ID_VALUE" \
    APPLE_IAP_ISSUER_ID="$APPLE_IAP_ISSUER_ID_VALUE" \
    REVENUECAT_PROJECT_ID="$PINNED_REVENUECAT_PROJECT_ID" \
    REVENUECAT_ENTITLEMENT_ID="$PINNED_REVENUECAT_ENTITLEMENT_ID" \
    GEMINI_SECRET_VERSION="$GEMINI_SECRET_VERSION" \
    PRINCIPAL_HMAC_SECRET_VERSION="$PRINCIPAL_HMAC_SECRET_VERSION" \
    APPLE_IAP_PRIVATE_KEY_SECRET_VERSION="$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION" \
    REVENUECAT_SECRET_VERSION="$REVENUECAT_SECRET_VERSION" \
    DEPLOY_MODE=canary \
    MEAL_SCAN_CANARY_CORRELATION_SHA256="$CANARY_CORRELATION_ID" \
    MEAL_SCAN_ENABLED="$enabled" \
    ALLOW_UNAUTHENTICATED="$allow_unauthenticated" \
    "$DEPLOY_SCRIPT"
  )
}

deploy_temporarily_enabled_public() {
  note "Temporarily deploying current RC proxy source enabled/public behind required Firebase App Check."
  deploy_environment true true
  local service_file
  service_file="$TEMP_ROOT/enabled-service.json"
  service_json >"$service_file"
  require_equal "$(service_env_value "$service_file" MEAL_SCAN_ENABLED)" "true" "Temporary revision must be enabled"
  require_equal "$(service_env_value "$service_file" APP_CHECK_REQUIRED)" "true" "Temporary revision must require App Check"
  CANARY_REVISION="$(jq -er '.status.latestReadyRevisionName' "$service_file")"
  append_summary "Machine-read temporary service: current RC proxy enabled/public with App Check required."
}

deploy_disabled_private() {
  deploy_environment false false
}

restore_initial_iam_policy() {
  [[ -s "$INITIAL_IAM_POLICY_FILE" ]] || return 1
  gcloud run services set-iam-policy "$SERVICE_NAME" "$INITIAL_IAM_POLICY_FILE" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --quiet >/dev/null
}

verify_final_disabled_private() {
  local service_file unauthenticated_status authenticated_status response_file identity_token
  local final_iam_raw final_iam_canonical
  service_file="$TEMP_ROOT/final-service.json"
  service_json >"$service_file" || return 1
  require_equal "$(service_env_value "$service_file" MEAL_SCAN_ENABLED)" "false" "Final service must be disabled"
  invoker_iam_check_is_enabled "$service_file" || return 1
  FINAL_DISABLED_REVISION="$(jq -er '.status.latestReadyRevisionName' "$service_file")" || return 1
  final_iam_raw="$TEMP_ROOT/final-iam-raw.json"
  final_iam_canonical="$TEMP_ROOT/final-iam-policy.json"
  gcloud run services get-iam-policy "$SERVICE_NAME" \
    --project "$PROJECT_ID" --region "$REGION" --format=json >"$final_iam_raw" || return 1
  iam_policy_is_private "$final_iam_raw" || return 1
  canonical_iam_policy "$final_iam_raw" >"$final_iam_canonical" || return 1
  cmp -s "$INITIAL_IAM_POLICY_FILE" "$final_iam_canonical" || return 1
  require_equal \
    "$(shasum -a 256 "$final_iam_canonical" | awk '{print $1}')" \
    "$INITIAL_IAM_POLICY_DIGEST" \
    "Final IAM policy digest differs from the exact initial snapshot" || return 1
  response_file="$TEMP_ROOT/final-response.json"
  unauthenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  private_invoker_gate_rejects_status "$unauthenticated_status" || return 1
  identity_token="$(gcloud auth print-identity-token)" || return 1
  authenticated_status="$(printf 'header = "Authorization: Bearer %s"\n' "$identity_token" | \
    curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
      --request POST --config - "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  unset identity_token
  [[ "$authenticated_status" == "503" ]] || return 1
  jq -e '.error == "meal_scan_unavailable" and .reason == "feature_disabled"' "$response_file" >/dev/null
}

run_owner_guided_canary() {
  note "Owner-observed UI evidence is guidance only; pressing Return is never machine proof."
  note "Machine-read evidence will independently evaluate server request, authorization, quota, cache, and provider counters."
  append_summary "Owner-observed UI evidence: all entries below are explicitly unverified by automation."
  case "$CANARY_PHASE" in
    seed)
      capture_and_verify_phase fresh-scan \
        "Owner step A: confirm an active monthly or annual sandbox transaction; choose a non-sensitive canary meal photo; read and accept the per-upload Google Gemini consent; review and adjust the editable draft; save; relaunch; verify persistence."
      capture_and_verify_phase exact-reuse \
        "Owner step B: select the exact same photo and choose Use Previous Meal; review without triggering a fresh upload."
      record_owner_only_observation \
        "Owner step C: separately exercise camera denial/recovery, offline/timeout/retry, sandbox entitlement loss, displayed quota state, remote kill-switch messaging, barcode fallback, and manual fallback. Do not enter any health detail into this terminal." \
        "denial/recovery, network retry, entitlement, quota, kill-switch, barcode, and manual fallbacks"
      note "Seed window complete. Rollback now; keep the service disabled/private beyond the 24-hour server cache TTL before the separately approved rescan window."
      append_summary "Protocol state: seed window complete; Scan as New remains pending a separate post-TTL rescan invocation."
      ;;
    rescan)
      capture_and_verify_phase scan-as-new \
        "Owner rescan step: using the exact locally saved repeat photo from the earlier seed window after more than 24 hours, choose Scan as New and complete the consent/review flow. Abort if the local repeat is missing or the server cache may still be live."
      note "Rescan window complete. This verifies canary arithmetic only; TestFlight and other release gates remain open."
      append_summary "Protocol state: uncached Scan as New rescan window complete; TestFlight and release gates remain open."
      ;;
  esac
}

record_owner_only_observation() {
  local instructions="$1"
  local summary="$2"
  note "$instructions"
  read -r -p "Press Return after this owner-observed review, or Ctrl-C to abort: "
  append_summary "Owner-observed UI evidence: $summary were owner-reported; not machine proof."
}

capture_quota_documents() {
  local output_file="$1"
  local access_token documents_file response_file status page_token next_page_token query_url encoded page_count captured_at
  access_token="$(gcloud auth print-access-token)" || return 1
  documents_file="$(mktemp "$TEMP_ROOT/firestore-quota-documents.XXXXXX")" || return 1
  chmod 0600 "$documents_file"
  page_token=""
  page_count=0
  while true; do
    page_count=$((page_count + 1))
    (( page_count <= MAX_FIRESTORE_SNAPSHOT_PAGES )) || return 1
    query_url="https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/$MEAL_SCAN_ROLLING_QUOTA_COLLECTION?pageSize=$FIRESTORE_SNAPSHOT_PAGE_SIZE&orderBy=__name__"
    if [[ -n "$page_token" ]]; then
      encoded="$(jq -rn --arg value "$page_token" '$value | @uri')" || return 1
      query_url="${query_url}&pageToken=$encoded"
    fi
    response_file="$(mktemp "$TEMP_ROOT/firestore-quota-response.XXXXXX")" || return 1
    status="$(printf 'header = "Authorization: Bearer %s"\n' "$access_token" | \
      curl --silent --show-error --config - --output "$response_file" --write-out '%{http_code}' "$query_url")" || return 1
    [[ "$status" == "200" ]] || return 1
    jq -cS '(.documents // [])[] | {name, fields: (.fields // {}), updateTime: (.updateTime // null)}' "$response_file" >>"$documents_file"
    next_page_token="$(jq -er '.nextPageToken // ""' "$response_file")" || return 1
    rm -f "$response_file"
    [[ -n "$next_page_token" ]] || break
    page_token="$next_page_token"
  done
  unset access_token
  captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -s --arg captured_at "$captured_at" \
    '{capturedAt: $captured_at, documents: .}' "$documents_file" >"$output_file"
  chmod 0600 "$output_file"
  rm -f "$documents_file"
}

capture_phase_window() {
  local phase="$1"
  local start_utc="$2"
  local end_utc="$3"
  local operation_tag="$4"
  local quota_before_raw="$5"
  local quota_after_raw="$6"
  local output_file="$7"
  local events_file quota_before_file quota_after_file quota_tag
  events_file="$TEMP_ROOT/${phase}-safe-events.json"
  quota_before_file="$TEMP_ROOT/${phase}-safe-quota-before.json"
  quota_after_file="$TEMP_ROOT/${phase}-safe-quota-after.json"
  gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.revision_name=\"$CANARY_REVISION\" AND timestamp>=\"$start_utc\" AND timestamp<=\"$end_utc\" AND (jsonPayload.canaryCorrelationId=\"$CANARY_CORRELATION_ID\" OR textPayload:\"$CANARY_CORRELATION_ID\") AND (logName:\"run.googleapis.com%2Fstdout\" OR logName:\"run.googleapis.com%2Fstderr\")" \
    --project "$PROJECT_ID" \
    --limit=$((MAX_LOG_ENTRIES + 1)) \
    --format=json | node "$EVIDENCE_HELPER" project-events \
      --correlation "$CANARY_CORRELATION_ID" \
      --operation "$operation_tag" >"$events_file" \
    || die "Strict canary log projection rejected the evidence window"
  chmod 0600 "$events_file"

  if [[ "$phase" == "exact-reuse" ]]; then
    quota_tag="$CANARY_QUOTA_TAG"
  else
    quota_tag="$(jq -er '
      [.[] | select(
        .eventType == "quota_decision" and
        .outcome == "allowed" and
        .quotaDelta == 1 and
        (.canaryQuotaTag | type == "string")
      ) | .canaryQuotaTag] |
      if length == 1 then .[0] else empty end
    ' "$events_file")" || die "$phase did not yield one correlated quota tag"
  fi
  [[ "$quota_tag" =~ ^[a-f0-9]{64}$ ]] || die "Correlated quota tag is invalid"

  node "$EVIDENCE_HELPER" quota-snapshot \
    --canary-id "$CANARY_ID" --quota-tag "$quota_tag" \
    <"$quota_before_raw" >"$quota_before_file" \
    || die "Before-quota projection failed"
  node "$EVIDENCE_HELPER" quota-snapshot \
    --canary-id "$CANARY_ID" --quota-tag "$quota_tag" \
    <"$quota_after_raw" >"$quota_after_file" \
    || die "After-quota projection failed"
  rm -f "$quota_before_raw" "$quota_after_raw"
  chmod 0600 "$quota_before_file" "$quota_after_file"

  jq -n \
    --arg phase "$phase" \
    --slurpfile events "$events_file" \
    --slurpfile quota_before "$quota_before_file" \
    --slurpfile quota_after "$quota_after_file" \
    '{phase: $phase, events: $events[0], quotaBefore: $quota_before[0], quotaAfter: $quota_after[0]}' | \
    node "$EVIDENCE_HELPER" verify-phase >"$output_file" \
    || die "$phase correlated evidence arithmetic failed"
  rm -f "$events_file" "$quota_before_file" "$quota_after_file"
  chmod 0600 "$output_file"
}

capture_and_verify_phase() {
  local phase="$1"
  local instructions="$2"
  local quota_before_raw quota_after_raw start_utc end_utc evidence_file operation_tag
  quota_before_raw="$TEMP_ROOT/${phase}-quota-before-raw.json"
  quota_after_raw="$TEMP_ROOT/${phase}-quota-after-raw.json"
  capture_quota_documents "$quota_before_raw" || die "Unable to read ephemeral quota state before $phase"
  start_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "Machine-read evidence window for $phase starts now. Perform only this named action:"
  note "$instructions"
  read -r -p "Press Return immediately after the named $phase action finishes so machine evidence can close the window: "
  end_utc="$(date -u -v+3S +%Y-%m-%dT%H:%M:%SZ)"
  operation_tag="$(device_console_operation_for_phase "$phase")"
  capture_quota_documents "$quota_after_raw" || die "Unable to read ephemeral quota state after $phase"
  sleep 10
  evidence_file="$TEMP_ROOT/${phase}-evidence.json"
  capture_phase_window \
    "$phase" "$start_utc" "$end_utc" "$operation_tag" \
    "$quota_before_raw" "$quota_after_raw" "$evidence_file"
  verify_phase_evidence "$phase" "$evidence_file" || die "$phase machine-read evidence arithmetic failed"
  case "$phase" in
    exact-reuse)
      append_summary "Owner-observed UI evidence: exact local reuse was owner-reported; not machine proof."
      append_summary "Machine-read exact reuse: zero correlated events of every outcome and the exact correlated quota snapshot remained unchanged."
      ;;
    fresh-scan|scan-as-new)
      CANARY_QUOTA_TAG="$(jq -er '.canaryQuotaTag' "$evidence_file")"
      append_summary "Owner-observed UI evidence: $phase flow was owner-reported; not machine proof."
      append_summary "Machine-read $phase: four affirmative App Check/StoreKit/current-Apple/RevenueCat controls, one exact correlated quota delta, one fresh dispatch, one completed provider operation, and strict content-free projection."
      ;;
  esac
}

uninstall_and_verify_initial_absence() {
  local apps_json
  xcrun devicectl device uninstall app --device "$DEVICE_ID" "$APP_BUNDLE_ID" --quiet --timeout 30 \
    || return 1
  apps_json="$TEMP_ROOT/post-uninstall-apps.json"
  xcrun devicectl device info apps --device "$DEVICE_ID" --json-output "$apps_json" >/dev/null \
    || return 1
  device_app_inventory_is_valid "$apps_json" || return 1
  ! device_has_installed_app "$apps_json" "$APP_BUNDLE_ID"
}

mark_receipt_manual_restore_required() {
  local receipt_temp
  receipt_temp="$CANARY_RECEIPT_ROOT/.manual-restore.$$.tmp"
  jq '.lifecycle = "manual_restore_required"' "$CANARY_RECEIPT_PATH" >"$receipt_temp" || return 1
  chmod 0600 "$receipt_temp"
  mv "$receipt_temp" "$CANARY_RECEIPT_PATH"
}

finalize_device_lifecycle() {
  local incoming_status="$1"
  if [[ "$CANARY_PHASE" == "seed" ]]; then
    if [[ "$incoming_status" == "0" && "$CANARY_RUN_COMPLETED" == true && "$ROLLBACK_COMPLETE" == true ]]; then
      write_seed_receipt || return 1
      note "Seed lifecycle complete: the canary remains installed with its local repeat state for the buffered rescan window."
      append_summary "Machine-read device lifecycle: seed canary intentionally remains installed; app data and local repeat state are preserved for rescan."
      return 0
    fi
    if [[ "$CANARY_APP_INSTALL_STARTED" == true && "$APP_WAS_INSTALLED" == false ]]; then
      note "Failed seed cleanup: restoring the initially absent app state."
      uninstall_and_verify_initial_absence || return 1
    elif [[ "$CANARY_APP_INSTALL_STARTED" == true && "$APP_WAS_INSTALLED" == true ]]; then
      note "MANUAL RESTORE REQUIRED: the original binary could not be exported. Reinstall CycleBalance $ORIGINAL_APP_VERSION ($ORIGINAL_APP_BUILD), verify signing state $ORIGINAL_APP_SIGNING_STATE, then restore the protected app-data backup at $ORIGINAL_APP_DATA_BACKUP_PATH." >&2
      return 1
    fi
    return 0
  fi

  if [[ "$incoming_status" != "0" || "$CANARY_RUN_COMPLETED" != true || "$ROLLBACK_COMPLETE" != true ]]; then
    note "Rescan did not complete; the owner-only receipt and installed canary are retained for a controlled retry after review." >&2
    return 0
  fi
  if [[ "$APP_WAS_INSTALLED" == false ]]; then
    note "Final rescan cleanup: restoring and verifying the initially absent app state."
    uninstall_and_verify_initial_absence || return 1
    rm -f "$CANARY_RECEIPT_PATH"
    append_summary "Machine-read device lifecycle: final canary removed, initially absent state verified, and seed receipt retired."
    return 0
  fi

  mark_receipt_manual_restore_required || return 1
  note "MANUAL RESTORE REQUIRED: the original binary was not exportable. Reinstall CycleBalance $ORIGINAL_APP_VERSION ($ORIGINAL_APP_BUILD), verify signing state $ORIGINAL_APP_SIGNING_STATE, and restore/verify the protected data at $ORIGINAL_APP_DATA_BACKUP_PATH. The receipt remains until that handoff is complete." >&2
  append_summary "Machine-read device lifecycle: manual restore required because the originally present app binary was not exportable; receipt and protected app-data backup retained."
  return 1
}

rollback() {
  local status=$?
  set +e
  stop_device_console
  if [[ "$ROLLBACK_ARMED" == true && "$ROLLBACK_COMPLETE" == false ]]; then
    note "Rollback: redeploying disabled/private, restoring the exact IAM snapshot, and verifying transport plus feature kill switch."
    if deploy_disabled_private && restore_initial_iam_policy && verify_final_disabled_private; then
      ROLLBACK_COMPLETE=true
      append_summary "Machine-read rollback: exact initial IAM restored; invoker check enabled; final service private; anonymous 403/404; authenticated 503 feature_disabled."
      note "Rollback verification passed."
    else
      note "FATAL: rollback deploy or disabled/private verification failed; investigate Cloud Run immediately." >&2
      append_summary "Machine-read rollback: FAILED; immediate owner investigation required."
      status=1
    fi
  fi
  if ! finalize_device_lifecycle "$status"; then
    note "FATAL: device lifecycle restoration or handoff is incomplete." >&2
    status=1
  fi
  APPLE_IAP_KEY_ID_VALUE=""
  APPLE_IAP_ISSUER_ID_VALUE=""
  cleanup_temp
  if [[ -n "$EVIDENCE_DIR" ]]; then
    note "Permission-restricted evidence summary: $EVIDENCE_DIR"
  fi
  exit "$status"
}

main() {
  validate_pinned_identity
  case "$DRY_RUN" in
    true) print_dry_run; return ;;
    false) ;;
    *) die "DRY_RUN must be true or false" ;;
  esac

  [[ "$CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY" == "$LIVE_CONFIRMATION_VALUE" ]] \
    || die "Live execution requires CONFIRM_GENERAL_KENOBI_POSITIVE_CANARY=$LIVE_CONFIRMATION_VALUE"

  for command in gcloud jq curl node npm xcodebuild xcrun codesign security plutil shasum git awk sed grep find uuidgen stat cmp sort tail; do
    require_command "$command"
  done
  [[ -x "$DEPLOY_SCRIPT" ]] || die "Missing executable deploy script: $DEPLOY_SCRIPT"
  [[ -x "$EVIDENCE_HELPER" ]] || die "Missing executable strict evidence helper: $EVIDENCE_HELPER"
  [[ -x "$REVENUECAT_OFFERING_VERIFIER" ]] || die "Missing executable RevenueCat offering verifier: $REVENUECAT_OFFERING_VERIFIER"
  [[ -x "$APPLE_IAP_V1_PROVISIONER" ]] || die "Missing executable Apple IAP v1 provisioner: $APPLE_IAP_V1_PROVISIONER"
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-positive-canary.XXXXXX")"
  umask 077
  prepare_evidence_directory
  case "$CANARY_PHASE" in
    seed)
      [[ ! -e "$CANARY_RECEIPT_PATH" ]] \
        || die "Seed is blocked while an owner-only canary receipt already exists"
      CANARY_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
      [[ "$CANARY_ID" =~ ^[a-f0-9-]{36}$ ]] || die "Unable to generate a canonical random canary ID"
      CANARY_CORRELATION_ID="$(sha256_text "$CANARY_ID")"
      ;;
    rescan)
      load_seed_receipt
      ;;
  esac
  verify_source_preconditions
  load_and_verify_secret_metadata
  verify_live_revenuecat_configuration
  verify_initial_cloud_state
  verify_dormant_window_continuity
  verify_device_preconditions
  case "$CANARY_PHASE" in
    seed)
      backup_app_data
      build_and_inspect_release_canary
      verify_device_preconditions
      install_release_canary
      ;;
    rescan) ;;
  esac
  verify_device_preconditions
  verify_installed_canary_continuity
  launch_canary_with_console
  assert_canonical_release_flags
  require_unchanged "$(shasum -a 256 "$PROJECT_YML" | awk '{print $1}')" "$PROJECT_YML_SHA_BEFORE" "project.yml changed before cloud mutation"

  # The trap is already installed; this arm switch is set before the first cloud mutation.
  ROLLBACK_ARMED=true
  deploy_temporarily_enabled_public
  run_owner_guided_canary
  CANARY_RUN_COMPLETED=true
  if [[ "$CANARY_PHASE" == "seed" ]]; then
    SEED_RECEIPT_PENDING=true
  fi
  note "Positive canary protocol completed; rollback will now restore disabled/private state."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap rollback EXIT INT TERM
  main "$@"
fi
