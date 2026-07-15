# Task 3 Positive General Kenobi Canary Report

Date: 2026-07-14 (America/Chicago)

Branch: `codex/cyclebalance-1.0.5-rc`

Prior implementation commits:

- `3e6cc191b59cc49661adef2fd6dd8027337e2fcf` (`feat: add approval-gated meal scan canary`)
- `c6949d1` (`docs: record positive canary implementation`)

## Outcome

HARDENED AND PREPARED; LIVE CANARY NOT RUN. The independent review's eight Important findings were addressed in code, scripts, tests, and runbooks. The RC now has a content-free operation-correlation path, affirmative authorization evidence, exact correlated quota arithmetic, a persisted two-window receipt, exact Cloud Run IAM restoration, a canary-specific deploy mode, a one-time Apple IAP `v1` provisioner, and a read-only RevenueCat offering verifier.

No Cloud Run deploy or IAM mutation, Secret Manager write or rotation, RevenueCat configuration change, device build/install/launch, General Kenobi interaction, TestFlight distribution, App Store action, or publication occurred during this remediation. A real entitled scan is still an owner-approved external gate; this work does not claim it passed.

## Review Findings Addressed

1. **Correlated affirmative evidence:** a random canary UUID is accepted only by a development-signed runtime whose embedded profile has `get-task-allow=true`. The client sends the UUID plus `SHA-256(requestId)` in canary-only headers and prints only the operation hash immediately before dispatch. The proxy hash-validates both, preserves the public response schema, and correlates allowlisted App Check, StoreKit JWS, current Apple status, RevenueCat, quota, cache, provider, and request events. Ordinary scanner requests emit none of the canary fields or affirmative events.
2. **Owner-only seed receipt:** seed writes a mode-`0600` content-free receipt only after verified disabled/private rollback. It records lifecycle, approved source and service revisions, random canary ID/hash, exact quota tag, IAM digest, General Kenobi identities, and original/canary app state. Rescan is blocked until the 24-hour result TTL plus a 10-minute ingestion/skew buffer.
3. **Two-window device lifecycle:** a successful seed keeps the development canary installed and preserves local repeat state. Rescan does not rebuild or reinstall. Initially absent devices are uninstalled and verified absent only after final rescan; initially present devices stop with an explicit manual binary/data restore handoff because CoreDevice cannot export the original binary.
4. **Apple IAP key state machine:** `provision-apple-iap-key-v1.sh` defaults to non-mutating dry run, inspects resource/version/IAM metadata before key-file access, aborts on any enabled/disabled/destroyed version, permits only zero versions to exact enabled `v1`, prevents `v2`, and reads back exact proxy-service-account-only `secretAccessor` IAM without printing key material.
5. **Cloud Run IAM:** preflight rejects both `allUsers` and `allAuthenticatedUsers`, requires the invoker IAM check, snapshots a canonical restorable policy before mutation, and restores/compares the exact policy and digest on every armed rollback. Rescan also requires the seed's disabled revision/IAM digest and a bounded no-mutation audit readback; the runbook explicitly says this is continuity evidence, not absolute audit proof.
6. **Strict evidence projection:** Cloud Logging output is piped directly through `positive-canary-evidence.mjs`; raw logs are never written. The helper rejects unexpected fields, sensitive key variants, bearer/JWT/JWS, StoreKit/App Check identifiers, JPEG/PNG base64, PEM, OAuth/RevenueCat key patterns, oversized strings, and high-entropy values before emitting a bounded allowlisted projection. Exact reuse requires zero correlated events of every outcome and an unchanged exact quota snapshot.
7. **Canary-specific deploy mode:** `DEPLOY_MODE=canary` pins the production project/region/service, requires the canary digest, skips global `gcloud config` mutation and Firestore Rules deployment, and limits mutations to the reviewed Cloud Run deployment/access path. General deploy behavior remains unchanged.
8. **Live RevenueCat configuration verification:** `verify-revenuecat-offering-v2.sh` is GET-only, accepts a v2 secret through hidden/stdin memory only, and fails closed unless the active current offering is `default`, exact monthly/annual packages map to the exact `P1M`/`P1Y` products, and active `CycleBalance Unlimited` contains both products. The live harness pipes only the pinned Secret Manager version into this verifier and never persists or exposes it.

