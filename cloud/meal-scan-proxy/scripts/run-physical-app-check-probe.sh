#!/usr/bin/env bash
# Runs one physical-device request with a deliberately invalid StoreKit transaction JWS.
# The normal path is dry-run only.
set -euo pipefail

readonly PINNED_PROJECT_ID="cyclebalance-prod-20260710"
readonly PINNED_SERVICE_NAME="cyclebalance-meal-scan-proxy"
readonly DEFAULT_DEVICE_ID="0C663BE9-3804-587C-BD8A-A2B4D38F998A"

PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-$PINNED_SERVICE_NAME}"
DEVICE_NAME="${DEVICE_NAME:-General Kenobi}"
readonly PROBE_SCHEME="PCOS Production Meal Scan Probe"
DRY_RUN="${DRY_RUN:-false}"
CONFIRM_TEMPORARY_PUBLIC_PROBE="${CONFIRM_TEMPORARY_PUBLIC_PROBE:-}"

readonly APP_BUNDLE_ID="alex.PCOS"
readonly PROBE_TEST="PCOSProductionProbeTests/ProductionMealScanAppCheckProbeTests"
readonly MEAL_SCAN_ROLLING_QUOTA_COLLECTION="mealScanRollingQuota"
readonly FIRESTORE_SNAPSHOT_PAGE_SIZE=100
readonly MAX_FIRESTORE_SNAPSHOT_PAGES=100
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROXY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "$PROXY_DIR/../.." && pwd)"
readonly DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-cloud-run.sh"

ROLLBACK_ARMED=false
ROLLBACK_COMPLETE=false
TEMP_ROOT=""
SERVICE_URL=""
START_UTC=""
END_UTC=""
PROBE_REVISION=""
DEVICE_IDENTIFIER=""
XCODE_DEVICE_UDID=""
APP_WAS_INSTALLED=""
PROBE_APP_INSTALL_STARTED=false

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

private_invoker_gate_rejects_status() {
  [[ "$1" == "403" || "$1" == "404" ]]
}

validate_pinned_cloud_identity() {
  require_equal "$PROJECT_ID" "$PINNED_PROJECT_ID" "The probe is pinned to the production project"
  require_equal "$SERVICE_NAME" "$PINNED_SERVICE_NAME" "The probe is pinned to the production service"
}

resolve_device_identifier() {
  local device_id="${DEVICE_ID:-}"
  local device_udid="${DEVICE_UDID:-}"
  if [[ -n "$device_id" && -n "$device_udid" && "$device_id" != "$device_udid" ]]; then
    die "DEVICE_ID and DEVICE_UDID must match when both are set"
  fi
  printf '%s\n' "${device_id:-${device_udid:-$DEFAULT_DEVICE_ID}}"
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
    ] as $recognized_states |
    (($recognized_states | length) > 0 and all($recognized_states[]; . == true))
  ' "$lock_json" >/dev/null
}

device_details_are_paired() {
  local details_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("isPaired") and (.isPaired | type == "boolean")
        then .isPaired else empty end),
      (if has("paired") and (.paired | type == "boolean")
        then .paired else empty end),
      (if has("pairingState") and (.pairingState | type == "string") and
          ((.pairingState | ascii_downcase) == "paired" or (.pairingState | ascii_downcase) == "unpaired")
        then ((.pairingState | ascii_downcase) == "paired") else empty end)
    ] as $recognized_states |
    (($recognized_states | length) > 0 and all($recognized_states[]; . == true))
  ' "$details_json" >/dev/null
}

device_details_have_developer_mode() {
  local details_json="$1"
  jq -e '
    [
      .. | objects |
      (if has("developerModeEnabled") and (.developerModeEnabled | type == "boolean")
        then .developerModeEnabled else empty end),
      (if has("isDeveloperModeEnabled") and (.isDeveloperModeEnabled | type == "boolean")
        then .isDeveloperModeEnabled else empty end),
      (if has("developerModeStatus") and (.developerModeStatus | type == "string") and
          ((.developerModeStatus | ascii_downcase) == "enabled" or (.developerModeStatus | ascii_downcase) == "disabled")
        then ((.developerModeStatus | ascii_downcase) == "enabled") else empty end)
    ] as $recognized_states |
    (($recognized_states | length) > 0 and all($recognized_states[]; . == true))
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
      elif has("services") and (.services | type == "array")
        then (.services | length > 0)
      else empty end)
    ] as $recognized_states |
    (($recognized_states | length) > 0 and all($recognized_states[]; . == true))
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
  jq -e --arg bundle_id "$bundle_id" '
    any(.result.apps[]; .bundleIdentifier == $bundle_id)
  ' "$apps_json" >/dev/null
}

