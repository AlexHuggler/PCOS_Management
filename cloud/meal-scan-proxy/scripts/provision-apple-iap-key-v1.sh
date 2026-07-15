#!/usr/bin/env bash
set -euo pipefail

readonly PINNED_PROJECT_ID="cyclebalance-prod-20260710"
readonly PINNED_PROJECT_NUMBER="947929010052"
readonly PINNED_SECRET_NAME="cyclebalance-app-store-iap-private-key"
readonly PINNED_PROXY_SERVICE_ACCOUNT="cyclebalance-meal-scan-proxy@cyclebalance-prod-20260710.iam.gserviceaccount.com"

PROJECT_ID="${PROJECT_ID:-$PINNED_PROJECT_ID}"
SECRET_NAME="${APPLE_IAP_PRIVATE_KEY_SECRET_NAME:-$PINNED_SECRET_NAME}"
PROXY_SERVICE_ACCOUNT="${PROXY_SERVICE_ACCOUNT:-$PINNED_PROXY_SERVICE_ACCOUNT}"
DRY_RUN="${DRY_RUN:-true}"
readonly REQUIRED_APPROVAL="I_APPROVE_CREATE_APPLE_IAP_P8_SECRET_VERSION_1"
P8_FILE="${APPLE_IAP_P8_FILE:-}"
TEMP_ROOT=""
SEALED_P8_FILE=""
PROVISION_OWNER=""
INSPECTED_RESOURCE_STATE=""
INSPECTED_VERSION_COUNT=""
INSPECTED_PROVISION_STATE="unclaimed"
INSPECTED_PROVISION_OWNER=""

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

prepare_temp_root() {
  [[ -z "$TEMP_ROOT" ]] || return 0
  TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/cyclebalance-p8-v1.XXXXXX")"
  chmod 0700 "$TEMP_ROOT"
}

cleanup() {
  P8_FILE=""
  SEALED_P8_FILE=""
  PROVISION_OWNER=""
  unset P8_FILE SEALED_P8_FILE PROVISION_OWNER APPLE_IAP_P8_FILE
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}

secret_resource_name() {
  printf 'projects/%s/secrets/%s' "$PINNED_PROJECT_NUMBER" "$SECRET_NAME"
}

