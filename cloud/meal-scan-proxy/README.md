# CycleBalance Meal Scan Proxy

Cloud Run proxy for CycleBalance meal-photo estimates. The iOS app sends a normalized JPEG plus signed StoreKit evidence; Gemini credentials, purchase verification, quota enforcement, and budget controls remain server-side.

## Request and trust contract

An accepted JSON request contains `requestId`, `signedTransactionJWS`, `imageBase64`, `mealType`, and `locale`. `modelId` may select only an allowlisted model. Raw customer identifiers and client-asserted entitlement fields are rejected.

The request path is deliberately ordered:

1. Require Firebase App Check in production and validate the bounded JSON envelope.
2. Apply the coarse HMAC-pseudonymous per-evidence and global pre-verification abuse shield before Sharp decodes the JPEG. Its deployed limits are 30/minute and 200/day per submitted evidence key, plus 300/minute and 3,000/day globally.
3. Verify `signedTransactionJWS` with Apple's signed-data verifier and bundled Apple root certificates. Production and Sandbox verification are kept separate.
4. Derive the HMAC purchase principal only from the verified Apple environment and original transaction ID, then enforce 3 attempts/minute and 30 attempts/rolling 24 hours in a durable ledger before any current-status network lookup or image decoding.
5. Query the App Store Server API for current subscription status. Captured evidence is not enough: only an unrevoked, unexpired active or billing-grace-period transaction for the pinned bundle, app, environment, and product is accepted.
6. Check the result cache. A valid cache hit is free and remains available in budget-disabled mode.
7. In one Firestore transaction, reserve idempotency, principal rolling quota, a one-call-per-principal in-flight lease, and the durable global provider allowance. The global immutable ceilings are 60 fresh dispatches/minute and 1,000 fresh dispatches/rolling 24 hours. A global denial does not debit principal quota, and cache hits bypass this reservation.
8. Acquire the short result lease and call the allowlisted Gemini model. Completion, unknown outcome, or pre-dispatch failure releases the principal lease; crash recovery uses its bounded expiry.

The service never stores raw image bytes. Cache records contain only validated structured output and hashes. The maximum HTTP body is 2,200,000 bytes (2.2 MB), the decoded JPEG maximum is 1,500,000 bytes, the pixel maximum is 12,000,000, and the canonicalized JPEG maximum is 750,000 bytes.

## Quota and idempotency

Quota uses a rolling 24-hour window rather than a calendar-day counter:

- Paid: 10 fresh scans per rolling window; the client shows a warning at 8. In degraded budget mode the server cap is 5.
- Trial: 5 fresh scans per rolling window and 25 fresh scans for the trial lifetime. Degraded mode disables fresh trial dispatch. Lifetime exhaustion has no reset time and is not retryable.
- Cache hits do not consume scan quota. Barcode lookup and manual logging do not use this proxy.

Successful responses expose one truthful quota shape: `tier`, `used`, `limit`, `remaining`, `windowSeconds`, `resetAt`, and `retryAfterSeconds`. Trial lifetime exhaustion reports lifetime `used`, `limit`, and zero `remaining`, with null reset and retry fields.

The production Firestore collections are:

- `mealScanRollingQuota`: rolling-window and trial-lifetime counters.
- `mealScanIdempotency`: pending and completed request outcomes.
- `mealScanRequestGate`: pre-decode abuse counters.
- `mealScanPrincipalAttempts`: verified-principal 3/minute and 30/rolling-24-hour attempt ledger.
- `mealScanEstimateCache`: structured result cache and short leases.

All five collections are server-only and have TTL cleanup on `expiresAt`. The global provider allowance and principal in-flight lease live in `mealScanRollingQuota`, so their reservation is atomic with scan quota. Mobile and web access is denied by `firestore.rules`.

## Cost controls

Scanner spend controls are $15 alert, $20 degraded, and $25 disabled. The proxy derives a spend mode from the current Firestore `spendUsd` using deployment-pinned thresholds, then combines it with billing and manual modes by selecting the most restrictive state.

- Alert mode reports the warning but otherwise behaves normally.
- Degraded mode forces the least-expensive production model, caps paid fresh scans at 5, and blocks fresh trial scans.
- Disabled mode blocks fresh dispatch before quota consumption or Gemini, while valid cache hits remain available.
- Missing or invalid production control state fails closed.

The budget controller uses the same $15, $20, and $25 defaults. Google Cloud budgets are notifications, not hard caps; this server-side dispatch gate is the enforceable scanner control.

## Identifier-free operations and monitoring