app_attest_environment_from_app() {
  local app_path="$1"
  codesign --display --xml --entitlements - "$app_path" 2>/dev/null |
    plutil -extract 'com\.apple\.developer\.devicecheck\.appattest-environment' raw -
}

normalize_service_url() {
  local url="$1"
  if [[ "$url" == */ ]]; then
    url="${url%/}"
  fi
  printf '%s\n' "$url"
}

require_service_url_match() {
  local app_url verified_url
  app_url="$(normalize_service_url "$1")"
  verified_url="$(normalize_service_url "$2")"
  [[ "$verified_url" == https://* ]] || die "Verified Cloud Run service URL must use HTTPS"
  require_equal "$app_url" "$verified_url" "Release app proxy URL must exactly match the verified Cloud Run service URL"
}

cleanup_temp() {
  [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]] && rm -rf "$TEMP_ROOT"
}

preserve_probe_diagnostics() {
  [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]] || return 0

  local test_log result_bundle diagnostics_root diagnostics_dir
  test_log="$TEMP_ROOT/physical-probe-test.log"
  result_bundle="$TEMP_ROOT/PhysicalProbe.xcresult"
  [[ -f "$test_log" || -d "$result_bundle" ]] || return 0

  diagnostics_root="$HOME/Library/Logs/CycleBalance/PhysicalProbe"
  diagnostics_dir="$diagnostics_root/$(date -u +%Y%m%dT%H%M%SZ)-failed"
  umask 077
  mkdir -p "$diagnostics_dir"
  chmod 0700 "$diagnostics_root" "$diagnostics_dir"
  if [[ -f "$test_log" ]]; then
    sed -E \
      -e 's/(Authorization: Bearer )[[:graph:]]+/\1[REDACTED]/g' \
      -e 's/AIza[[:alnum:]_-]+/[REDACTED_GOOGLE_API_KEY]/g' \
      "$test_log" >"$diagnostics_dir/physical-probe-test.log"
    chmod 0600 "$diagnostics_dir/physical-probe-test.log"
  fi
  if [[ -d "$result_bundle" ]]; then
    cp -R "$result_bundle" "$diagnostics_dir/PhysicalProbe.xcresult"
  fi
  note "Preserved failed-probe diagnostics at $diagnostics_dir."
}