read_secret_inventory() {
  local output_file="$1"
  gcloud secrets list \
    --project "$PROJECT_ID" \
    --filter="name:$SECRET_NAME" \
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
    (.name? | type == "string") and .name == $expected and
    (.etag? | type == "string") and (.etag | length > 0) and
    (((.labels // {}) | type) == "object")
  ' "$output_file" >/dev/null 2>&1 \
    || die "Apple IAP secret metadata did not match the pinned resource"
}

metadata_etag() {
  jq -er '.etag | strings | select(length > 0)' "$1" \
    || die "Apple IAP secret metadata did not contain an ETag"
}

require_unclaimed_provision_metadata() {
  jq -e '
    ((.labels // {}) | type == "object") and
    ((.labels // {}).cyclebalance_iap_provision_state // "" | length == 0) and
    ((.labels // {}).cyclebalance_iap_provision_owner // "" | length == 0)
  ' "$1" >/dev/null 2>&1 \
    || die "Apple IAP secret is already locked or claimed; manual review is required"
}

require_owned_provision_state() {
  local metadata_file="$1"
  local expected_state="$2"
  jq -e --arg state "$expected_state" --arg owner "$PROVISION_OWNER" '
    ((.labels // {}) | type == "object") and
    (.labels.cyclebalance_iap_provision_state == $state) and
    (.labels.cyclebalance_iap_provision_owner == $owner)
  ' "$metadata_file" >/dev/null 2>&1 \
    || die "Apple IAP secret provisioning ownership readback did not match"
}

provision_labels() {
  local state="$1"
  printf 'cyclebalance_iap_provision_state=%s,cyclebalance_iap_provision_owner=%s' \
    "$state" "$PROVISION_OWNER"
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

inspect_metadata_read_only() {
  local inventory_file secret_file versions_file iam_file resource_count
  inventory_file="$TEMP_ROOT/inspection-secret-inventory.json"
  secret_file="$TEMP_ROOT/inspection-secret.json"
  versions_file="$TEMP_ROOT/inspection-versions.json"
  iam_file="$TEMP_ROOT/inspection-iam.json"
  read_secret_inventory "$inventory_file"
  resource_count="$(jq -r 'length' "$inventory_file")"
  if [[ "$resource_count" == "0" ]]; then
    INSPECTED_RESOURCE_STATE="absent"
    INSPECTED_VERSION_COUNT="0"
  else
    INSPECTED_RESOURCE_STATE="present"
    verify_secret_metadata "$secret_file"
    INSPECTED_PROVISION_STATE="$(jq -r '(.labels // {}).cyclebalance_iap_provision_state // "unclaimed"' "$secret_file")"
    INSPECTED_PROVISION_OWNER="$(jq -r '(.labels // {}).cyclebalance_iap_provision_owner // ""' "$secret_file")"
    read_versions "$versions_file"
    INSPECTED_VERSION_COUNT="$(jq -r 'length' "$versions_file")"
    require_zero_versions "$versions_file"
    read_iam_policy "$iam_file"
  fi
  printf '%s\n' \
    "Read-only metadata inspection complete." \
    "Observed resource: $INSPECTED_RESOURCE_STATE" \
    "Observed versions: $INSPECTED_VERSION_COUNT" \
    "Observed provisioning state: $INSPECTED_PROVISION_STATE" \
    "Observed public IAM principals: none."
}

require_live_claimable_inspection() {
  if [[ "$INSPECTED_RESOURCE_STATE" == "present" ]]; then
    [[ "$INSPECTED_PROVISION_STATE" == "unclaimed" && -z "$INSPECTED_PROVISION_OWNER" ]] \
      || die "Apple IAP secret is already locked or claimed; manual review is required"
  fi
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
  local sealed_path
  if [[ -z "$P8_FILE" ]]; then
    [[ -t 0 ]] || die "APPLE_IAP_P8_FILE must name the owner-only .p8 file for live provisioning"
    read -rsp "Path to the owner-only App Store Connect IAP .p8 file: " P8_FILE
    printf '\n' >/dev/tty
  fi
  [[ "$P8_FILE" == *.p8 ]] || die "APPLE_IAP_P8_FILE must use the .p8 extension"
  sealed_path="$TEMP_ROOT/sealed-app-store-iap-key.p8"
  node - "$P8_FILE" "$sealed_path" <<'NODE' >/dev/null 2>&1 \
    || die ".p8 file must contain one valid PKCS8 P-256 EC private key"
const {
  closeSync,
  constants,
  fchmodSync,
  fstatSync,
  fsyncSync,
  openSync,
  readSync,
  writeSync,
} = require("node:fs");
const { createPrivateKey } = require("node:crypto");

let sourceFd;
let sealedFd;
let material;
let der;
try {
  const source = process.argv[2];
  const sealed = process.argv[3];
  sourceFd = openSync(source, constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0));
  const metadata = fstatSync(sourceFd);
  if (!metadata.isFile()) throw new Error("not a regular file");
  if ((metadata.mode & 0o077) !== 0) throw new Error("source permissions are not owner-only");
  if (metadata.size < 100 || metadata.size > 10_000) throw new Error("unexpected source size");

  material = Buffer.alloc(metadata.size);
  let readOffset = 0;
  while (readOffset < material.length) {
    const count = readSync(sourceFd, material, readOffset, material.length - readOffset, readOffset);
    if (count === 0) throw new Error("short source read");
    readOffset += count;
  }
  const afterRead = fstatSync(sourceFd);
  if (
    afterRead.dev !== metadata.dev ||
    afterRead.ino !== metadata.ino ||
    afterRead.size !== metadata.size
  ) {
    throw new Error("source changed while held open");
  }

  const pem = material.toString("utf8");
  const match = pem.match(/^-----BEGIN PRIVATE KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END PRIVATE KEY-----\r?\n?$/);
  if (!match) throw new Error("invalid envelope");
  der = Buffer.from(match[1].replace(/\s/g, ""), "base64");
  if (der.length === 0) throw new Error("invalid DER");
  const key = createPrivateKey({ key: der, format: "der", type: "pkcs8" });
  const curve = key.asymmetricKeyDetails?.namedCurve;
  if (key.asymmetricKeyType !== "ec" || !["prime256v1", "secp256r1", "P-256"].includes(curve)) {
    throw new Error("invalid key type");
  }
  sealedFd = openSync(
    sealed,
    constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | (constants.O_NOFOLLOW ?? 0),
    0o400
  );
  let writeOffset = 0;
  while (writeOffset < material.length) {
    writeOffset += writeSync(
      sealedFd,
      material,
      writeOffset,
      material.length - writeOffset,
      writeOffset
    );
  }
  fchmodSync(sealedFd, 0o400);
  fsyncSync(sealedFd);
} catch {
  process.exitCode = 1;
} finally {
  der?.fill(0);
  material?.fill(0);
  if (sealedFd !== undefined) closeSync(sealedFd);
  if (sourceFd !== undefined) closeSync(sourceFd);
}
NODE
  SEALED_P8_FILE="$sealed_path"
  P8_FILE=""
  unset P8_FILE APPLE_IAP_P8_FILE
  [[ -f "$SEALED_P8_FILE" && ! -L "$SEALED_P8_FILE" ]] \
    || die "sealed .p8 snapshot was not created safely"
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
  local resource_count secret_existed="false" etag

  inventory_file="$TEMP_ROOT/live-secret-inventory.json"
  secret_file="$TEMP_ROOT/live-secret.json"
  versions_file="$TEMP_ROOT/live-versions.json"
  iam_file="$TEMP_ROOT/live-iam.json"
  iam_policy_file="$TEMP_ROOT/iam-policy.json"
  version_file="$TEMP_ROOT/version-1.json"

  read_secret_inventory "$inventory_file"
  resource_count="$(jq -r 'length' "$inventory_file")"
  if [[ "$resource_count" == "1" ]]; then
    secret_existed="true"
    verify_secret_metadata "$secret_file"
    require_unclaimed_provision_metadata "$secret_file"
    read_versions "$versions_file"
    require_zero_versions "$versions_file"
    read_iam_policy "$iam_file"
    etag="$(metadata_etag "$secret_file")"
    gcloud secrets update "$SECRET_NAME" \
      --project "$PROJECT_ID" \
      --etag="$etag" \
      --update-labels="$(provision_labels locked)" >/dev/null \
      || die "could not acquire the Apple IAP provisioning lock; no IAM or version mutation was attempted"
    verify_secret_metadata "$secret_file"
    require_owned_provision_state "$secret_file" "locked"
    read_versions "$versions_file"
    require_zero_versions "$versions_file"
    read_iam_policy "$iam_file"
  else
    gcloud secrets create "$SECRET_NAME" \
      --project "$PROJECT_ID" \
      --replication-policy=automatic \
      --data-file="$SEALED_P8_FILE" \
      --labels="$(provision_labels locked)" >/dev/null \
      || die "atomic Apple IAP secret creation did not succeed; do not retry without manual inventory review"
    verify_secret_metadata "$secret_file"
    require_owned_provision_state "$secret_file" "locked"
    read_versions "$versions_file"
    verify_exact_enabled_v1 "$versions_file"
  fi

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
  if [[ "$secret_existed" == "true" ]]; then
    read_versions "$versions_file"
    require_zero_versions "$versions_file"
    if ! gcloud secrets versions add "$SECRET_NAME" \
      --project "$PROJECT_ID" \
      --data-file="$SEALED_P8_FILE" >/dev/null; then
      gcloud secrets versions list "$SECRET_NAME" \
        --project "$PROJECT_ID" \
        --format=json >"$TEMP_ROOT/ambiguous-version-readback.json" 2>/dev/null || true
      die "Apple IAP version creation result was ambiguous; the provisioning lock remains for manual review"
    fi
  fi

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

  verify_secret_metadata "$secret_file"
  require_owned_provision_state "$secret_file" "locked"
  etag="$(metadata_etag "$secret_file")"
  gcloud secrets update "$SECRET_NAME" \
    --project "$PROJECT_ID" \
    --etag="$etag" \
    --update-labels="$(provision_labels complete)" >/dev/null \
    || die "could not finalize Apple IAP provisioning ownership; the lock remains for manual review"
  verify_secret_metadata "$secret_file"
  require_owned_provision_state "$secret_file" "complete"
  read_versions "$versions_file"
  verify_exact_enabled_v1 "$versions_file"
  read_iam_policy "$iam_file"
  require_exact_proxy_iam "$iam_file"

  printf '%s\n' \
    "Provisioning verified: the pinned Apple IAP secret has exactly enabled version 1." \
    "IAM verified: secretAccessor is granted to the pinned proxy service account only." \
    "Provisioning state verified: complete under the retained immutable owner label."
}

print_dry_run() {
  printf '%s\n' \
    "DRY RUN ONLY - authenticated read-only metadata inspection completed; no Cloud write or key-file access occurred." \
    "Pinned project: $PROJECT_ID" \
    "Pinned secret: $SECRET_NAME" \
    "Observed resource: $INSPECTED_RESOURCE_STATE" \
    "Observed versions: $INSPECTED_VERSION_COUNT" \
    "Eligible invariant: start with zero versions and create exactly enabled version 1." \
    "Planned IAM invariant: service-account-only secretAccessor for the pinned proxy identity." \
    "Set DRY_RUN=false and provide the exact owner approval to perform the one-time handoff."
}

main() {
  trap cleanup EXIT
  require_pinned_identity
  case "$DRY_RUN" in
    true|false) ;;
    *) die "DRY_RUN must be true or false" ;;
  esac
  require_command gcloud
  require_command jq
  prepare_temp_root
  inspect_metadata_read_only
  case "$DRY_RUN" in
    true) print_dry_run ;;
    false)
      [[ "${CONFIRM_APPLE_IAP_P8_V1:-}" == "$REQUIRED_APPROVAL" ]] \
        || die "live provisioning requires CONFIRM_APPLE_IAP_P8_V1=$REQUIRED_APPROVAL"
      require_command node
      require_live_claimable_inspection
      PROVISION_OWNER="$(node -e 'process.stdout.write(require("node:crypto").randomBytes(16).toString("hex"))')" \
        || die "could not create a local provisioning owner token"
      [[ "$PROVISION_OWNER" =~ ^[a-f0-9]{32}$ ]] \
        || die "local provisioning owner token was invalid"
      load_and_validate_p8_file
      provision_live
      ;;
  esac
}

main "$@"
