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
- `MEAL_SCAN_REQUEST_GATE=firestore`: production request-abuse gate. It counts every integrity-verified request before RevenueCat, including result-cache hits.
- `MEAL_SCAN_REQUEST_GATE_COLLECTION`: defaults to the TTL-managed `mealScanRequestGate`, isolated from billable scan quota records.
- `MEAL_SCAN_REQUESTS_PER_MINUTE_LIMIT`: defaults to `30`.
- `MEAL_SCAN_REQUESTS_PER_DAY_LIMIT`: defaults to `200`.
- `MEAL_SCAN_GLOBAL_REQUESTS_PER_MINUTE_LIMIT`: defaults to `300` across all submitted app-user IDs.
- `MEAL_SCAN_GLOBAL_REQUESTS_PER_DAY_LIMIT`: defaults to `3000` across all submitted app-user IDs.
- `MEAL_SCAN_RESULT_CACHE=firestore`: production image-hash deduplication mode. It also defaults to Firestore when `MEAL_SCAN_QUOTA_STORE=firestore`.
- `MEAL_SCAN_RESULT_CACHE_COLLECTION`: defaults to `mealScanEstimateCache`.
- `MEAL_SCAN_RESULT_CACHE_TTL_SECONDS`: defaults to `86400` (24 hours). Cache records contain structured nutrition output and hashes, never raw image bytes.
- `MEAL_SCAN_RESULT_LEASE_TTL_MS`: defaults to `30000` and must exceed the Gemini timeout by at least five seconds.
- `MAX_BODY_BYTES`: defaults to `5242880` (5 MiB).
- `MAX_IMAGE_BYTES`: defaults to `1500000` bytes after JPEG normalization.
- `MEAL_SCAN_BUDGET_STORE=firestore`: reads dynamic spend controls from `mealScanControls/global`.
- `MEAL_SCAN_CONTROL_CACHE_TTL_MS`: defaults to `30000` so budget changes propagate without a Firestore read on every request.
- `MEAL_SCAN_MONTHLY_BUDGET_ALERT_USD`: production deploy value is `75`; responses remain enabled but report `budget.mode = "alert"`.
- `MEAL_SCAN_MONTHLY_BUDGET_DEGRADE_USD`: production deploy value is `90`; requests are forced to `gemini-3.1-flash-lite`.
- `MEAL_SCAN_MONTHLY_BUDGET_DISABLE_USD`: production deploy value is `120`; integrity-verified requests return `503 meal_scan_unavailable` with `monthly_budget_exceeded` before RevenueCat, quota, or Gemini calls. Billing and manual control modes are combined fail-closed, so the most restrictive mode always wins.

The proxy rejects missing production App Check tokens before reading the body, validates the model allowlist, verifies app integrity, checks the fail-closed budget state, applies per-ID and global request-abuse limits before RevenueCat, verifies entitlement/trial status, checks the per-user image/model/schema/prompt/meal-type/locale result cache, consumes scan quota on cache misses, and only then calls the selected Gemini model. A cache hit does not consume another scan or call Gemini. A 30-second Firestore lease collapses concurrent identical requests during the normal 12-second provider deadline; it is a cost-control optimization rather than an exactly-once guarantee after infrastructure timeouts. It defaults to `gemini-3.1-flash-lite`; `gemini-2.5-flash` is available only as an explicit evaluation/escalation model. Requests that omit `modelId` use the 3.1 Flash-Lite default, and degraded budget mode forces every request back to that least-expensive production model. Retired `gemini-2.0-flash-lite`, unavailable `gemini-2.5-flash-lite`, and unknown model IDs are rejected before entitlement, quota, or provider calls. The proxy does not use Gemini File API uploads, tools, grounding, or explicit context caching.

Quota defaults:

- Trial: 5 photo estimates per day and 25 total photo estimates for the trial period.
- Paid: 5 photo estimates soft warning threshold and 10 photo estimates hard limit per day.
- Request abuse limit: 30 integrity-verified requests per minute and 200 per day for each submitted ID, plus 300 per minute and 3,000 per day globally, including cache hits and failed entitlement checks.
- Barcode lookup and manual meal logging are not routed through this proxy and are not limited by these scan quotas.

Successful responses include:

- `quota.remainingToday`
- `quota.remainingTrial` for trial users, otherwise `null`
- `budget.mode` (`normal`, `alert`, or `degraded`)
- `provider.id`, `provider.modelId`, and `provider.selectionReason`
- `cacheHit` (`true` when a successful per-user image/model/schema/prompt/meal-type/locale result is reused)
- `modelId`
- `usage.inputTokens`, `usage.outputTokens`, `usage.totalTokens`, and `usage.estimatedCostUSD`

The proxy must not store raw image bytes. Application logs are limited to image hash prefixes, provider/model ID, token usage, estimated cost, quota tier, budget mode, and status metadata; pseudonymous app user hashes and reviewed meal content are excluded. The project log router discards Cloud Run HTTP request logs for this service while preserving application and audit logs. This guarantee covers CycleBalance infrastructure only: standard paid Gemini abuse monitoring may retain request content for 55 days unless Google has approved Zero Data Retention for the production project.

