#!/usr/bin/env bash
# Runs one deliberately non-entitled physical-device request. The normal path is dry-run only.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-cyclebalance-meal-scan-proxy}"
DEVICE_UDID="${DEVICE_UDID:-0C663BE9-3804-587C-BD8A-A2B4D38F998A}"
DEVICE_NAME="${DEVICE_NAME:-General Kenobi}"
PROBE_SCHEME="${PROBE_SCHEME:-PCOS Production Meal Scan Probe}"
DRY_RUN="${DRY_RUN:-false}"
CONFIRM_TEMPORARY_PUBLIC_PROBE="${CONFIRM_TEMPORARY_PUBLIC_PROBE:-}"

readonly APP_BUNDLE_ID="alex.PCOS"
readonly PROBE_TEST="PCOSTests/ProductionMealScanAppCheckProbeTests"
readonly PROBE_USER_ID="cyclebalance-appcheck-probe-no-entitlement"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROXY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "$PROXY_DIR/../.." && pwd)"
readonly DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-cloud-run.sh"

ROLLBACK_ARMED=false
ROLLBACK_COMPLETE=false
TEMP_ROOT=""
SERVICE_URL=""
START_UTC=""

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

cleanup_temp() {
  [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]] && rm -rf "$TEMP_ROOT"
}

rollback() {
  local status=$?
  set +e
  if [[ "$ROLLBACK_ARMED" == true && "$ROLLBACK_COMPLETE" == false ]]; then
    note "Rollback: restoring disabled/private Cloud Run state."
    deploy_private
    if verify_private_disabled_state; then
      ROLLBACK_COMPLETE=true
      note "Rollback verification passed: unauthenticated 403 and authenticated 503 feature_disabled."
    else
      note "FATAL: rollback deploy or verification failed; inspect the Cloud Run service immediately." >&2
      status=1
    fi
  fi
  cleanup_temp
  exit "$status"
}

trap rollback EXIT INT TERM

print_dry_run() {
  note "DRY RUN ONLY: no cloud, device, build, installation, or backup action will run."
  note "1. Validate project $PROJECT_ID and Cloud Run service $SERVICE_NAME in $REGION."
  note "2. Require MEAL_SCAN_ENABLED=false, Firestore budget mode normal, and no allUsers Cloud Run invoker."
  note "3. Confirm $DEVICE_NAME ($DEVICE_UDID) is paired, unlocked, in Developer Mode, and can auto-mount its DDI."
  note "4. Back up $APP_BUNDLE_ID app data to ~/Library/Application Support/CycleBalance/DeviceBackups/<UTC timestamp> mode 0700; abort if it fails."
  note "5. Build current Release source in a temporary DerivedData directory without -allowProvisioningUpdates."
  note "6. Inspect the product for bundle ID $APP_BUNDLE_ID, production App Attest entitlement, and a complete HTTPS proxy URL."
  note "7. Arm rollback before any cloud mutation."
  note "8. Temporarily deploy MEAL_SCAN_ENABLED=true with unauthenticated ingress using deploy-cloud-run.sh."
  note "9. Run only $PROBE_TEST with RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1 on the named device."
  note "10. Require HTTP 403 premium_entitlement_required / entitlement_inactive, no quota document, and no Gemini estimate log for the image-hash prefix."
  note "11. Always redeploy disabled/private and require unauthenticated 403 plus authenticated 503 feature_disabled."
}

read_budget_mode() {
  (cd "$PROXY_DIR" && node --input-type=module - "$PROJECT_ID" <<'NODE'
import { Firestore } from "@google-cloud/firestore";

const projectId = process.argv[2];
const snapshot = await new Firestore({ projectId }).collection("mealScanControls").doc("global").get();
if (!snapshot.exists) process.exit(2);
const data = snapshot.data() ?? {};
const mode = data.manualMode ?? data.billingMode;
if (typeof mode !== "string") process.exit(3);
process.stdout.write(mode);
NODE
  )
}

quota_snapshot() {
  (cd "$PROXY_DIR" && node --input-type=module - "$PROJECT_ID" "$PROBE_USER_ID" <<'NODE'
import crypto from "node:crypto";
import { Firestore } from "@google-cloud/firestore";

const [projectId, appUserId] = process.argv.slice(2);
const appUserHash = crypto.createHash("sha256").update(appUserId).digest("hex").slice(0, 16);
const day = new Date().toISOString().slice(0, 10);
const snapshot = await new Firestore({ projectId })
  .collection("mealScanDailyQuota")
  .doc(`${appUserHash}_${day}`)
  .get();
process.stdout.write(snapshot.exists ? String(snapshot.get("used") ?? 0) : "absent");
NODE
  )
}

service_json() {
  gcloud run services describe "$SERVICE_NAME" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --format=json
}

