#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-cyclebalance-meal-scan-proxy}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-cyclebalance-meal-scan-proxy}"
BUILD_SERVICE_ACCOUNT_NAME="${BUILD_SERVICE_ACCOUNT_NAME:-cyclebalance-cloud-build}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-cyclebalance-gemini-api-key}"
REVENUECAT_SECRET_NAME="${REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key}"
GEMINI_SECRET_VERSION="${GEMINI_SECRET_VERSION:-}"
REVENUECAT_SECRET_VERSION="${REVENUECAT_SECRET_VERSION:-}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-1:947929010052:ios:6e68c8645a6a6b5e3057d1}"
REVENUECAT_PROJECT_ID="${REVENUECAT_PROJECT_ID:-proj8da4e000}"
MEAL_SCAN_ENABLED="${MEAL_SCAN_ENABLED:-false}"
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-false}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Missing required command: gcloud" >&2
  exit 1
fi

if [[ -z "$PROJECT_ID" ]]; then
  read -rp "Google Cloud project ID for CycleBalance: " PROJECT_ID
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUILD_SERVICE_ACCOUNT_EMAIL="${BUILD_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

latest_enabled_secret_version() {
  local secret_name="$1"
  gcloud secrets versions list "$secret_name" \
    --project "$PROJECT_ID" \
    --filter="state=ENABLED" \
    --sort-by="~createTime" \
    --limit=1 \
    --format="value(name)"
}

if [[ -z "$GEMINI_SECRET_VERSION" ]]; then
  GEMINI_SECRET_VERSION="$(latest_enabled_secret_version "$GEMINI_SECRET_NAME")"
fi
if [[ -z "$GEMINI_SECRET_VERSION" ]]; then
  echo "No enabled Gemini secret version exists: $GEMINI_SECRET_NAME" >&2
  exit 1
fi

if [[ -z "$REVENUECAT_SECRET_VERSION" ]]; then
  REVENUECAT_SECRET_VERSION="$(latest_enabled_secret_version "$REVENUECAT_SECRET_NAME")"
fi
if [[ "$MEAL_SCAN_ENABLED" == "true" && -z "$REVENUECAT_SECRET_VERSION" ]]; then
  echo "An enabled RevenueCat secret version is required before enabling meal scans." >&2
  exit 1
fi

if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
  AUTH_FLAG="--allow-unauthenticated"
else
  AUTH_FLAG="--no-allow-unauthenticated"
fi

ENV_VARS="^@^NODE_ENV=production@MEAL_SCAN_ENABLED=${MEAL_SCAN_ENABLED}@APP_CHECK_REQUIRED=true@FIREBASE_APP_ID=${FIREBASE_APP_ID}@REVENUECAT_PROJECT_ID=${REVENUECAT_PROJECT_ID}@REVENUECAT_ENTITLEMENT_ID=CycleBalance Unlimited@MEAL_SCAN_QUOTA_STORE=firestore@MEAL_SCAN_RESULT_CACHE=firestore@MEAL_SCAN_BUDGET_STORE=firestore@MEAL_SCAN_RESULT_CACHE_TTL_SECONDS=86400@MEAL_SCAN_CONTROL_CACHE_TTL_MS=30000@MEAL_SCAN_DAILY_LIMIT=10@MEAL_SCAN_SOFT_DAILY_LIMIT=5@MEAL_SCAN_TRIAL_DAILY_LIMIT=5@MEAL_SCAN_TRIAL_TOTAL_LIMIT=25@MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD=75@MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD=90@MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD=120@MAX_BODY_BYTES=5242880@MAX_IMAGE_BYTES=1500000@APP_CHECK_TIMEOUT_MS=5000@REVENUECAT_TIMEOUT_MS=5000@GEMINI_TIMEOUT_MS=12000"
SECRETS="GEMINI_API_KEY=${GEMINI_SECRET_NAME}:${GEMINI_SECRET_VERSION}"
if [[ -n "$REVENUECAT_SECRET_VERSION" ]]; then
  SECRETS="${SECRETS},REVENUECAT_SECRET_API_KEY=${REVENUECAT_SECRET_NAME}:${REVENUECAT_SECRET_VERSION}"
fi

gcloud config set project "$PROJECT_ID" --quiet
gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --source . \
  --service-account "$SERVICE_ACCOUNT_EMAIL" \
  --build-service-account "projects/${PROJECT_ID}/serviceAccounts/${BUILD_SERVICE_ACCOUNT_EMAIL}" \
  --set-env-vars "$ENV_VARS" \
  --set-secrets "$SECRETS" \
  --cpu 1 \
  --memory 512Mi \
  --min-instances 0 \
  --max-instances 2 \
  --concurrency 20 \
  --timeout 30s \
  --execution-environment gen2 \
  --no-automatic-updates \
  --ingress all \
  --quiet \
  "$AUTH_FLAG"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)')"

echo
echo "Cloud Run deploy complete."
echo "Service URL: $SERVICE_URL"
echo
if [[ "$MEAL_SCAN_ENABLED" == "true" ]]; then
  echo "Scanner is enabled for this revision."
else
  echo "Scanner remains disabled because MEAL_SCAN_ENABLED=false."
fi
echo "Enable only after Firebase App Check production verification and staging pass:"
echo "MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true PROJECT_ID=$PROJECT_ID REGION=$REGION ./scripts/deploy-cloud-run.sh"
echo
echo "Set this in Config/LocalSecrets.xcconfig only for builds that should call the proxy:"
echo "MEAL_SCAN_PROXY_BASE_URL = $SERVICE_URL"
