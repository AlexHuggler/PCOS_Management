#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FIRESTORE_LOCATION="${FIRESTORE_LOCATION:-nam5}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-cyclebalance-meal-scan-proxy}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-cyclebalance-gemini-api-key}"
PRINCIPAL_HMAC_SECRET_NAME="${PRINCIPAL_HMAC_SECRET_NAME:-cyclebalance-meal-scan-principal-hmac}"
APPLE_IAP_PRIVATE_KEY_SECRET_NAME="${APPLE_IAP_PRIVATE_KEY_SECRET_NAME:-cyclebalance-app-store-iap-private-key}"
QUOTA_COLLECTION_NAME="${QUOTA_COLLECTION_NAME:-mealScanRollingQuota}"
IDEMPOTENCY_COLLECTION_NAME="${IDEMPOTENCY_COLLECTION_NAME:-mealScanIdempotency}"
REQUEST_GATE_COLLECTION_NAME="${REQUEST_GATE_COLLECTION_NAME:-mealScanRequestGate}"
PRINCIPAL_ATTEMPT_COLLECTION_NAME="${PRINCIPAL_ATTEMPT_COLLECTION_NAME:-mealScanPrincipalAttempts}"
RESULT_CACHE_COLLECTION_NAME="${RESULT_CACHE_COLLECTION_NAME:-mealScanEstimateCache}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local current_value="${!var_name:-}"
  if [[ -z "$current_value" ]]; then
    read -rp "$prompt: " current_value
    printf -v "$var_name" "%s" "$current_value"
  fi
}

ensure_secret() {
  local secret_name="$1"
  if ! gcloud secrets describe "$secret_name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$secret_name" \
      --project "$PROJECT_ID" \
      --replication-policy="automatic"
  fi
}

add_secret_version_from_prompt() {
  local secret_name="$1"
  local prompt="$2"
  local required="${3:-false}"
  local value=""
  read -rsp "$prompt: " value
  echo
  if [[ -z "$value" ]]; then
    if [[ "$required" == "true" ]]; then
      echo "Required secret value was empty: $secret_name" >&2
      exit 1
    fi
    echo "Skipped empty secret value for $secret_name"
    return
  fi
  printf "%s" "$value" | gcloud secrets versions add "$secret_name" \
    --project "$PROJECT_ID" \
    --data-file=-
}

add_secret_version_from_file_prompt() {
  local secret_name="$1"
  local prompt="$2"
  local file_path=""
  read -rp "$prompt: " file_path
  if [[ -z "$file_path" || ! -f "$file_path" || ! -r "$file_path" ]]; then
    echo "A readable secret file is required for $secret_name" >&2
    exit 1
  fi
  gcloud secrets versions add "$secret_name" \
    --project "$PROJECT_ID" \
    --data-file="$file_path"
}

require_command curl
require_command gcloud
require_command jq
prompt_if_empty PROJECT_ID "Google Cloud project ID for CycleBalance"

gcloud config set project "$PROJECT_ID"

echo "Enabling required Google Cloud APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  firestore.googleapis.com \
  firebaserules.googleapis.com \
  generativelanguage.googleapis.com \
  apikeys.googleapis.com \
  firebase.googleapis.com \
  firebaseappcheck.googleapis.com \
  firebaseinstallations.googleapis.com \
  billingbudgets.googleapis.com \
  pubsub.googleapis.com \
  --project "$PROJECT_ID"

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
    --project "$PROJECT_ID" \
    --display-name="CycleBalance meal scan proxy"
fi

echo "Ensuring Firestore default database exists..."
if ! gcloud firestore databases describe --database="(default)" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud firestore databases create \
    --database="(default)" \
    --location="$FIRESTORE_LOCATION" \
    --project "$PROJECT_ID"
fi

echo "Deploying deny-all Firestore mobile/web security rules..."
PROJECT_ID="$PROJECT_ID" "$SCRIPT_DIR/deploy-firestore-rules.sh"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/datastore.user" \
  --condition=None >/dev/null

ensure_secret "$GEMINI_SECRET_NAME"
ensure_secret "$PRINCIPAL_HMAC_SECRET_NAME"
ensure_secret "$APPLE_IAP_PRIVATE_KEY_SECRET_NAME"

for secret_name in "$GEMINI_SECRET_NAME" "$PRINCIPAL_HMAC_SECRET_NAME" "$APPLE_IAP_PRIVATE_KEY_SECRET_NAME"; do
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project "$PROJECT_ID" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/secretmanager.secretAccessor" >/dev/null
done

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/firebaseappcheck.tokenVerifier" \
  --condition=None >/dev/null

echo "Enabling Firestore TTL deletion for quota, idempotency, abuse-gate, verified-attempt, and structured estimate cache records..."
gcloud firestore fields ttls update expiresAt \
  --collection-group="$QUOTA_COLLECTION_NAME" \
  --database="(default)" \
  --enable-ttl \
  --project="$PROJECT_ID" \
  --async >/dev/null
gcloud firestore fields ttls update expiresAt \
  --collection-group="$IDEMPOTENCY_COLLECTION_NAME" \
  --database="(default)" \
  --enable-ttl \
  --project="$PROJECT_ID" \
  --async >/dev/null
gcloud firestore fields ttls update expiresAt \
  --collection-group="$REQUEST_GATE_COLLECTION_NAME" \
  --database="(default)" \
  --enable-ttl \
  --project="$PROJECT_ID" \
  --async >/dev/null
gcloud firestore fields ttls update expiresAt \
  --collection-group="$PRINCIPAL_ATTEMPT_COLLECTION_NAME" \
  --database="(default)" \
  --enable-ttl \
  --project="$PROJECT_ID" \
  --async >/dev/null
gcloud firestore fields ttls update expiresAt \
  --collection-group="$RESULT_CACHE_COLLECTION_NAME" \
  --database="(default)" \
  --enable-ttl \
  --project="$PROJECT_ID" \
  --async >/dev/null

echo
echo "Secret values go directly to Secret Manager, not to this repo."
add_secret_version_from_prompt "$GEMINI_SECRET_NAME" "Gemini API key" true
add_secret_version_from_prompt "$PRINCIPAL_HMAC_SECRET_NAME" "Random principal HMAC secret (at least 32 characters)" true
add_secret_version_from_file_prompt "$APPLE_IAP_PRIVATE_KEY_SECRET_NAME" "Path to the App Store Connect In-App Purchase private key (.p8)"

echo
echo "Bootstrap complete."
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Service account: $SERVICE_ACCOUNT_EMAIL"
echo "Secrets: $GEMINI_SECRET_NAME, $PRINCIPAL_HMAC_SECRET_NAME, $APPLE_IAP_PRIVATE_KEY_SECRET_NAME"
echo "Firestore: (default) in $FIRESTORE_LOCATION"