The proxy emits one structured `meal_scan_scanner_event` schema to stdout for Cloud Logging. Its bounded event types are `authorization_rejection`, `request_gate_decision`, `budget_state`, `cache_decision`, `quota_decision`, `global_dispatch_decision`, `provider_call`, and `request_result`. These events expose only operational dimensions: bounded outcomes/reasons, status class, tier, budget mode, cache disposition, provider/model, input/output token counts, estimated request cost, and latency.

Cache events distinguish `server_hit`, lease/wait hits, `fresh_dispatch`, and bounded unavailable/in-progress outcomes. The server cannot observe an on-device lookup, so `localCacheDisposition=not_observed` is explicit rather than inferred. Firestore budget controls older than 24 hours emit a stale signal; missing or invalid control reads emit an unavailable signal and continue to fail closed.

Scanner events never include raw JWS, original transaction IDs, pseudonymous principals, request IDs, image hashes or bytes, App Check tokens, API keys, or user-entered content. Unknown rejection text is reduced to the bounded reason `other`; exception messages are not copied into scanner events.

`scripts/deploy-monitoring-alerts.sh` renders and validates four log-based metrics and alert policies for the pinned production project. The default command is local validation-only and does not invoke a Google Cloud mutation:

```sh
./scripts/deploy-monitoring-alerts.sh
```

The staged policies alert on:

- budget-mode transitions, restrictive modes, and stale/unavailable budget state;
- 60 fresh provider calls per minute or more;
- a 5xx ratio above 5% for 10 minutes;
- more than 20 combined App Check and StoreKit/JWS rejections per minute.

The script is idempotent by metric name and alert-policy display name, contains no notification destination or destination secret, and requires explicit approval before this separate mutation command is run:

```sh
APPLY=true PROJECT_ID=cyclebalance-prod-20260710 ./scripts/deploy-monitoring-alerts.sh
```

Applying monitoring does not deploy Cloud Run, change ingress, or alter the scanner flag. Keep `MEAL_SCAN_ENABLED=false` and `ALLOW_UNAUTHENTICATED=false` until scanner activation is separately approved.

## Production configuration

Required production values include:

- `GEMINI_API_KEY` from Secret Manager.
- `PRINCIPAL_HMAC_SECRET` from Secret Manager, at least 32 characters.
- `APPLE_IAP_PRIVATE_KEY` from a numerically pinned Secret Manager version.
- `APPLE_IAP_KEY_ID` and `APPLE_IAP_ISSUER_ID` for the App Store Server API.
- `APPLE_BUNDLE_ID=alex.PCOS`, `APPLE_APP_ID=6760353511`, and exactly `cyclebalance.premium.monthly,cyclebalance.premium.annual`; enabled production startup rejects any other Apple identity.
- `FIREBASE_APP_ID`, `APP_CHECK_REQUIRED=true`, and Firestore backends for quota, idempotency, the coarse abuse shield, verified-principal attempts, cache, and budget control.

Apple trust roots are version-controlled in `certs/` with source URLs and SHA-256 provenance; deployment does not accept an unpinned root-certificate environment secret. Network, timeout, HTTP 429, HTTP 5xx, and retryable online-certificate-check failures are temporary `503` errors. Invalid signatures, claims, products, revoked purchases, and expired purchases are non-retryable authorization failures.

Operational defaults include a 5-second App Check timeout, 5-second App Store status timeout, 12-second Gemini timeout, 30-second idempotency/lease interval, and a 24-hour result-cache TTL. The lease interval must exceed the provider timeout by at least five seconds.

## Deployment and activation

`scripts/bootstrap-gcp.sh` provisions the runtime identities, server-only Firestore policy, required secrets, and TTL policies. `scripts/deploy-cloud-run.sh` re-verifies the deny-all rules, requires pinned secret versions, deploys, and verifies ingress state. Neither script should be run as part of a local test.

Every deployment defaults to both gates closed:

```sh
MEAL_SCAN_ENABLED=false
ALLOW_UNAUTHENTICATED=false
```

Public scanner activation is a separate, explicit approval-gated action after all release checks pass:

```sh
MEAL_SCAN_ENABLED=true ALLOW_UNAUTHENTICATED=true PROJECT_ID=$PROJECT_ID REGION=$REGION ./scripts/deploy-cloud-run.sh
```

Do not enable only one flag. Keep the service private and scanner-disabled until the owner approves public activation.

## Local verification

From this directory:

```sh
npm test
npm audit --audit-level=high
bash -n scripts/bootstrap-gcp.sh scripts/deploy-cloud-run.sh scripts/deploy-monitoring-alerts.sh
```

The default model is `gemini-3.1-flash-lite`; `gemini-2.5-flash` is evaluation-only. Unknown or retired model IDs are rejected before provider dispatch. The proxy does not use Gemini File API uploads, tools, grounding, or explicit context caching.