Additional hardening verifies a clean tracked/untracked worktree at an owner-approved full commit, strict code signing, pinned team/application identifiers, General Kenobi in `ProvisionedDevices`, and CoreDevice/Xcode UDID continuity. Command-shim tests cover failures, signals, rollback errors, and both initially present/absent device outcomes.

## TDD And Verification Evidence

- Proxy correlation RED: focused canary tests initially failed because correlated fields were missing and an operation/request mismatch returned `200`; GREEN: 3 focused tests passed.
- Swift correlation RED: the focused suite failed to compile because `MealScanCanaryCorrelation` and the injected client argument were absent; GREEN: `GeminiMealScanTests` passed 31/31 after the development-profile-gated implementation.
- Evidence helper RED: the module was initially absent; GREEN: 7/7 tests now cover imported functions plus a spawned CLI success/fail-closed path.
- Canary deploy RED: the command-shim observed Firestore Rules execution in canary mode; GREEN: 2/2 tests prove the skip path and pinned fail-closed identities.
- Apple IAP and RevenueCat scripts: 14/14 focused command-shim/fixture tests passed.
- Positive canary runner: 18/18 tests passed, including the receipt boundary, IAM/public-principal gates, strict signing/source contracts, failure/signal rollback, and initial-present/initial-absent lifecycle outcomes.
- Full proxy suite: `npm test` reported 229 passed, 0 failed, 0 skipped.
- `node --check scripts/positive-canary-evidence.mjs`: passed.
- `bash -n` passed for the positive canary, Cloud Run deploy, Apple IAP provisioner, and RevenueCat verifier scripts.
- `DRY_RUN=true cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`: passed and remained non-mutating.
- `git diff --check`: passed.

## Files In This Remediation

- `PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift`
- `PCOS/PCOSTests/GeminiMealScanTests.swift` (only the canary correlation assertions/tests)
- `cloud/meal-scan-proxy/src/server.js`
- `cloud/meal-scan-proxy/test/proxy.test.js`
- `cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`
- `cloud/meal-scan-proxy/scripts/positive-canary-evidence.mjs`
- `cloud/meal-scan-proxy/scripts/deploy-cloud-run.sh`
- `cloud/meal-scan-proxy/scripts/provision-apple-iap-key-v1.sh`
- `cloud/meal-scan-proxy/scripts/verify-revenuecat-offering-v2.sh`
- `cloud/meal-scan-proxy/test/positive-canary-script.test.js`
- `cloud/meal-scan-proxy/test/positive-canary-evidence.test.js`
- `cloud/meal-scan-proxy/test/canary-deploy-mode.test.js`
- `cloud/meal-scan-proxy/test/provision-apple-iap-key-v1.test.js`
- `cloud/meal-scan-proxy/test/revenuecat-offering-verifier.test.js`
- `cloud/meal-scan-proxy/test/fixtures/revenuecat/*.json`
- `docs/meal_scan_flash_lite_production_setup.md`
- `AppStoreReadinessChecklist.md`
- `.superpowers/sdd/task-3-report.md`

## Remaining Owner And External Gates

- Run and review the Apple IAP provisioner's dry-run metadata plan. Only if there are zero existing versions may the owner separately approve the one-time `v1` write.
- Supply the matching App Store IAP key ID and issuer ID through the live harness's hidden prompts.
- Confirm the RevenueCat v2 key has the required least-privilege read scopes; a permission failure blocks the canary.
- Freeze and explicitly approve the full source commit, then run the separately approved `seed` and post-buffer `rescan` windows on unlocked General Kenobi.
- If CycleBalance is initially present, complete and verify the explicit manual original-binary/data restore handoff after rescan.
- A passing development-signed canary still does not close the positive sandbox-JWS real-device TestFlight gate.
- The 80-image/120-call benchmark, signed distribution archive/export, production distribution profile, App Privacy/policy review, localization, screenshots, reviewer access, TestFlight, and publication approval remain open.

## Safety Notes

- No third Release feature override was added; canonical scanner flags remain `NO`.
- No client model selection, direct Gemini route, mock path, or release bypass was introduced.
- No raw canary UUID, App Check token, JWS, transaction identifier, purchase principal, photo, meal content, API key, bearer header, or raw log is retained in evidence.
- The negative invalid-JWS physical probe remains separate and unchanged.
