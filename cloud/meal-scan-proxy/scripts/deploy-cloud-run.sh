#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-cyclebalance-meal-scan-proxy}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-cyclebalance-meal-scan-proxy}"
BUILD_SERVICE_ACCOUNT_NAME="${BUILD_SERVICE_ACCOUNT_NAME:-cyclebalance-cloud-build}"
GEMINI_SECRET_NAME="${GEMINI_SECRET_NAME:-cyclebalance-gemini-api-key}"
PRINCIPAL_HMAC_SECRET_NAME="${PRINCIPAL_HMAC_SECRET_NAME:-cyclebalance-meal-scan-principal-hmac}"
APPLE_IAP_PRIVATE_KEY_SECRET_NAME="${APPLE_IAP_PRIVATE_KEY_SECRET_NAME:-cyclebalance-app-store-iap-private-key}"
REVENUECAT_SECRET_NAME="${REVENUECAT_SECRET_NAME:-cyclebalance-revenuecat-secret-api-key}"
GEMINI_SECRET_VERSION="${GEMINI_SECRET_VERSION:-}"
PRINCIPAL_HMAC_SECRET_VERSION="${PRINCIPAL_HMAC_SECRET_VERSION:-}"
APPLE_IAP_PRIVATE_KEY_SECRET_VERSION="${APPLE_IAP_PRIVATE_KEY_SECRET_VERSION:-}"
REVENUECAT_SECRET_VERSION="${REVENUECAT_SECRET_VERSION:-}"
FIREBASE_APP_ID="${FIREBASE_APP_ID:-1:947929010052:ios:6e68c8645a6a6b5e3057d1}"
APPLE_BUNDLE_ID="${APPLE_BUNDLE_ID:-alex.PCOS}"
APPLE_APP_ID="${APPLE_APP_ID:-6760353511}"
APPLE_ALLOWED_PRODUCT_IDS="${APPLE_ALLOWED_PRODUCT_IDS:-cyclebalance.premium.monthly,cyclebalance.premium.annual}"
APPLE_IAP_KEY_ID="${APPLE_IAP_KEY_ID:-}"
APPLE_IAP_ISSUER_ID="${APPLE_IAP_ISSUER_ID:-}"
REVENUECAT_PROJECT_ID="${REVENUECAT_PROJECT_ID:-proj8da4e000}"
REVENUECAT_ENTITLEMENT_ID="${REVENUECAT_ENTITLEMENT_ID:-CycleBalance Unlimited}"
MEAL_SCAN_ENABLED="${MEAL_SCAN_ENABLED:-false}"
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-false}"
INVOKER_ACCESS_ATTEMPTS="${INVOKER_ACCESS_ATTEMPTS:-90}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIRESTORE_RULES_DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-firestore-rules.sh"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Missing required command: gcloud" >&2
  exit 1
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "Missing required command: curl" >&2
  exit 1
fi

if [[ -z "$PROJECT_ID" ]]; then
  read -rp "Google Cloud project ID for CycleBalance: " PROJECT_ID
fi

SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUILD_SERVICE_ACCOUNT_EMAIL="${BUILD_SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if [[ -z "$GEMINI_SECRET_VERSION" ]]; then
  echo "Set GEMINI_SECRET_VERSION to a reviewed numeric version; latest is not accepted." >&2
  exit 1