verify_initial_cloud_state() {
  note "Checking project, service, disabled state, budget mode, and IAM."
  require_equal "$(gcloud projects describe "$PROJECT_ID" --format='value(projectId)')" "$PROJECT_ID" "Unexpected Google Cloud project"

  local service
  service="$(service_json)"
  SERVICE_URL="$(jq -r '.status.url // empty' <<<"$service")"
  [[ "$SERVICE_URL" == https://* ]] || die "Cloud Run service has no HTTPS URL"
  jq -e '[.spec.template.spec.containers[].env[]? | select(.name == "MEAL_SCAN_ENABLED") | .value] | index("false") != null' \
    <<<"$service" >/dev/null || die "MEAL_SCAN_ENABLED must be false before the probe"

  local budget_mode
  budget_mode="$(read_budget_mode)" || die "Unable to read Firestore budget control"
  require_equal "$budget_mode" "normal" "Budget mode must be normal before the probe"

  ! gcloud run services get-iam-policy "$SERVICE_NAME" \
    --project "$PROJECT_ID" \
    --region "$REGION" \
    --format=json | jq -e '[.bindings[]? | select(.role == "roles/run.invoker") | .members[]?] | index("allUsers") != null' >/dev/null \
    || die "Cloud Run service must not grant allUsers the invoker role before the probe"
}

verify_device_preconditions() {
  note "Checking the named physical device without requesting any passcode."
  local devices_json details_json lock_json ddi_json
  devices_json="$TEMP_ROOT/devices.json"
  details_json="$TEMP_ROOT/device-details.json"
  lock_json="$TEMP_ROOT/device-lock.json"
  ddi_json="$TEMP_ROOT/device-ddi.json"

  xcrun devicectl list devices --json-output "$devices_json" >/dev/null
  jq -e --arg udid "$DEVICE_UDID" --arg name "$DEVICE_NAME" '
    .. | objects | select((.identifier? // .udid? // "") == $udid) |
    [.. | strings | select(. == $name)] | length > 0
  ' "$devices_json" >/dev/null || die "Expected paired device $DEVICE_NAME ($DEVICE_UDID) was not found"

  xcrun devicectl device info details --device "$DEVICE_UDID" --json-output "$details_json" >/dev/null
  jq -e '.. | objects | [.isPaired?, .paired?, .deviceProperties?.isPaired?] | any(. == true)' \
    "$details_json" >/dev/null || die "Device is not paired"
  jq -e '.. | objects | [.developerModeEnabled?, .isDeveloperModeEnabled?, .deviceProperties?.developerModeEnabled?] | any(. == true)' \
    "$details_json" >/dev/null || die "Developer Mode must be enabled"

  xcrun devicectl device info lockState --device "$DEVICE_UDID" --json-output "$lock_json" >/dev/null
  ! jq -e '.. | strings | ascii_downcase | select(. == "locked" or . == "lock")' "$lock_json" >/dev/null \
    || die "Device is locked. Unlock it manually; this script will never request a passcode."

  xcrun devicectl device info ddiServices --auto-mount-ddis --device "$DEVICE_UDID" --json-output "$ddi_json" >/dev/null \
    || die "CoreDevice could not mount or verify the developer disk image"
  jq -e '.. | objects | select(has("services")) | .services | length > 0' "$ddi_json" >/dev/null \
    || die "Developer disk image services are not available"
}

backup_app_data() {
  local backup_root backup_dir
  backup_root="$HOME/Library/Application Support/CycleBalance/DeviceBackups"
  backup_dir="$backup_root/$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  mkdir -p "$backup_dir"
  chmod 0700 "$backup_root" "$backup_dir"
  note "Backing up the installed app-data container before any installation."
  xcrun devicectl device copy from \
    --device "$DEVICE_UDID" \
    --domain-type appDataContainer \
    --domain-identifier "$APP_BUNDLE_ID" \
    --source . \
    --destination "$backup_dir" >/dev/null \
    || die "CoreDevice app-data backup failed. Stop here and complete an encrypted Finder backup before retrying."
  find "$backup_dir" -mindepth 1 -print -quit | grep -q . \
    || die "CoreDevice app-data backup was empty. Stop here and complete an encrypted Finder backup before retrying."
}

build_and_inspect_release_product() {
  local app_path bundle_id app_attest_environment proxy_url
  note "Building current Release source into temporary DerivedData without provisioning updates."
  xcodebuild \
    -project "$REPOSITORY_ROOT/PCOS.xcodeproj" \
    -scheme "$PROBE_SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$TEMP_ROOT/DerivedData" \
    build

  app_path="$(find "$TEMP_ROOT/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name 'PCOS.app' -print -quit)"
  [[ -n "$app_path" ]] || die "Release build did not produce PCOS.app"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
  require_equal "$bundle_id" "$APP_BUNDLE_ID" "Unexpected Release bundle identifier"
  app_attest_environment="$(codesign -d --entitlements :- "$app_path" 2>/dev/null | plutil -extract 'com.apple.developer.devicecheck.appattest-environment' raw -)"
  require_equal "$app_attest_environment" "production" "Release build must use production App Attest"
  proxy_url="$(/usr/libexec/PlistBuddy -c 'Print :MEAL_SCAN_PROXY_BASE_URL' "$app_path/Info.plist")"
  [[ "$proxy_url" == https://* && "$proxy_url" != *'$('* && "$proxy_url" != *'YOUR_'* ]] \
    || die "Release build must contain a complete production HTTPS proxy URL"
}

deploy_temporary_public_probe() {
  note "Temporarily enabling the reviewed probe revision."
  (cd "$PROXY_DIR" && \
    PROJECT_ID="$PROJECT_ID" REGION="$REGION" SERVICE_NAME="$SERVICE_NAME" \
    MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true "$DEPLOY_SCRIPT")
}

deploy_private() {
  (cd "$PROXY_DIR" && \
    PROJECT_ID="$PROJECT_ID" REGION="$REGION" SERVICE_NAME="$SERVICE_NAME" \
    MEAL_SCAN_ENABLED=false ALLOW_UNAUTHENTICATED=false "$DEPLOY_SCRIPT")
}

verify_private_disabled_state() {
  local service unauthenticated_status authenticated_status response_file identity_token
  service="$(service_json)" || return 1
  SERVICE_URL="$(jq -r '.status.url // empty' <<<"$service")"
  jq -e '[.spec.template.spec.containers[].env[]? | select(.name == "MEAL_SCAN_ENABLED") | .value] | index("false") != null' \
    <<<"$service" >/dev/null || return 1
  ! gcloud run services get-iam-policy "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format=json | \
    jq -e '[.bindings[]? | select(.role == "roles/run.invoker") | .members[]?] | index("allUsers") != null' >/dev/null || return 1

  response_file="$TEMP_ROOT/disabled-response.json"
  unauthenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  [[ "$unauthenticated_status" == "403" ]] || return 1

  identity_token="$(gcloud auth print-identity-token)" || return 1
  authenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST \
    --header "Authorization: Bearer $identity_token" \
    "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  [[ "$authenticated_status" == "503" ]] || return 1
  jq -e '.error == "meal_scan_unavailable" and .reason == "feature_disabled"' "$response_file" >/dev/null || return 1
}

run_probe_and_verify_side_effects() {
  local before_quota after_quota test_log hash_prefix estimate_logs
  before_quota="$(quota_snapshot)" || die "Unable to read the probe quota document before test execution"
  test_log="$TEMP_ROOT/physical-probe-test.log"
  START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "Running the opt-in Release test on the physical device."
  RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1 xcodebuild test \
    -project "$REPOSITORY_ROOT/PCOS.xcodeproj" \
    -scheme "$PROBE_SCHEME" \
    -configuration Release \
    -destination "platform=iOS,id=$DEVICE_UDID" \
    -derivedDataPath "$TEMP_ROOT/ProbeTestDerivedData" \
    -only-testing:"$PROBE_TEST" | tee "$test_log"

  hash_prefix="$(sed -n 's/.*image hash prefix: \([0-9a-f]\{12\}\).*/\1/p' "$test_log" | tail -n 1)"
  [[ "$hash_prefix" =~ ^[0-9a-f]{12}$ ]] || die "The probe did not emit its safe image-hash prefix"
  after_quota="$(quota_snapshot)" || die "Unable to read the probe quota document after test execution"
  require_equal "$after_quota" "$before_quota" "Probe must not write or consume quota"

  estimate_logs="$(gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"$SERVICE_NAME\" AND timestamp>=\"$START_UTC\" AND jsonPayload.imageHash=\"$hash_prefix\"" \
    --project "$PROJECT_ID" \
    --limit=1 \
    --format='value(insertId)')"
  [[ -z "$estimate_logs" ]] || die "Probe must not create a Gemini estimate event for image-hash prefix $hash_prefix"
}

main() {
  [[ -n "$PROJECT_ID" ]] || die "PROJECT_ID is required"
  if [[ "$DRY_RUN" == "true" ]]; then
    print_dry_run
    return
  fi

  [[ "$CONFIRM_TEMPORARY_PUBLIC_PROBE" == "YES" ]] || die "Live execution requires CONFIRM_TEMPORARY_PUBLIC_PROBE=YES"
  require_command gcloud
  require_command jq
  require_command curl
  require_command node
  require_command xcodebuild
  require_command xcrun
  require_command codesign

  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-physical-probe.XXXXXX")"
  verify_initial_cloud_state
  verify_device_preconditions
  backup_app_data
  build_and_inspect_release_product

  # From this point forward the EXIT trap restores the private, disabled revision on every exit path.
  ROLLBACK_ARMED=true
  deploy_temporary_public_probe
  run_probe_and_verify_side_effects
  note "Physical probe passed. The rollback trap will now restore private/disabled state."
}

main "$@"
