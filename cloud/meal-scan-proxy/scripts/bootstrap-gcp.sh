#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FIRESTORE_LOCATION="${FIRESTORE_LOCATION:-nam5}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-cyclebalance-meal-scan-proxy}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-cyclebalance-gemini-api-key}"
REVENUECAT_SECRET_NAME="${REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key}"
APP_ATTEST_BEARER_SECRET_NAME="${APP_ATTEST_BEARER_SECRET_NAME:-cyclebalance-app-attest-verifier-bearer}"

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

require_command gcloud
prompt_if_empty PROJECT_ID "Google Cloud project ID for CycleBalance"

gcloud config set project "$PROJECT_ID"

echo "Enabling required Google Cloud APIs..."
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  firestore.googleapis.com \
  generativelanguage.googleapis.com \
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

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/datastore.user" \
  --condition=None >/dev/null

ensure_secret "$GEMINI_SECRET_NAME"
ensure_secret "$REVENUECAT_SECRET_NAME"
ensure_secret "$APP_ATTEST_BEARER_SECRET_NAME"

gcloud secrets add-iam-policy-binding "$GEMINI_SECRET_NAME" \
  --project "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null
gcloud secrets add-iam-policy-binding "$REVENUECAT_SECRET_NAME" \
  --project "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null
gcloud secrets add-iam-policy-binding "$APP_ATTEST_BEARER_SECRET_NAME" \
  --project "$PROJECT_ID" \
  --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" >/dev/null

echo
echo "The next prompts are hidden. Values go directly to Secret Manager, not to this repo."
add_secret_version_from_prompt "$GEMINI_SECRET_NAME" "Gemini API key" true
add_secret_version_from_prompt "$REVENUECAT_SECRET_NAME" "RevenueCat secret API key" true
add_secret_version_from_prompt "$APP_ATTEST_BEARER_SECRET_NAME" "Optional App Attest verifier bearer token, press Enter to skip" false

echo
echo "Bootstrap complete."
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Service account: $SERVICE_ACCOUNT_EMAIL"
echo "Secrets: $GEMINI_SECRET_NAME, $REVENUECAT_SECRET_NAME, $APP_ATTEST_BEARER_SECRET_NAME"
echo "Firestore: (default) in $FIRESTORE_LOCATION"
