# Task 1 Backend Finalization Report

Date: 2026-07-13 (America/Chicago)
Scope: `cloud/meal-scan-proxy` only
Commit verified: `372f7bf522a256f457a3cdafbd0e7d69635f058c` (`feat: harden meal scan proxy contract`)
Base commit: `3230ee754571ec8f69cdb8673376a68f9e7c3d43`

## Outcome

DONE WITH CONCERNS. The committed backend scope is green under fresh focused and full tests, has no high-severity npm audit findings, and retains private/disabled deployment defaults. No backend repair or follow-up commit was necessary. The main maintainability concern is the 2,258-line `src/server.js`; Docker verification was unavailable locally.

## TDD Evidence

Inherited evidence from the implementing agent (not independently re-created during finalization):

- RED: the focused Task 1 run failed 21 of 22 tests before implementation.
- GREEN: the implementing agent reported the focused run at 22/22 and the full proxy run at 94/94.

Fresh finalizer evidence on committed HEAD:

- Focused Task 1 command: `node --test --test-name-pattern='expired verified StoreKit|forged, expired, revoked|namespaces the HMAC|raw RevenueCat identifier|rolling quota expires|above the absolute startup maximum|server cache hit does not consume|one requestId permits|ambiguous provider timeout|canonical request hash|public model selection and always|public JSON body cap|decoded, pixel, and canonicalized|structured output and rejects|monthly spend at the exact' test/proxy.test.js`
  - Result: 22 passed, 0 failed, 0 skipped; exit 0.
- Full command: `npm test`
  - Result: 93 passed, 0 failed, 0 skipped; exit 0.
  - The fresh runner reports 93 tests, not the inherited 94; there is no failure or skip in the committed suite, but the count discrepancy is recorded rather than normalized away.

## Fresh Verification

- `npm audit --audit-level=high`: exit 0; `found 0 vulnerabilities`.
- `bash -n` on all changed shell scripts (`bootstrap-gcp.sh`, `deploy-cloud-run.sh`, `deploy-firestore-rules.sh`, `run-physical-app-check-probe.sh`): exit 0, no diagnostics.
- `git diff --check 3230ee754571ec8f69cdb8673376a68f9e7c3d43..HEAD -- cloud/meal-scan-proxy`: exit 0, no diagnostics.
- Backend working tree and index: clean; no staged backend files.
- Commit scope: all 14 committed paths are under `cloud/meal-scan-proxy`.
- Secret-pattern scan across the backend commit found no Google API keys, private-key blocks, Stripe/GitHub/Slack/AWS tokens, or JWT-shaped credentials.
- Docker: `command -v docker` exited 1, so the optional build/runtime smoke was skipped immediately as requested.

## Security Boundary Review

- `scripts/deploy-cloud-run.sh` defaults `MEAL_SCAN_ENABLED=false` and `ALLOW_UNAUTHENTICATED=false`.
- The private default selects both `--no-allow-unauthenticated` and `--invoker-iam-check`, then verifies anonymous requests receive Cloud Run 403/404 before reporting success.
- Deploy-time Gemini and principal-HMAC secrets require reviewed numeric versions; `latest` is not accepted.
- `.gcloudignore` excludes environment files, key/certificate containers, secret-named paths, and local secrets configuration.
- Backend logs contain event names, bounded cost/quota metrics, and sanitized error codes; request IDs, purchase principals, StoreKit JWS values, meal content, images, and secret values are not logged.
- Firestore client rules are deny-all, and deployment verifies those rules before deploying Cloud Run.

## Changed Files

- `.gcloudignore`
- `README.md`
- `firestore.rules`
- `package-lock.json`
- `package.json`
- `scripts/bootstrap-gcp.sh`
- `scripts/deploy-cloud-run.sh`
- `scripts/deploy-firestore-rules.sh`
- `scripts/estimate-usage-cost.mjs`
- `scripts/run-physical-app-check-probe.sh`
- `src/server.js`
- `test/firestore-rules-deploy.test.js`
- `test/physical-probe-script.test.js`
- `test/proxy.test.js`

## Concerns And Self-Review

- Maintainability: `src/server.js` is 2,258 lines and changed by +1,506/-478 lines. It now combines HTTP orchestration, StoreKit verification, image canonicalization, quota/idempotency/cache stores, budget controls, App Check, and provider integration. A later behavior-preserving decomposition should separate these responsibilities, but doing that during security finalization would add avoidable risk.
- Verification gap: Docker was unavailable, so the container image and production start path were not exercised here.
- Evidence discrepancy: the inherited full-suite count was 94/94 while the fresh committed suite is 93/93. There are zero failures/skips, but future history review may want to identify the removed or reclassified test.
- Scope discipline: no files outside the requested report were edited during finalization, no unrelated dirty-tree changes were staged, and no backend changes were added after the existing scope-only commit.

---

## Post-Review Backend Repair (2026-07-13)

This section supersedes the earlier “no backend repair” outcome. A fresh adversarial review found production gaps after `372f7bf`; they were repaired with strict RED-to-GREEN cycles in the meal-scan proxy and budget controller. No Google Cloud, Apple, deployment, billing, or other external state was mutated.

