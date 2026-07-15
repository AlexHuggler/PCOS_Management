# Task 3 Positive General Kenobi Canary Report

Date: 2026-07-14 (America/Chicago)

Branch: `codex/cyclebalance-1.0.5-rc`

Implementation commit: `3e6cc191b59cc49661adef2fd6dd8027337e2fcf` (`feat: add approval-gated meal scan canary`)

## Outcome

IMPLEMENTED AND PREPARED; LIVE CANARY NOT RUN. The RC now contains a tested, executable positive-canary harness whose default path is non-mutating. It prepares an owner-driven development-signed Release canary for General Kenobi, separates owner observations from machine-read evidence, and guarantees a disabled/private rollback around each later live window. No Cloud Run deployment or IAM change, secret creation or rotation, device build/install, General Kenobi interaction, TestFlight distribution, or publication occurred during this task.

## TDD Evidence

- RED: `node --test test/positive-canary-script.test.js` initially reported 0 passed and 10 failed because the positive-canary script and its required runbook contract did not exist.
- Additional focused RED runs were captured as the contract expanded to require evidence-window ordering, separate seed/rescan windows, complete stdout/stderr prohibited-content scanning, and non-persistence of bearer tokens. Each new assertion failed before its corresponding implementation was added.
- GREEN: `node --test test/positive-canary-script.test.js` reports 12 passed, 0 failed; exit 0.
- The contract tests cover dry-run non-mutation, pinned production and device identities, live confirmation, unique General Kenobi resolution, Release override allowlisting, unchanged canonical flags, rollback-before-mutation ordering, final disabled/private verification, redaction and prohibited-log rules, exact-reuse/Scan-as-New arithmetic, bounded evidence windows, two-phase cache-expiry handling, and bearer-token non-persistence.

## Implementation Summary

- Added `cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`, executable mode `100755`.
- Default `DRY_RUN=true` prints the complete protocol and performs no cloud, device, build, installation, backup, secret, or publication operation.
- The live path requires the exact owner confirmation `I_APPROVE_GENERAL_KENOBI_POSITIVE_CANARY_WITH_TEMPORARY_PUBLIC_CLOUD_RUN` before live preflight and rejects identity overrides or ambiguous device resolution.
- Preflight pins the production project, service, endpoint, bundle, Firebase/Apple/RevenueCat identifiers, products, entitlement, branch, and General Kenobi UDID. Secret checks are metadata-only and never use `versions access`.
- The Release canary build permits only `MEAL_SCAN_RELEASE_UI_ENABLED=YES` and `MEAL_SCAN_RELEASE_GEMINI_ENABLED=YES`; mock data, debug-direct transport, fallback model, and visual-similarity paths remain disabled. Canonical `project.yml` flags are hashed before and after the build and must remain `NO`.
- Existing app data is backed up before installation with restrictive permissions. The resulting app must be development-signed, nondistributable, App Attest production-capable, and pinned to `alex.PCOS` and the production proxy URL.
- A rollback trap is installed before the live orchestration and armed before the first cloud mutation. Every exit path restores disabled/private service state and verifies anonymous rejection plus authenticated `503 feature_disabled`.
- The positive protocol is split into separately approved `seed` and `rescan` windows. Seed verifies one fresh scan and exact local reuse, then rolls back. Rescan runs only after more than 24 hours with the service disabled/private so `Scan as New` must be an uncached, exactly-one-provider dispatch.
- Machine evidence is content-free and bounded. The summary records safe counts/digests only, uses restrictive permissions, rejects prohibited content, removes raw logs, and never retains tokens, JWS values, transaction identifiers, meal names, photos, or bearer headers.
- Updated the production setup and App Store readiness runbooks with exact dry-run/live commands, owner-only Apple IAP provisioning handoff, two-window rollback requirements, and explicitly open release gates.

## Verification Results

- `bash -n cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`: exit 0.
- `node --test test/positive-canary-script.test.js`: 12 passed, 0 failed; exit 0.
- `npm test` in `cloud/meal-scan-proxy`: 197 passed, 0 failed, 0 skipped; exit 0.
- `DRY_RUN=true cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`: exit 0 and printed the complete non-mutating protocol.
- `git diff --check`: exit 0.
- Script mode check: `-rwxr-xr-x`; committed as `100755`.
- The implementation commit contains only the canary script, its test, and the two required documentation files. Concurrent SwiftUI work was not staged or committed by this task.

## Files Changed

- `cloud/meal-scan-proxy/scripts/run-positive-general-kenobi-canary.sh`
- `cloud/meal-scan-proxy/test/positive-canary-script.test.js`
- `docs/meal_scan_flash_lite_production_setup.md`
- `AppStoreReadinessChecklist.md`

## Owner And External Blockers

- `cyclebalance-app-store-iap-private-key` still needs the owner-controlled `.p8` provisioning handoff. The key value must remain hidden; the staged command has not been run.
- The matching App Store IAP key ID and issuer ID still need owner entry through the live harness's hidden prompts. They must not be written to chat, environment files, or retained evidence.
- The existing Gemini and RevenueCat secrets must not be re-prompted, rotated, or replaced. The principal-HMAC resource exists at pinned version `1`; no value was read during this task.
- Production Cloud Run has not been deployed with the final RC Apple/RevenueCat configuration, and the service was not enabled or made public by this task.
- General Kenobi has not been built for, installed to, backed up by, or exercised by this task. Both live windows require fresh explicit owner approval and physical control of an unlocked, paired, Developer-Mode/DDI-ready device.
- The seed and rescan phases require separate rollback-bounded invocations and more than 24 hours disabled/private between them. Neither has run.
- A passing development-signed canary still does not close the positive sandbox-JWS real-device TestFlight gate.
- The frozen 80-image/120-call benchmark remains open.
- The App Store distribution profile still must prove production App Attest and HealthKit with `get-task-allow=false`; signed archive/export inspection remains open.
- RevenueCat offering/entitlement/product verification, App Privacy and policy review, localization, final screenshots, reviewer access, TestFlight distribution, and publication approval remain open.

## Scope And Safety Notes

- No live secret values, credentials, tokens, JWS data, transaction identifiers, meal content, images, or bearer headers were exposed or persisted.
- No cloud, Apple, device, billing, TestFlight, or publication state was mutated.
- The negative invalid-JWS physical probe remains separate and unchanged; the positive harness does not weaken or repurpose it.
