#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-cyclebalance-meal-scan-proxy}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-cyclebalance-meal-scan-proxy}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-cyclebalance-gemini-api-key}"
REVENUECAT_SECRET_NAME="${REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key}"
APP_ATTEST_BEARER_SECRET_NAME="${APP_ATTEST_BEARER_SECRET_NAME:-cyclebalance-app-attest-verifier-bearer}"
APP_ATTEST_VERIFIER_URL="${APP_ATTEST_VERIFIER_URL:-}"
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-false}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Missing required command: gcloud" >&2
  exit 1
fi

if [[ -z "$PROJECT_ID" ]]; then
  read -rp "Google Cloud project ID for CycleBalance: " PROJECT_ID
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
  AUTH_FLAG="--allow-unauthenticated"
else
  AUTH_FLAG="--no-allow-unauthenticated"
fi

ENV_VARS="^@^NODE_ENV=production@MEAL_SCAN_ENABLED=false@APP_ATTEST_REQUIRED=true@APP_ATTEST_VERIFIER_URL=${APP_ATTEST_VERIFIER_URL}@REVENUECAT_ENTITLEMENT_ID=CycleBalance Unlimited@MEAL_SCAN_QUOTA_STORE=firestore@MEAL_SCAN_DAILY_LIMIT=10@MEAL_SCAN_SOFT_DAILY_LIMIT=5@MEAL_SCAN_TRIAL_DAILY_LIMIT=5@MEAL_SCAN_TRIAL_TOTAL_LIMIT=25@MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD=50@MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD=75@MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD=100"
SECRETS="GEMINI_API_KEY=${GEMINI_SECRET_NAME}:latest,REVENUECAT_SECRET_API_KEY=${REVENUECAT_SECRET_NAME}:latest"
if gcloud secrets versions list "$APP_ATTEST_BEARER_SECRET_NAME" \
  --project "$PROJECT_ID" \
  --filter="state:enabled" \
  --limit=1 \
  --format="value(name)" | grep -q .; then
  SECRETS="${SECRETS},APP_ATTEST_VERIFIER_BEARER=${APP_ATTEST_BEARER_SECRET_NAME}:latest"
fi

gcloud config set project "$PROJECT_ID"
gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --source . \
  --service-account "$SERVICE_ACCOUNT_EMAIL" \
  --set-env-vars "$ENV_VARS" \
  --set-secrets "$SECRETS" \
  --ingress all \
  "$AUTH_FLAG"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)')"

echo
echo "Cloud Run deploy complete."
echo "Service URL: $SERVICE_URL"
echo
echo "Scanner remains disabled because MEAL_SCAN_ENABLED=false."
echo "After App Attest verification is ready and staging passes, enable with:"
echo "gcloud run services update $SERVICE_NAME --project $PROJECT_ID --region $REGION --update-env-vars MEAL_SCAN_ENABLED=true"
echo
echo "Set this in Config/LocalSecrets.xcconfig only for builds that should call the proxy:"
echo "MEAL_SCAN_PROXY_BASE_URL = $SERVICE_URL"