### Repaired Findings

- Made Firestore `spendUsd` authoritative against deployment-pinned `$15/$20/$25` thresholds, retained the most restrictive billing/manual mode, and failed closed on missing spend, invalid modes, or invalid threshold ordering. Updated the budget-controller defaults to the same thresholds.
- Moved cache expiry deletion into a Firestore transaction so a stale reader cannot delete a concurrently refreshed result. Budget-disabled mode still serves valid free cache hits.
- Replaced obsolete bootstrap inputs with the principal-HMAC and App Store API key secrets, made multiline `.p8` ingestion file-based, and enabled TTL for every active server collection.
- Bundled Apple’s three official DER trust roots with SHA-256 provenance, removed runtime trust-root override behavior, built the real `SignedDataVerifier`, separated Production/Sandbox, classified retryable certificate/network failures, and added a current App Store Server API status lookup.
- Bound current status to the submitted original transaction, environment, bundle, and product; current status tier now controls quota. Enabled production is pinned to `alex.PCOS`, Apple ID `6760353511`, and the exact monthly/annual products.
- Added a verified-HMAC-principal attempt ledger capped at 3/minute and 30/rolling-24-hours, separate from the coarser pre-verification abuse shield.
- Made idempotency, principal rolling quota, a 60/minute plus 1,000/rolling-24-hour durable global provider allowance, and a one-provider-call-per-principal lease one Firestore transaction. Global/lease denials do not debit principal quota; cache hits bypass the reservation; completion, unknown, failure, and expiry release the principal lease.
- Corrected trial lifetime responses, degraded-mode paid/trial restrictions, raw-gate-before-Sharp ordering, explicit public activation command, and the README contract.

### RED-to-GREEN Evidence

- Budget authority and cache race: 0/2 RED, then 2/2 GREEN.
- Disabled/degraded/trial/order controls: 0/5 RED, then 7/7 combined GREEN.
- Budget-controller production defaults: 0/1 RED, then 1/1 GREEN.
- Bootstrap and activation contracts: 0/2 RED, then 2/2 GREEN.
- Real Apple roots, retry classification, and current-status replay defense: 0/6 RED, then 6/6 GREEN.
- Atomic Firestore quota/idempotency adapters and server path: 0/3 RED across the focused cycles, then 3/3 GREEN.
- Current product binding, authoritative current tier, and missing-spend fail-closed behavior: 0/3 RED, then 3/3 GREEN.
- Verified-principal attempts, global dispatch concurrency/rollover, principal lease lifecycle, server denial mapping, Apple pinning, and deploy contract: 0/9 RED, then 9/9 GREEN.
- Additional fail-closed mode/threshold checks, multiline Apple-key bootstrap, and immutable bundled roots each reproduced RED before their focused GREEN run.

### Fresh Final Verification

- Meal-scan proxy `npm test`: 131 passed, 0 failed, 0 skipped; exit 0.
- Meal-scan proxy `npm audit --audit-level=high`: `found 0 vulnerabilities`; exit 0.
- Budget controller `npm test`: 6 passed, 0 failed, 0 skipped; exit 0.
- Budget controller `npm audit --audit-level=high`: `found 0 vulnerabilities`; exit 0.
- `node --check` on both changed runtime modules: exit 0.
- `bash -n` on both changed setup/deploy scripts: exit 0.
- `git diff --check`: exit 0.
- `npm pack --dry-run --json`: exit 0 and includes all three bundled Apple roots plus their provenance README.
- Decoded Apple-root SHA-256 values match the recorded provenance: `b0b1730e...f024`, `c2b9b042...a050`, and `63343abf...9179`.
- Focused secret-pattern scan found no API keys, private-key blocks, access tokens, or JWT-shaped credentials.

### Remaining Concern

`src/server.js` is now 3,108 lines and should later be decomposed behind behavior-preserving tests. Docker remains unavailable locally, so container execution was not re-run; package composition and runtime syntax were verified instead.

### Adversarial Re-review Closure

A final read-only review found three additional gaps, all fixed before commit:

- The Cloud Run image now copies `certs/`, with a deployment-contract regression test proving the startup trust anchors are present in the image definition.
- A cache observer can no longer overwrite a same-hash pending/unknown idempotency record or strand the owning provider lease. The adapter preserves claim ownership, and the HTTP path returns pending/unknown `409` responses instead of false success.
- Every bundled Apple root is now pinned at runtime to its exact DER SHA-256 value; a parseable certificate substituted under an expected filename is rejected.

Focused RED: 0 passed, 4 failed. Focused GREEN: 4 passed, 0 failed. The final meal-scan proxy suite then passed 135/135, both npm audits again found 0 vulnerabilities, controller tests passed 6/6, runtime and shell syntax checks passed, `git diff --check` passed, and both the package dry run and `gcloud meta list-files-for-upload` included all three trust anchors. Docker is not installed locally, so the static image contract plus source-manifest/package/runtime checks are the available container evidence. `src/server.js` is 3,133 lines after these repairs.
