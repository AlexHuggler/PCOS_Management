#!/usr/bin/env bash
set -euo pipefail

readonly PINNED_PROJECT_ID="proj8da4e000"
readonly PINNED_API_ROOT="https://api.revenuecat.com/v2"
readonly PINNED_APP_ID="appca3539a96a"
readonly EXPECTED_OFFERING_LOOKUP_KEY="default"
readonly EXPECTED_ENTITLEMENT_LOOKUP_KEY="CycleBalance Unlimited"
readonly EXPECTED_MONTHLY_PACKAGE_LOOKUP_KEY='$rc_monthly'
readonly EXPECTED_ANNUAL_PACKAGE_LOOKUP_KEY='$rc_annual'
readonly EXPECTED_MONTHLY_PRODUCT="cyclebalance.premium.monthly"
readonly EXPECTED_ANNUAL_PRODUCT="cyclebalance.premium.annual"

PROJECT_ID="${REVENUECAT_PROJECT_ID:-$PINNED_PROJECT_ID}"
DRY_RUN="${DRY_RUN:-true}"
REVENUECAT_API_KEY_VALUE=""
TEMP_ROOT=""

umask 077

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_pinned_identity() {
  [[ "$PROJECT_ID" == "$PINNED_PROJECT_ID" ]] \
    || die "RevenueCat project is pinned to $PINNED_PROJECT_ID"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

cleanup() {
  REVENUECAT_API_KEY_VALUE=""
  unset REVENUECAT_API_KEY_VALUE REVENUECAT_API_V2_KEY REVENUECAT_SECRET_API_KEY
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

read_api_key() {
  if [[ -n "${REVENUECAT_API_V2_KEY:-}" || -n "${REVENUECAT_SECRET_API_KEY:-}" ]]; then
    die "supply the RevenueCat API v2 secret key only through hidden input or stdin, never an environment variable"
  fi
  unset REVENUECAT_API_V2_KEY REVENUECAT_SECRET_API_KEY

  if [[ -t 0 ]]; then
    read -rsp "RevenueCat API v2 secret key (hidden and memory-only): " REVENUECAT_API_KEY_VALUE
    printf '\n' >/dev/tty
  else
    IFS= read -r REVENUECAT_API_KEY_VALUE \
      || [[ -n "$REVENUECAT_API_KEY_VALUE" ]] \
      || die "RevenueCat API v2 secret key was not supplied on stdin"
  fi
  [[ "$REVENUECAT_API_KEY_VALUE" =~ ^sk_[A-Za-z0-9._-]{20,255}$ ]] \
    || die "RevenueCat API v2 secret key format was invalid"
}

api_get() {
  local path="$1"
  local output_file="$2"
  local status url
  url="$PINNED_API_ROOT/projects/$PROJECT_ID$path"
  if ! status="$(
    printf 'header = "Authorization: Bearer %s"\n' "$REVENUECAT_API_KEY_VALUE" |
      curl --disable --config - \
        --silent \
        --show-error \
        --proto '=https' \
        --tlsv1.2 \
        --connect-timeout 10 \
        --max-time 20 \
        --output "$output_file" \
        --write-out '%{http_code}' \
        "$url"
  )"; then
    die "RevenueCat read-only API request failed before an HTTP response"
  fi
  [[ "$status" =~ ^[0-9]{3}$ ]] || die "RevenueCat read-only API returned an invalid HTTP status"
  [[ "$status" == "200" ]] || die "RevenueCat read-only API returned HTTP $status"
  jq -e . "$output_file" >/dev/null 2>&1 \
    || die "RevenueCat read-only API returned malformed JSON"
}

require_safe_resource_id() {
  local resource_id="$1"
  local label="$2"
  [[ "$resource_id" =~ ^[A-Za-z0-9_-]{4,255}$ ]] \
    || die "$label resource ID was unsafe or malformed"
}

verify_offering_list() {
  local file="$1"
  jq -e \
    --arg project "$PROJECT_ID" \
    --arg lookup "$EXPECTED_OFFERING_LOOKUP_KEY" '
      .object == "list" and
      (.items | type == "array") and
      has("next_page") and
      .next_page == null and
      ([.items[] | select(.is_current == true)] | length == 1) and
      ([.items[] | select(
        .state == "active" and
        .object == "offering" and
        .project_id == $project and
        .lookup_key == $lookup and
        .is_current == true and
        (.id | type == "string")
      )] | length == 1)
    ' "$file" >/dev/null 2>&1 \
    || die "complete active current default offering evidence was not verified"
}

verify_package_list() {
  local file="$1"
  jq -e \
    --arg monthly "$EXPECTED_MONTHLY_PACKAGE_LOOKUP_KEY" \
    --arg annual "$EXPECTED_ANNUAL_PACKAGE_LOOKUP_KEY" '
    .object == "list" and
    (.items | type == "array") and
    has("next_page") and
    .next_page == null and
    (.items | length == 2) and
    (all(.items[];
      .object == "package" and
      (.id | type == "string") and
      (.lookup_key == $monthly or .lookup_key == $annual)
    )) and
    ([.items[].lookup_key] | sort == ([$monthly, $annual] | sort)) and
    ([.items[].id] | unique | length == 2)
  ' "$file" >/dev/null 2>&1 \
    || die "exact monthly and annual package configuration was not verified"
}

verify_package_product() {
  local file="$1"
  local expected_store_id="$2"
  local expected_duration="$3"
  jq -e \
    --arg app_id "$PINNED_APP_ID" \
    --arg store_id "$expected_store_id" \
    --arg duration "$expected_duration" '
      def safe_resource_id:
        if type == "string" then test("^[A-Za-z0-9_-]{4,255}$") else false end;
      .object == "list" and
      (.items | type == "array") and
      has("next_page") and
      .next_page == null and
      (all(.items[];
        (.product | type == "object") and
        .product.object == "product" and
        (.product.id | safe_resource_id) and
        (.product.app_id | safe_resource_id)
      )) and
      ([.items[].product | select(.app_id == $app_id)] | length == 1) and
      ([.items[].product | select(
        .app_id == $app_id and
        .state == "active" and
        .object == "product" and
        (.id | type == "string") and
        .store_identifier == $store_id and
        .type == "subscription" and
        .subscription.duration == $duration
      )] | length == 1)
    ' "$file" >/dev/null 2>&1 \
    || die "exact monthly and annual package configuration was not verified"
}

verify_entitlement_list() {
  local file="$1"
  jq -e \
    --arg project "$PROJECT_ID" \
    --arg lookup "$EXPECTED_ENTITLEMENT_LOOKUP_KEY" '
      .object == "list" and
      (.items | type == "array") and
      has("next_page") and
      .next_page == null and
      ([.items[] | select(
        .state == "active" and
        .object == "entitlement" and
        .project_id == $project and
        .lookup_key == $lookup and
        (.id | type == "string")
      )] | length == 1)
    ' "$file" >/dev/null 2>&1 \
    || die "CycleBalance Unlimited entitlement did not have exact active products evidence"
}

verify_entitlement_products() {
  local file="$1"
  local monthly_product_id="$2"
  local annual_product_id="$3"
  jq -e \
    --arg monthly_id "$monthly_product_id" \
    --arg annual_id "$annual_product_id" \
    --arg app_id "$PINNED_APP_ID" \
    --arg monthly_store "$EXPECTED_MONTHLY_PRODUCT" \
    --arg annual_store "$EXPECTED_ANNUAL_PRODUCT" '
      def safe_resource_id:
        if type == "string" then test("^[A-Za-z0-9_-]{4,255}$") else false end;
      .object == "list" and
      (.items | type == "array") and
      has("next_page") and
      .next_page == null and
      (all(.items[];
        .object == "product" and
        (.id | safe_resource_id) and
        (.app_id | safe_resource_id)
      )) and
      ([.items[] | select(.app_id == $app_id)] | length == 2) and
      ([.items[] | select(.app_id == $app_id) | .id] | sort == ([$monthly_id, $annual_id] | sort)) and
      ([.items[] | select(
        .app_id == $app_id and
        .state == "active" and
        .object == "product" and
        .id == $monthly_id and
        .store_identifier == $monthly_store and
        .type == "subscription" and
        .subscription.duration == "P1M"
      )] | length == 1) and
      ([.items[] | select(
        .app_id == $app_id and
        .state == "active" and
        .object == "product" and
        .id == $annual_id and
        .store_identifier == $annual_store and
        .type == "subscription" and
        .subscription.duration == "P1Y"
      )] | length == 1)
    ' "$file" >/dev/null 2>&1 \
    || die "CycleBalance Unlimited entitlement did not have exact monthly and annual products attached"
}

verify_live() {
  local offerings_file packages_file monthly_file annual_file entitlements_file entitlement_products_file
  local offering_id monthly_package_id annual_package_id monthly_product_id annual_product_id entitlement_id

  require_command curl
  require_command jq
  read_api_key
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-revenuecat-v2.XXXXXX")"
  chmod 0700 "$TEMP_ROOT"
  offerings_file="$TEMP_ROOT/offerings.json"
  packages_file="$TEMP_ROOT/packages.json"
  monthly_file="$TEMP_ROOT/monthly-products.json"
  annual_file="$TEMP_ROOT/annual-products.json"
  entitlements_file="$TEMP_ROOT/entitlements.json"
  entitlement_products_file="$TEMP_ROOT/entitlement-products.json"

  api_get "/offerings?limit=100" "$offerings_file"
  verify_offering_list "$offerings_file"
  offering_id="$(jq -er --arg lookup "$EXPECTED_OFFERING_LOOKUP_KEY" '
    .items[] | select(.state == "active" and .lookup_key == $lookup and .is_current == true) | .id
  ' "$offerings_file")"
  require_safe_resource_id "$offering_id" "offering"

  api_get "/offerings/$offering_id/packages?limit=100" "$packages_file"
  verify_package_list "$packages_file"
  monthly_package_id="$(jq -er --arg lookup "$EXPECTED_MONTHLY_PACKAGE_LOOKUP_KEY" \
    '.items[] | select(.lookup_key == $lookup) | .id' "$packages_file")"
  annual_package_id="$(jq -er --arg lookup "$EXPECTED_ANNUAL_PACKAGE_LOOKUP_KEY" \
    '.items[] | select(.lookup_key == $lookup) | .id' "$packages_file")"
  require_safe_resource_id "$monthly_package_id" "monthly package"
  require_safe_resource_id "$annual_package_id" "annual package"

  api_get "/packages/$monthly_package_id/products?limit=100" "$monthly_file"
  verify_package_product "$monthly_file" "$EXPECTED_MONTHLY_PRODUCT" "P1M"
  monthly_product_id="$(jq -er \
    --arg app_id "$PINNED_APP_ID" \
    --arg store_id "$EXPECTED_MONTHLY_PRODUCT" \
    '.items[].product | select(.app_id == $app_id and .store_identifier == $store_id) | .id' \
    "$monthly_file")"
  require_safe_resource_id "$monthly_product_id" "monthly product"

  api_get "/packages/$annual_package_id/products?limit=100" "$annual_file"
  verify_package_product "$annual_file" "$EXPECTED_ANNUAL_PRODUCT" "P1Y"
  annual_product_id="$(jq -er \
    --arg app_id "$PINNED_APP_ID" \
    --arg store_id "$EXPECTED_ANNUAL_PRODUCT" \
    '.items[].product | select(.app_id == $app_id and .store_identifier == $store_id) | .id' \
    "$annual_file")"
  require_safe_resource_id "$annual_product_id" "annual product"
  [[ "$monthly_product_id" != "$annual_product_id" ]] \
    || die "exact monthly and annual package configuration was not verified"

  api_get "/entitlements?limit=100" "$entitlements_file"
  verify_entitlement_list "$entitlements_file"
  entitlement_id="$(jq -er --arg lookup "$EXPECTED_ENTITLEMENT_LOOKUP_KEY" '
    .items[] | select(.state == "active" and .lookup_key == $lookup) | .id
  ' "$entitlements_file")"
  require_safe_resource_id "$entitlement_id" "entitlement"

  api_get "/entitlements/$entitlement_id/products?limit=100" "$entitlement_products_file"
  REVENUECAT_API_KEY_VALUE=""
  unset REVENUECAT_API_KEY_VALUE
  verify_entitlement_products "$entitlement_products_file" "$monthly_product_id" "$annual_product_id"

  printf '%s\n' \
    "RevenueCat configuration verified through read-only API v2 endpoints." \
    "Current offering: default; exact packages: $EXPECTED_MONTHLY_PACKAGE_LOOKUP_KEY and $EXPECTED_ANNUAL_PACKAGE_LOOKUP_KEY." \
    "Entitlement: CycleBalance Unlimited; both exact CycleBalance iOS products are attached and active."
}

print_dry_run() {
  printf '%s\n' \
    "DRY RUN ONLY - no RevenueCat request or API-key read was performed." \
    "Planned read-only API v2 checks for project $PROJECT_ID:" \
    "- the active current offering has lookup_key default" \
    "- the offering contains exact $EXPECTED_MONTHLY_PACKAGE_LOOKUP_KEY and $EXPECTED_ANNUAL_PACKAGE_LOOKUP_KEY packages" \
    "- those packages and the active CycleBalance Unlimited entitlement contain both exact CycleBalance iOS products" \
    "Required shared-key read-only scopes: Subscriptions, Offerings, Packages, Entitlements; no write access."
}

main() {
  trap cleanup EXIT
  require_pinned_identity
  case "$DRY_RUN" in
    true) print_dry_run ;;
    false) verify_live ;;
    *) die "DRY_RUN must be true or false" ;;
  esac
}

main "$@"
