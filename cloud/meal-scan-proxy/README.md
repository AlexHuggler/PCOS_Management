# CycleBalance Meal Scan Proxy

Cloud Run proxy for production Gemini meal estimates. The iOS app sends a normalized JPEG and metadata to this service; the Gemini API key stays server-side.

Required production environment:

- `GEMINI_API_KEY`: injected from Secret Manager.
- `REVENUECAT_SECRET_API_KEY`: least-privilege RevenueCat V2 secret key for server-side entitlement checks.
- `REVENUECAT_PROJECT_ID`: RevenueCat V2 project identifier. Production uses `proj8da4e000`.
- `REVENUECAT_ENTITLEMENT_ID`: defaults to `CycleBalance Unlimited`.
- `MEAL_SCAN_ENABLED`: set to `true` only after production gates pass. Production defaults fail closed when this variable is absent; disabled requests return `503 meal_scan_unavailable` before entitlement, quota, or Gemini calls.
- `APP_CHECK_REQUIRED=true`: production gate that requires a Firebase App Check limited-use token backed by Apple App Attest.
- `FIREBASE_APP_ID`: pins accepted App Check tokens to the CycleBalance iOS app. Production uses `1:947929010052:ios:6e68c8645a6a6b5e3057d1`.
- `APP_CHECK_TIMEOUT_MS`: defaults to `5000`.
- `REVENUECAT_TIMEOUT_MS`: defaults to `5000`.
- `GEMINI_TIMEOUT_MS`: defaults to `12000`.
- `MEAL_SCAN_DAILY_LIMIT`: defaults to `10`.
- `MEAL_SCAN_SOFT_DAILY_LIMIT`: defaults to `5`.
- `MEAL_SCAN_TRIAL_DAILY_LIMIT`: defaults to `5`.
- `MEAL_SCAN_TRIAL_TOTAL_LIMIT`: defaults to `25`.
- `MEAL_SCAN_QUOTA_STORE=firestore`: production quota mode. Grant the Cloud Run service account Firestore write access.
- `MEAL_SCAN_QUOTA_COLLECTION`: defaults to `mealScanDailyQuota`.
- `MEAL_SCAN_RESULT_CACHE=firestore`: production image-hash deduplication mode. It also defaults to Firestore when `MEAL_SCAN_QUOTA_STORE=firestore`.
- `MEAL_SCAN_RESULT_CACHE_COLLECTION`: defaults to `mealScanEstimateCache`.
- `MEAL_SCAN_RESULT_CACHE_TTL_SECONDS`: defaults to `86400` (24 hours). Cache records contain structured nutrition output and hashes, never raw image bytes.
- `MAX_BODY_BYTES`: defaults to `5242880` (5 MiB).
- `MAX_IMAGE_BYTES`: defaults to `1500000` bytes after JPEG normalization.
- `MEAL_SCAN_BUDGET_STORE=firestore`: reads dynamic spend controls from `mealScanControls/global`.
- `MEAL_SCAN_CONTROL_CACHE_TTL_MS`: defaults to `30000` so budget changes propagate without a Firestore read on every request.
- `MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD`: production deploy value is `75`; responses remain enabled but report `budget.mode = "alert"`.
- `MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD`: production deploy value is `90`; requests are forced to `gemini-2.5-flash-lite`.
- `MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD`: production deploy value is `120`; requests return `503 meal_scan_unavailable` with `monthly_budget_exceeded` before integrity, entitlement, quota, or Gemini calls.

The proxy validates the model allowlist, checks app integrity, checks RevenueCat entitlement/trial status, checks the per-user image-hash result cache, consumes quota on cache misses, and only then calls the selected Gemini model. A cache hit does not consume another scan or call Gemini. It defaults to `gemini-2.5-flash-lite`; `gemini-2.5-flash` is available only as an escalation model, and `gemini-3.1-flash-lite` is allowlisted for controlled migration evaluation. Requests that omit `modelId` keep the backward-compatible 2.5 Flash-Lite default. Any non-default model is forced back to `gemini-2.5-flash-lite` while the monthly budget is in degraded mode. Retired `gemini-2.0-flash-lite` requests are rejected before gated or provider calls. The proxy does not use Gemini File API uploads, tools, grounding, or explicit context caching.