restore_original_app_absence() {
  [[ "$APP_WAS_INSTALLED" == false && "$PROBE_APP_INSTALL_STARTED" == true ]] || return 0
  [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" && -n "$DEVICE_IDENTIFIER" ]] || return 1

  local apps_json verified_apps_json
  apps_json="$TEMP_ROOT/rollback-device-apps.json"
  verified_apps_json="$TEMP_ROOT/rollback-device-apps-verified.json"
  xcrun devicectl device info apps \
    --device "$DEVICE_IDENTIFIER" \
    --json-output "$apps_json" >/dev/null || return 1
  device_app_inventory_is_valid "$apps_json" || return 1
  if ! device_has_installed_app "$apps_json" "$APP_BUNDLE_ID"; then
    return 0
  fi

  note "Device cleanup: removing the transient probe app because CycleBalance was initially absent."
  xcrun devicectl device uninstall app \
    --device "$DEVICE_IDENTIFIER" \
    "$APP_BUNDLE_ID" \
    --quiet \
    --timeout 30 || return 1
  xcrun devicectl device info apps \
    --device "$DEVICE_IDENTIFIER" \
    --json-output "$verified_apps_json" >/dev/null || return 1
  device_app_inventory_is_valid "$verified_apps_json" || return 1
  ! device_has_installed_app "$verified_apps_json" "$APP_BUNDLE_ID"
}

rollback() {
  local status=$?
  set +e
  if [[ "$ROLLBACK_ARMED" == true && "$ROLLBACK_COMPLETE" == false ]]; then
    note "Rollback: restoring disabled/private Cloud Run state."
    deploy_private
    if verify_private_disabled_state; then
      ROLLBACK_COMPLETE=true
      note "Rollback verification passed: unauthenticated 403/404 and authenticated 503 feature_disabled."
    else
      note "FATAL: rollback deploy or verification failed; inspect the Cloud Run service immediately." >&2
      status=1
    fi
  fi
  if ! restore_original_app_absence; then
    note "FATAL: the transient CycleBalance probe app could not be removed from the device." >&2
    status=1
  fi
  if [[ "$status" -ne 0 ]]; then
    preserve_probe_diagnostics || note "WARNING: failed-probe diagnostics could not be preserved." >&2
  fi
  cleanup_temp
  exit "$status"
}

print_dry_run() {
  note "DRY RUN ONLY: no cloud, device, build, installation, or backup action will run."
  note "1. Validate project $PROJECT_ID and Cloud Run service $SERVICE_NAME in $REGION."
  note "2. Require MEAL_SCAN_ENABLED=false, Firestore budget mode normal, and no allUsers Cloud Run invoker."
  note "3. Confirm $DEVICE_NAME ($DEVICE_IDENTIFIER) is paired, explicitly reported unlocked, in Developer Mode, and can auto-mount its DDI."
  note "4. Prove whether $APP_BUNDLE_ID is installed. If present, back up its app data to ~/Library/Application Support/CycleBalance/DeviceBackups/<UTC timestamp> mode 0700; abort if inventory or backup fails."
  note "5. Build current Release source in a temporary DerivedData directory without automatic provisioning changes."
  note "6. Inspect the product for bundle ID $APP_BUNDLE_ID, production App Attest entitlement, and exact equality with the verified Cloud Run URL."
  note "7. Arm rollback before any cloud mutation."
  note "8. Temporarily deploy MEAL_SCAN_ENABLED=true with unauthenticated ingress using deploy-cloud-run.sh."
  note "9. Run only $PROBE_TEST through the dedicated opt-in Release scheme on the named device."
  note "10. Require HTTP 403 premium_entitlement_required / storekit_transaction_invalid, prove the complete $MEAL_SCAN_ROLLING_QUOTA_COLLECTION collection is unchanged, and prove the probe revision emits no provider_call or meal_scan_estimate event."
  note "11. Record that this negative probe does not satisfy the positive sandbox-JWS real-device TestFlight gate; that gate remains open."
  note "12. Always redeploy disabled/private, verify the transport and kill switch, and remove a transient probe app when CycleBalance was initially absent."
}

firestore_document_json() {
  local collection="$1"
  local document_id="$2"
  local access_token auth_config response_file status
  access_token="$(gcloud auth print-access-token)" || return 1
  auth_config="$(mktemp "$TEMP_ROOT/firestore-auth.XXXXXX")" || return 1
  response_file="$(mktemp "$TEMP_ROOT/firestore-response.XXXXXX")" || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$access_token" >"$auth_config"
  unset access_token

  status="$(curl --silent --show-error \
    --config "$auth_config" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/$collection/$document_id")" \
    || return 1
  rm -f "$auth_config"

  case "$status" in
    200) cat "$response_file" ;;
    404) printf '{"__notFound":true}' ;;
    *) return 1 ;;
  esac
}