fi
if [[ ! "$GEMINI_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "GEMINI_SECRET_VERSION must be a reviewed numeric version; latest is not accepted." >&2
  exit 1
fi

if [[ "$MEAL_SCAN_ENABLED" == "true" ]]; then
  if [[ "$APPLE_BUNDLE_ID" != "alex.PCOS" || "$APPLE_APP_ID" != "6760353511" || "$APPLE_ALLOWED_PRODUCT_IDS" != "cyclebalance.premium.monthly,cyclebalance.premium.annual" ]]; then
    echo "Enabled deployment must use the pinned CycleBalance Apple identity." >&2
    exit 1
  fi
  if [[ "$REVENUECAT_PROJECT_ID" != "proj8da4e000" || "$REVENUECAT_ENTITLEMENT_ID" != "CycleBalance Unlimited" ]]; then
    echo "Enabled deployment must use the pinned CycleBalance RevenueCat configuration." >&2
    exit 1
  fi
  if [[ -z "$PRINCIPAL_HMAC_SECRET_VERSION" ]]; then
    echo "Set PRINCIPAL_HMAC_SECRET_VERSION to a reviewed numeric version before enabling." >&2
    exit 1
  fi
  if [[ ! "$PRINCIPAL_HMAC_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
    echo "A numeric principal-HMAC secret version is required before enabling meal scans." >&2
    exit 1
  fi
  if [[ ! "$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
    echo "APPLE_IAP_PRIVATE_KEY_SECRET_VERSION must be a reviewed numeric pinned version before enabling." >&2
    exit 1
  fi
  if [[ ! "$REVENUECAT_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
    echo "REVENUECAT_SECRET_VERSION must be a reviewed numeric pinned version before enabling." >&2
    exit 1
  fi
  if [[ ! "$APPLE_APP_ID" =~ ^[0-9]{5,20}$ || ! "$APPLE_IAP_KEY_ID" =~ ^[A-Za-z0-9]{4,128}$ || ! "$APPLE_IAP_ISSUER_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "APPLE_APP_ID, APPLE_IAP_KEY_ID, and APPLE_IAP_ISSUER_ID are required before enabling meal scans." >&2
    exit 1
  fi
fi
if [[ -n "$PRINCIPAL_HMAC_SECRET_VERSION" && ! "$PRINCIPAL_HMAC_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "PRINCIPAL_HMAC_SECRET_VERSION must be a numeric pinned version, never latest." >&2
  exit 1
fi
if [[ -n "$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION" && ! "$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "APPLE_IAP_PRIVATE_KEY_SECRET_VERSION must be a numeric pinned version, never latest." >&2
  exit 1
fi
if [[ -n "$REVENUECAT_SECRET_VERSION" && ! "$REVENUECAT_SECRET_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "REVENUECAT_SECRET_VERSION must be a numeric pinned version, never latest." >&2
  exit 1
fi

if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
  AUTH_FLAG="--allow-unauthenticated"
  INVOKER_IAM_CHECK_FLAG="--no-invoker-iam-check"
else
  AUTH_FLAG="--no-allow-unauthenticated"
  INVOKER_IAM_CHECK_FLAG="--invoker-iam-check"
fi

private_invoker_gate_rejects_status() {
  [[ "$1" == "403" || "$1" == "404" ]]
}

public_app_integrity_challenge_status() {
  [[ "$1" == "401" ]]
}

wait_for_invoker_access_state() {
  local service_url="$1"
  local attempt status
  for ((attempt = 1; attempt <= INVOKER_ACCESS_ATTEMPTS; attempt += 1)); do
    status="$(curl --silent --show-error --max-time 5 \
      --output /dev/null \
      --write-out '%{http_code}' \
      --request POST \
      "$service_url/v1/meal-scans/estimate" 2>/dev/null || printf '000')"
    if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
      public_app_integrity_challenge_status "$status" && return 0
    elif private_invoker_gate_rejects_status "$status"; then
      return 0
    fi
    sleep 2
  done

  if [[ "$ALLOW_UNAUTHENTICATED" == "true" ]]; then
    echo "Timed out waiting for the public HTTP 401 App Check challenge." >&2
  else
    echo "Timed out waiting for expected anonymous HTTP 403 or 404 from the Cloud Run invoker gate." >&2
  fi
  return 1
}

ENV_VARS="^@^NODE_ENV=production@MEAL_SCAN_ENABLED=${MEAL_SCAN_ENABLED}@APP_CHECK_REQUIRED=true@FIREBASE_APP_ID=${FIREBASE_APP_ID}@APPLE_BUNDLE_ID=${APPLE_BUNDLE_ID}@APPLE_APP_ID=${APPLE_APP_ID}@APPLE_ALLOWED_PRODUCT_IDS=${APPLE_ALLOWED_PRODUCT_IDS}@APPLE_IAP_KEY_ID=${APPLE_IAP_KEY_ID}@APPLE_IAP_ISSUER_ID=${APPLE_IAP_ISSUER_ID}@REVENUECAT_PROJECT_ID=${REVENUECAT_PROJECT_ID}@REVENUECAT_ENTITLEMENT_ID=${REVENUECAT_ENTITLEMENT_ID}@REVENUECAT_TIMEOUT_MS=3000@MEAL_SCAN_QUOTA_STORE=firestore@MEAL_SCAN_QUOTA_COLLECTION=mealScanRollingQuota@MEAL_SCAN_RESULT_CACHE=firestore@MEAL_SCAN_IDEMPOTENCY_STORE=firestore@MEAL_SCAN_IDEMPOTENCY_COLLECTION=mealScanIdempotency@MEAL_SCAN_IDEMPOTENCY_PENDING_TTL_MS=30000@MEAL_SCAN_REQUEST_GATE=firestore@MEAL_SCAN_REQUEST_GATE_COLLECTION=mealScanRequestGate@MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT=30@MEAL_SCAN_REQUESTS_PER_DAY_LIMIT=200@MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT=300@MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT=3000@MEAL_SCAN_PRINCIPAL_ATTEMPT_STORE=firestore@MEAL_SCAN_PRINCIPAL_ATTEMPT_COLLECTION=mealScanPrincipalAttempts@MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_MINUTE_LIMIT=3@MEAL_SCAN_PRINCIPAL_ATTEMPTS_PER_24_HOURS_LIMIT=30@MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_MINUTE_LIMIT=60@MEAL_SCAN_GLOBAL_PROVIDER_DISPATCHES_PER_24_HOURS_LIMIT=1000@MEAL_SCAN_BUDGET_STORE=firestore@MEAL_SCAN_RESULT_CACHE_TTL_SECONDS=86400@MEAL_SCAN_RESULT_LEASE_TTL_MS=30000@MEAL_SCAN_CONTROL_CACHE_TTL_MS=30000@MEAL_SCAN_DAILY_LIMIT=10@MEAL_SCAN_TRIAL_DAILY_LIMIT=5@MEAL_SCAN_TRIAL_TOTAL_LIMIT=25@MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD=15@MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD=20@MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD=25@MAX_BODY_BYTES=2200000@MAX_IMAGE_BYTES=1500000@MAX_IMAGE_PIXELS=12000000@MAX_CANONICAL_IMAGE_BYTES=750000@APP_CHECK_TIMEOUT_MS=5000@APPLE_STATUS_TIMEOUT_MS=5000@GEMINI_TIMEOUT_MS=12000"
SECRETS="GEMINI_API_KEY=${GEMINI_SECRET_NAME}:${GEMINI_SECRET_VERSION}"
if [[ -n "$PRINCIPAL_HMAC_SECRET_VERSION" ]]; then
  SECRETS="${SECRETS},MEAL_SCAN_PRINCIPAL_HMAC_SECRET=${PRINCIPAL_HMAC_SECRET_NAME}:${PRINCIPAL_HMAC_SECRET_VERSION}"
fi
if [[ -n "$APPLE_IAP_PRIVATE_KEY_SECRET_VERSION" ]]; then
  SECRETS="${SECRETS},APPLE_IAP_PRIVATE_KEY=${APPLE_IAP_PRIVATE_KEY_SECRET_NAME}:${APPLE_IAP_PRIVATE_KEY_SECRET_VERSION}"
fi
if [[ -n "$REVENUECAT_SECRET_VERSION" ]]; then
  SECRETS="${SECRETS},REVENUECAT_SECRET_API_KEY=${REVENUECAT_SECRET_NAME}:${REVENUECAT_SECRET_VERSION}"
fi

gcloud config set project "$PROJECT_ID" --quiet
[[ -x "$FIRESTORE_RULES_DEPLOY_SCRIPT" ]] || {
  echo "Missing executable Firestore Rules deployment: $FIRESTORE_RULES_DEPLOY_SCRIPT" >&2
  exit 1
}
PROJECT_ID="$PROJECT_ID" "$FIRESTORE_RULES_DEPLOY_SCRIPT"

gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --source "$PROXY_DIR" \
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
  "$AUTH_FLAG" \
  "$INVOKER_IAM_CHECK_FLAG"

gcloud run services update "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --quiet \
  "$INVOKER_IAM_CHECK_FLAG"

SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" --project "$PROJECT_ID" --region "$REGION" --format='value(status.url)')"
wait_for_invoker_access_state "$SERVICE_URL"

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
echo "MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true PROJECT_ID=$PROJECT_ID REGION=$REGION $SCRIPT_DIR/deploy-cloud-run.sh"
echo
echo "Set this in Config/LocalSecrets.xcconfig only for builds that should call the proxy:"
echo "MEAL_SCAN_PROXY_BASE_URL = $SERVICE_URL"