Quota defaults:

- Trial: 5 photo estimates per day and 25 total photo estimates for the trial period.
- Paid: 5 photo estimates soft warning threshold and 10 photo estimates hard limit per day.
- Barcode lookup and manual meal logging are not routed through this proxy and are not limited by these scan quotas.

Successful responses include:

- `quota.remainingToday`
- `quota.remainingTrial` for trial users, otherwise `null`
- `budget.mode` (`normal`, `alert`, or `degraded`)
- `provider.id`, `provider.modelId`, and `provider.selectionReason`
- `cacheHit` (`true` when a successful per-user image/model/schema/prompt result is reused)
- `modelId`
- `usage.inputTokens`, `usage.outputTokens`, `usage.totalTokens`, and `usage.estimatedCostUSD`

The proxy must not store raw image bytes. Logs should stay limited to hashed app user identifiers, image hash prefixes, provider/model ID, token usage, estimated cost, quota tier, budget mode, and status metadata. This guarantee covers CycleBalance infrastructure only: standard paid Gemini abuse monitoring may retain request content for 55 days unless Google has approved Zero Data Retention for the production project.

Client JSON errors, oversized bodies, provider timeouts, and malformed provider output return distinct user-safe `reason` and `retryable` fields. Provider parse failures are never reported as invalid client JSON.

RevenueCat API V2 is the entitlement and trial-state source, not the quota ledger. The server key is restricted to read-only Customer and Subscription access. Keep scanner quota in Firestore for v1. RevenueCat Virtual Currency can be reconsidered only if scan credits become a user-facing product concept. CycleBalance does not require accounts for v1 scanner access; anonymous RevenueCat app user IDs are acceptable for launch but are not reliable abuse controls across reinstall or multiple devices.

## Live Production Posture

- Google Cloud project: `cyclebalance-prod-20260710` (`CycleBalance Production`).
- Cloud Run service: `cyclebalance-meal-scan-proxy` in `us-central1`.
- The service is private and has `MEAL_SCAN_ENABLED=false`; this is intentional while the App Store privacy and labeled-quality gates remain open.
- Firebase App Check is configured for bundle ID `alex.PCOS`, with App Attest in Release and limited-use token consumption on the proxy.
- Firestore quota and estimate-cache records have active TTL policies.
- Google Cloud budget: `$150/month`, with notifications at 50%, 75%, 90%, and 100% plus forecasted 100%.
- A Pub/Sub-triggered budget controller writes the live Firestore control document. The scanner alerts at `$75`, degrades at `$90`, and disables at `$120`, leaving a `$30` buffer. Google Cloud budgets are alerts rather than billing caps; the proxy disable gate is the enforceable scanner safeguard.
- Gemini inference currently remains unavailable because the billing account's Prepay balance is depleted. Model metadata and key authentication succeed, but generation returns `429 RESOURCE_EXHAUSTED`. Before rollout, fund an owner-approved `$10-$25` evaluation balance, set the AI Studio project spend cap to `$120`, and keep auto-reload off unless the owner separately approves a monthly auto-charge limit no greater than `$150`.
- Cloud Run is limited to two proxy instances, 20 concurrent requests per instance, and a 30-second request timeout.
- No custom runtime service account has a user-managed key.

Production setup scripts:

- `scripts/bootstrap-gcp.sh`: enables required Google Cloud APIs, creates the Cloud Run service account, creates Firestore if needed, and stores Gemini/RevenueCat secrets in Secret Manager through hidden prompts.
- `scripts/deploy-cloud-run.sh`: deploys the proxy to Cloud Run with `MEAL_SCAN_ENABLED=false` by default.
- `scripts/estimate-usage-cost.mjs`: estimates daily/monthly Gemini spend for scanner usage scenarios.

Full setup runbook: `docs/meal_scan_flash_lite_production_setup.md`.