Client JSON errors, oversized bodies, provider timeouts, and malformed provider output return distinct user-safe `reason` and `retryable` fields. Provider parse failures are never reported as invalid client JSON.

RevenueCat API V2 is the entitlement and trial-state source, not the quota ledger. The server key is restricted to read-only Customer and Subscription access. Keep scanner quota in Firestore for v1. RevenueCat Virtual Currency can be reconsidered only if scan credits become a user-facing product concept. CycleBalance does not require accounts for v1 scanner access. Anonymous RevenueCat app user IDs are non-secret identifiers, not cryptographic purchase credentials: App Check, shared per-ID quota, and the global pre-entitlement gate bound the limited-production exposure, but they do not prevent a paid ID from being copied between valid app installations. Do not materially raise quotas or broaden rollout until the proxy also verifies signed StoreKit transaction evidence or binds entitlement access to a direct App Attest installation identity. RevenueCat Trusted Entitlements protects client responses from tampering but does not solve app-user-ID sharing.

## Live Production Posture

- Google Cloud project: `cyclebalance-prod-20260710` (`CycleBalance Production`).
- Cloud Run service: `cyclebalance-meal-scan-proxy` in `us-central1`.
- Hardened disabled revision: `cyclebalance-meal-scan-proxy-00021-gl2`, serving 100% of traffic.
- The service is private and has `MEAL_SCAN_ENABLED=false`; this is intentional while the App Store privacy and labeled-quality gates remain open.
- Firebase App Check is configured for bundle ID `alex.PCOS`, with App Attest in Release and limited-use token consumption on the proxy.
- Firestore quota, request-gate, and estimate-cache records have active TTL policies. The `cloud.firestore` Firebase Rules release denies every mobile/web read and write; only IAM-authorized server clients can access proxy-owned records.
- Google Cloud budget: `$150/month`, with notifications at 50%, 75%, 90%, and 100% plus forecasted 100%.
- A Pub/Sub-triggered budget controller writes the live Firestore control document. The scanner alerts at `$75`, degrades at `$90`, and disables at `$120`, leaving a `$30` buffer. Google Cloud budgets are alerts rather than billing caps; the proxy disable gate is the enforceable scanner safeguard.
- Gemini paid inference is funded with a `$25` owner-approved Prepay balance, auto-reload is off, and the AI Studio project spend cap is `$120`. The active Gemini authorization key is bound to the proxy service account, restricted to `generativelanguage.googleapis.com`, stored as Secret Manager version 2, and passed a `gemini-3.1-flash-lite` smoke test. The superseded standard key and secret version are retired. The same project rejects `gemini-2.5-flash-lite` as unavailable to new users.
- Google AI Studio storage is disabled for both GenerateContent and Interactions, with the fallback retention control reduced to seven days. No project-specific Zero Data Retention approval or request submission is verified, so production photo uploads remain disabled.
- Cloud Run is limited to two proxy instances, 20 concurrent requests per instance, and a 30-second request timeout.
- No custom runtime service account has a user-managed key.
- The corrected physical App Attest probe ran on `General Kenobi` against temporary enabled revision `cyclebalance-meal-scan-proxy-00020-lqb`. XCTest ran the dedicated Release test once with zero failures; the isolated user and global request-gate documents were created at `2026-07-13T05:24:20.309744Z` with count `1`, while the billable probe quota document remained absent and no `meal_scan_estimate` event was emitted. The transient `alex.PCOS` app was removed because it was absent before the probe. Rollback revision `cyclebalance-meal-scan-proxy-00021-gl2` is private and disabled; anonymous POST returns `403`, and authenticated POST returns `503 feature_disabled`.

Production setup scripts:

- `scripts/bootstrap-gcp.sh`: enables required Google Cloud APIs, creates the Cloud Run service account, creates Firestore if needed, deploys deny-all mobile/web rules, and stores Gemini/RevenueCat secrets in Secret Manager through hidden prompts.
- `scripts/deploy-firestore-rules.sh`: creates a validated immutable ruleset, creates or patches the pinned production `cloud.firestore` release, and verifies the deployed source without putting OAuth tokens in process arguments.
- `scripts/deploy-cloud-run.sh`: deploys and reads back deny-all Firebase Rules before every Cloud Run deployment, then deploys the proxy with `MEAL_SCAN_ENABLED=false` by default. Access-mode verification allows up to three minutes for Cloud Run IAM propagation.
- `scripts/run-physical-app-check-probe.sh`: runs the pinned physical Release probe, proves exactly one post-integrity request-gate advance without billable quota or Gemini estimation, always restores private/disabled state, removes only a transient probe app, and retains a mode-700 result bundle plus redacted console log when a run fails.
- `scripts/estimate-usage-cost.mjs`: estimates daily/monthly Gemini spend for scanner usage scenarios.

Full setup runbook: `docs/meal_scan_flash_lite_production_setup.md`.