firestore_collection_snapshot() {
  local collection="$1"
  local access_token auth_config documents_file response_file status
  local page_count page_token encoded_page_token query_url next_page_token snapshot

  access_token="$(gcloud auth print-access-token)" || return 1
  auth_config="$(mktemp "$TEMP_ROOT/firestore-collection-auth.XXXXXX")" || return 1
  documents_file="$(mktemp "$TEMP_ROOT/firestore-collection-documents.XXXXXX")" || {
    rm -f "$auth_config"
    return 1
  }
  chmod 600 "$auth_config" "$documents_file" || {
    rm -f "$auth_config" "$documents_file"
    return 1
  }
  printf 'header = "Authorization: Bearer %s"\n' "$access_token" >"$auth_config" || {
    unset access_token
    rm -f "$auth_config" "$documents_file"
    return 1
  }
  unset access_token

  page_count=0
  page_token=""
  while true; do
    page_count=$((page_count + 1))
    if (( page_count > MAX_FIRESTORE_SNAPSHOT_PAGES )); then
      rm -f "$auth_config" "$documents_file"
      return 1
    fi

    query_url="https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/(default)/documents/$collection?pageSize=$FIRESTORE_SNAPSHOT_PAGE_SIZE&orderBy=__name__"
    if [[ -n "$page_token" ]]; then
      encoded_page_token="$(jq -rn --arg page_token "$page_token" '$page_token | @uri')" || {
        rm -f "$auth_config" "$documents_file"
        return 1
      }
      query_url="${query_url}&pageToken=$encoded_page_token"
    fi

    response_file="$(mktemp "$TEMP_ROOT/firestore-collection-response.XXXXXX")" || {
      rm -f "$auth_config" "$documents_file"
      return 1
    }
    if ! status="$(curl --silent --show-error \
      --config "$auth_config" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$query_url")"; then
      rm -f "$auth_config" "$documents_file" "$response_file"
      return 1
    fi
    if [[ "$status" != "200" ]] || ! jq -e '
      ((.documents // []) | type == "array") and
      ((.nextPageToken // "") | type == "string")
    ' "$response_file" >/dev/null; then
      rm -f "$auth_config" "$documents_file" "$response_file"
      return 1
    fi
    if ! jq -c '
      (.documents // [])[] |
      {
        name,
        createTime: (.createTime // null),
        updateTime: (.updateTime // null),
        data: (.fields // {})
      }
    ' "$response_file" >>"$documents_file"; then
      rm -f "$auth_config" "$documents_file" "$response_file"
      return 1
    fi
    next_page_token="$(jq -r '.nextPageToken // ""' "$response_file")" || {
      rm -f "$auth_config" "$documents_file" "$response_file"
      return 1
    }
    rm -f "$response_file"

    if [[ -z "$next_page_token" ]]; then
      break
    fi
    page_token="$next_page_token"
  done

  snapshot="$(jq -cs 'sort_by(.name)' "$documents_file")" || {
    rm -f "$auth_config" "$documents_file"
    return 1
  }
  rm -f "$auth_config" "$documents_file"
  printf '%s\n' "$snapshot"
}

rolling_quota_snapshot() {
  firestore_collection_snapshot "$MEAL_SCAN_ROLLING_QUOTA_COLLECTION"
}

effective_budget_mode_from_json() {
  jq -er '
    def rank:
      if . == "normal" then 0
      elif . == "alert" then 1
      elif . == "degraded" then 2
      elif . == "disabled" then 3
      else -1
      end;
    select(.__notFound != true) |
    [.fields.manualMode.stringValue?, .fields.billingMode.stringValue?] |
    map(select(rank >= 0)) |
    if length == 0 then empty else max_by(rank) end
  '
}

read_budget_mode() {
  local document
  document="$(firestore_document_json "mealScanControls" "global")" || return 1
  effective_budget_mode_from_json <<<"$document"
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

  local unauthenticated_status response_file
  response_file="$TEMP_ROOT/initial-private-response.txt"
  unauthenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST "$SERVICE_URL/v1/meal-scans/estimate")" \
    || die "Unable to verify the Cloud Run private transport before the probe"
  private_invoker_gate_rejects_status "$unauthenticated_status" \
    || die "Cloud Run must reject unauthenticated transport with HTTP 403 or concealed 404 before the probe"
}

verify_device_preconditions() {
  note "Checking the named physical device without requesting any passcode."
  local devices_json details_json lock_json ddi_json xcdevice_json
  devices_json="$TEMP_ROOT/devices.json"
  details_json="$TEMP_ROOT/device-details.json"
  lock_json="$TEMP_ROOT/device-lock.json"
  ddi_json="$TEMP_ROOT/device-ddi.json"
  xcdevice_json="$TEMP_ROOT/xcdevice.json"

  xcrun devicectl list devices --json-output "$devices_json" >/dev/null
  jq -e --arg udid "$DEVICE_IDENTIFIER" --arg name "$DEVICE_NAME" '
    .. | objects | select((.identifier? // .udid? // "") == $udid) |
    [.. | strings | select(. == $name)] | length > 0
  ' "$devices_json" >/dev/null || die "Expected paired device $DEVICE_NAME ($DEVICE_IDENTIFIER) was not found"

  xcrun devicectl device info details --device "$DEVICE_IDENTIFIER" --json-output "$details_json" >/dev/null
  device_details_are_paired "$details_json" || die "Device is not paired"
  device_details_have_developer_mode "$details_json" || die "Developer Mode must be enabled"

  xcrun devicectl device info lockState --device "$DEVICE_IDENTIFIER" --json-output "$lock_json" >/dev/null
  device_lock_is_verified_unlocked "$lock_json" \
    || die "Device lock state is missing, unknown, conflicting, or locked. Unlock it manually; this script will never request a passcode."

  xcrun devicectl device info ddiServices --auto-mount-ddis --device "$DEVICE_IDENTIFIER" --json-output "$ddi_json" >/dev/null \
    || die "CoreDevice could not mount or verify the developer disk image"
  device_ddi_is_usable "$ddi_json" \
    || die "Developer disk image services are not available"

  xcrun xcdevice list >"$xcdevice_json" \
    || die "Xcode could not list physical-device destinations"
  XCODE_DEVICE_UDID="$(resolve_xcode_device_udid "$xcdevice_json" "$DEVICE_NAME")" \
    || die "Expected exactly one available physical Xcode destination named $DEVICE_NAME"
  note "Resolved $DEVICE_NAME from CoreDevice $DEVICE_IDENTIFIER to Xcode destination $XCODE_DEVICE_UDID."
}

backup_app_data() {
  local apps_json backup_root backup_dir
  apps_json="$TEMP_ROOT/device-apps.json"
  xcrun devicectl device info apps \
    --device "$DEVICE_IDENTIFIER" \
    --json-output "$apps_json" >/dev/null \
    || die "CoreDevice could not read the installed-app inventory"
  device_app_inventory_is_valid "$apps_json" \
    || die "CoreDevice returned an invalid installed-app inventory"
  if ! device_has_installed_app "$apps_json" "$APP_BUNDLE_ID"; then
    APP_WAS_INSTALLED=false
    note "$APP_BUNDLE_ID is not installed, so no existing app-data container requires backup."
    return
  fi
  APP_WAS_INSTALLED=true

  backup_root="$HOME/Library/Application Support/CycleBalance/DeviceBackups"
  backup_dir="$backup_root/$(date -u +%Y%m%dT%H%M%SZ)"
  umask 077
  mkdir -p "$backup_dir"
  chmod 0700 "$backup_root" "$backup_dir"
  note "Backing up the installed app-data container before any installation."
  xcrun devicectl device copy from \
    --device "$DEVICE_IDENTIFIER" \
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
    ENABLE_TESTABILITY=YES \
    build

  app_path="$(find "$TEMP_ROOT/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name 'PCOS.app' -print -quit)"
  [[ -n "$app_path" ]] || die "Release build did not produce PCOS.app"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
  require_equal "$bundle_id" "$APP_BUNDLE_ID" "Unexpected Release bundle identifier"
  if ! app_attest_environment="$(app_attest_environment_from_app "$app_path")"; then
    die "Unable to read the App Attest environment from the signed Release product"
  fi
  require_equal "$app_attest_environment" "production" "Release build must use production App Attest"
  proxy_url="$(/usr/libexec/PlistBuddy -c 'Print :MEAL_SCAN_PROXY_BASE_URL' "$app_path/Info.plist")"
  require_service_url_match "$proxy_url" "$SERVICE_URL"
}

deploy_temporary_public_probe() {
  note "Temporarily enabling the reviewed probe revision."
  (cd "$PROXY_DIR" && \
    PROJECT_ID="$PROJECT_ID" REGION="$REGION" SERVICE_NAME="$SERVICE_NAME" \
    MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true "$DEPLOY_SCRIPT")

  local service
  service="$(service_json)" || die "Unable to read the temporary Cloud Run revision"
  PROBE_REVISION="$(jq -r '.status.latestReadyRevisionName // empty' <<<"$service")"
  [[ -n "$PROBE_REVISION" ]] || die "Temporary Cloud Run revision name is missing"
  jq -e '[.spec.template.spec.containers[].env[]? | select(.name == "MEAL_SCAN_ENABLED") | .value] | index("true") != null' \
    <<<"$service" >/dev/null || die "Temporary Cloud Run revision is not enabled"
  note "Temporary probe revision: $PROBE_REVISION"
}

deploy_private() {
  (cd "$PROXY_DIR" && \
    PROJECT_ID="$PROJECT_ID" REGION="$REGION" SERVICE_NAME="$SERVICE_NAME" \
    MEAL_SCAN_ENABLED=false ALLOW_UNAUTHENTICATED=false "$DEPLOY_SCRIPT")
}

verify_private_disabled_state() {
  local service unauthenticated_status authenticated_status response_file identity_token auth_header_curl_config
  service="$(service_json)" || return 1
  SERVICE_URL="$(jq -r '.status.url // empty' <<<"$service")"
  jq -e '[.spec.template.spec.containers[].env[]? | select(.name == "MEAL_SCAN_ENABLED") | .value] | index("false") != null' \
    <<<"$service" >/dev/null || return 1
  ! gcloud run services get-iam-policy "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format=json | \
    jq -e '[.bindings[]? | select(.role == "roles/run.invoker") | .members[]?] | index("allUsers") != null' >/dev/null || return 1

  response_file="$TEMP_ROOT/disabled-response.json"
  unauthenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  private_invoker_gate_rejects_status "$unauthenticated_status" || return 1

  identity_token="$(gcloud auth print-identity-token)" || return 1
  auth_header_curl_config="$(mktemp "$TEMP_ROOT/cloud-run-auth.XXXXXX")" || return 1
  chmod 600 "$auth_header_curl_config" || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$identity_token" >"$auth_header_curl_config"
  unset identity_token
  authenticated_status="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --request POST \
    --config "$auth_header_curl_config" \
    "$SERVICE_URL/v1/meal-scans/estimate")" || return 1
  rm -f "$auth_header_curl_config"
  [[ "$authenticated_status" == "503" ]] || return 1
  jq -e '.error == "meal_scan_unavailable" and .reason == "feature_disabled"' "$response_file" >/dev/null || return 1
}

run_probe_and_verify_side_effects() {
  local before_rolling_quota after_rolling_quota test_log provider_logs estimate_logs
  before_rolling_quota="$(rolling_quota_snapshot)" \
    || die "Unable to read the complete rolling quota collection before test execution"
  test_log="$TEMP_ROOT/physical-probe-test.log"
  START_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  note "Running the opt-in Release test on the physical device."
  PROBE_APP_INSTALL_STARTED=true
  xcodebuild test \
    -project "$REPOSITORY_ROOT/PCOS.xcodeproj" \
    -scheme "$PROBE_SCHEME" \
    -configuration Release \
    -destination "platform=iOS,id=$XCODE_DEVICE_UDID" \
    -derivedDataPath "$TEMP_ROOT/DerivedData" \
    -resultBundlePath "$TEMP_ROOT/PhysicalProbe.xcresult" \
    ENABLE_TESTABILITY=YES \
    -only-testing:"$PROBE_TEST" | tee "$test_log"

  END_UTC="$(date -u -v+2S +%Y-%m-%dT%H:%M:%SZ)"
  after_rolling_quota="$(rolling_quota_snapshot)" \
    || die "Unable to read the complete rolling quota collection after test execution"
  require_unchanged "$after_rolling_quota" "$before_rolling_quota" \
    "Probe must leave the complete $MEAL_SCAN_ROLLING_QUOTA_COLLECTION collection unchanged"

  sleep 10
  provider_logs="$(gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.revision_name=\"$PROBE_REVISION\" AND timestamp>=\"$START_UTC\" AND timestamp<=\"$END_UTC\" AND \"meal_scan_scanner_event\" AND \"provider_call\"" \
    --project "$PROJECT_ID" \
    --limit=1 \
    --format='value(insertId)')"
  [[ -z "$provider_logs" ]] || die "Probe must not create a provider call event on $PROBE_REVISION"
  estimate_logs="$(gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.revision_name=\"$PROBE_REVISION\" AND timestamp>=\"$START_UTC\" AND timestamp<=\"$END_UTC\" AND \"meal_scan_estimate\"" \
    --project "$PROJECT_ID" \
    --limit=1 \
    --format='value(insertId)')"
  [[ -z "$estimate_logs" ]] || die "Probe must not create a Gemini estimate event on $PROBE_REVISION"
  note "Negative physical App Check evidence passed: storekit_transaction_invalid, complete $MEAL_SCAN_ROLLING_QUOTA_COLLECTION collection unchanged, and no provider_call or meal_scan_estimate event on $PROBE_REVISION."
  note "This negative probe does not satisfy the positive sandbox-JWS real-device TestFlight gate; that gate remains open."
}

main() {
  validate_pinned_cloud_identity
  DEVICE_IDENTIFIER="$(resolve_device_identifier)"
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
  umask 077
  verify_initial_cloud_state
  verify_device_preconditions
  backup_app_data
  build_and_inspect_release_product
  note "Rechecking the physical device immediately before the temporary cloud mutation."
  verify_device_preconditions

  # From this point forward the EXIT trap restores the private, disabled revision on every exit path.
  ROLLBACK_ARMED=true
  deploy_temporary_public_probe
  run_probe_and_verify_side_effects
  note "Physical probe passed. The rollback trap will now restore private/disabled state."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  trap rollback EXIT INT TERM
  main "$@"
fi
