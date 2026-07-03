# CycleBalance Meal Scan Proxy

Cloud Run proxy for production Gemini meal estimates. The iOS app sends a normalized JPEG and metadata to this service; the Gemini API key stays server-side.

Required production environment:

- `GEMINI_API_KEY`: injected from Secret Manager.
- `REVENUECAT_SECRET_API_KEY`: RevenueCat secret key for server-side entitlement checks.
- `REVENUECAT_ENTITLEMENT_ID`: defaults to `CycleBalance Unlimited`.
- `MEAL_SCAN_ENABLED`: set to `false` as a remote kill switch. Disabled requests return `503 meal_scan_unavailable` before entitlement, quota, or Gemini calls.
- `APP_ATTEST_REQUIRED=true`: production gate that rejects the legacy shared-secret header and requires App Attest headers.
- `APP_ATTEST_VERIFIER_URL`: production verifier service for App Attest assertions. Required when `APP_ATTEST_REQUIRED=true`; without it, production requests fail closed with `app_attest_verifier_unconfigured`. The verifier receives `keyId`, optional first-use `attestation`, `assertion`, `challenge`, `imageHash`, and `revenueCatAppUserId`.
- `APP_ATTEST_VERIFIER_BEARER`: optional bearer token sent to the verifier service.
- `APP_INTEGRITY_SHARED_SECRET`: temporary app-integrity gate for internal testing only. Do not use this as the production integrity mechanism.
- `APP_ATTEST_ACCEPT_UNVERIFIED_ASSERTIONS`: development-only bypass for verifier bring-up. Never enable in production.
- `MEAL_SCAN_DAILY_LIMIT`: defaults to `10`.
- `MEAL_SCAN_SOFT_DAILY_LIMIT`: defaults to `5`.
- `MEAL_SCAN_TRIAL_DAILY_LIMIT`: defaults to `5`.
- `MEAL_SCAN_TRIAL_TOTAL_LIMIT`: defaults to `25`.
- `MEAL_SCAN_QUOTA_STORE=firestore`: production quota mode. Grant the Cloud Run service account Firestore write access.
- `MEAL_SCAN_QUOTA_COLLECTION`: defaults to `mealScanDailyQuota`.
- `MEAL_SCAN_MONTHLY_SPEND_USD`: current month-to-date scanner API spend, supplied by billing export, log aggregation, or an ops job.
- `MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD`: defaults to `50`; responses remain enabled but report `budget.mode = "alert"`.
- `MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD`: defaults to `75`; Flash requests are forced back to `gemini-2.5-flash-lite`.
- `MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD`: defaults to `100`; requests return `503 meal_scan_unavailable` with `monthly_budget_exceeded` before app integrity, entitlement, quota, or Gemini calls.

The proxy validates app integrity, checks RevenueCat entitlement/trial status, consumes quota, and only then calls the selected Gemini model. It defaults to `gemini-2.5-flash-lite`; `gemini-2.5-flash` is available only as an escalation model and is disabled automatically while the monthly budget is in degraded mode. It does not use Gemini File API uploads, tools, grounding, or explicit context caching.

Quota defaults:

- Trial: 5 photo estimates per day and 25 total photo estimates for the trial period.
- Paid: 5 photo estimates soft warning threshold and 10 photo estimates hard limit per day.
- Barcode lookup and manual meal logging are not routed through this proxy and are not limited by these scan quotas.

Successful responses include:

- `quota.remainingToday`
- `quota.remainingTrial` for trial users, otherwise `null`
- `budget.mode` (`normal`, `alert`, or `degraded`)
- `provider.id`, `provider.modelId`, and `provider.selectionReason`
- `cacheHit` (`false` unless server-side result caching is added later)
- `modelId`
- `usage.inputTokens`, `usage.outputTokens`, `usage.totalTokens`, and `usage.estimatedCostUSD`

The proxy must not store raw image bytes. Logs should stay limited to hashed app user identifiers, image hash prefixes, provider/model ID, token usage, estimated cost, quota tier, budget mode, and status metadata.

RevenueCat is the entitlement and trial-state source, not the quota ledger. Keep scanner quota in Firestore for v1. RevenueCat Virtual Currency can be reconsidered only if scan credits become a user-facing product concept. CycleBalance does not require accounts for v1 scanner access; anonymous RevenueCat app user IDs are acceptable for launch but are not reliable abuse controls across reinstall or multiple devices.

Production setup scripts:

- `scripts/bootstrap-gcp.sh`: enables required Google Cloud APIs, creates the Cloud Run service account, creates Firestore if needed, and stores Gemini/RevenueCat secrets in Secret Manager through hidden prompts.
- `scripts/deploy-cloud-run.sh`: deploys the proxy to Cloud Run with `MEAL_SCAN_ENABLED=false` by default.
- `scripts/estimate-usage-cost.mjs`: estimates daily/monthly Gemini spend for scanner usage scenarios.

Full setup runbook: `docs/meal_scan_flash_lite_production_setup.md`.
