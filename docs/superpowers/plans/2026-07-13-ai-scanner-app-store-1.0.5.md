# CycleBalance AI Scanner And App Store 1.0.5 Implementation Plan

> **Historical implementation plan.** This document preserves the original task sequence and its unchecked boxes; it is not the current gate tracker. Use `AppStoreReadinessChecklist.md`, current source, and fresh verification results as the release source of truth.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a fail-closed, server-metered CycleBalance AI meal scanner in a verified `1.0.5` release candidate without enabling production inference, distributing TestFlight, or submitting to App Review before the owner approval gates.

**Architecture:** The iOS app obtains a limited-use Firebase App Check token and verified StoreKit transaction JWS, normalizes a meal photo, and calls a Cloud Run proxy. The proxy verifies App Check and Apple evidence, derives a pseudonymous purchase principal, enforces rolling quotas, idempotency, request/cost gates, canonical image validation, and a pinned Gemini model before inference. Barcode lookup and manual entry remain independent and available.

**Tech Stack:** SwiftUI, StoreKit 2, Swift Testing, Firebase App Check/App Attest, Node.js 20, Firestore, Cloud Run, Secret Manager, Apple App Store Server Library, Gemini structured output.

## Global Constraints

- Preserve unrelated dirty-worktree changes and never reset or overwrite them.
- Keep Cloud Run private and `MEAL_SCAN_ENABLED=false` during implementation and benchmark execution.
- Never ship Gemini, RevenueCat secret, Food Safety Korea, or USDA credentials in the app or repository.
- Pin production inference to `gemini-3.1-flash-lite`; clients cannot select a model.
- Paid allowance is 10 fresh provider dispatches per rolling 24 hours, warning after 8, with startup rejection above 15.
- Trial and sandbox allowance is 5 per rolling 24 hours and 25 lifetime.
- Exact local/server cache hits, barcode lookup, and manual entry do not consume AI quota.
- Monthly controls are alert at $15, degraded at $20, and disabled at $25; unavailable budget state fails closed.
- Production UI never substitutes mock nutrition after a remote failure.
- Release target is `1.0.5` build `18`, or the next unused build discovered before upload.
- Cloud enablement/public invoker, TestFlight distribution, and App Review submission require separate owner approval.

---

### Task 1: Harden The Cloud Proxy Contract And Security Boundary

**Files:**
- Modify: `cloud/meal-scan-proxy/test/proxy.test.js`
- Modify: `cloud/meal-scan-proxy/src/server.js`
- Modify: `cloud/meal-scan-proxy/package.json`
- Modify: `cloud/meal-scan-proxy/scripts/deploy-cloud-run.sh`

**Interfaces:**
- Request: `requestId`, `signedTransactionJWS`, meal metadata, and JPEG; `modelId` is rejected.
- Principal: HMAC of verified `originalTransactionId`, namespaced by Apple environment.
- Response quota: `tier`, `used`, `limit`, `remaining`, `windowSeconds`, `resetAt`, `retryAfterSeconds`.
- Idempotency: `pending`, `completed`, or `unknown`, bound to the canonical request hash.

- [ ] Add failing tests for forged/expired/revoked/wrong-app StoreKit JWS, sandbox separation, and raw RevenueCat-ID rejection.
- [ ] Add failing tests for exact rolling-window boundaries, startup limit above 15, cache-free quota, one in-flight request, durable ambiguous timeout, and idempotency body mismatch.
- [ ] Add failing tests for public `modelId` rejection, 2.2 MB body cap, decoded-image/pixel/canonical-size rejection, bounded output, and budget states `$15/$20/$25`.
- [ ] Run `npm test` and verify the new tests fail for missing behavior.
- [ ] Implement Apple verification, pseudonymous principal derivation, rolling Firestore ledger, idempotency ledger, fixed model, canonical image handling, schema bounds, cost modes, and identifier-free metrics.
- [ ] Pin deploy-time secret versions, anchor scripts to their directory, expand secret ignore patterns, and retain private/disabled defaults.
- [ ] Run `npm test` and `npm audit --audit-level=high` until both exit zero.

### Task 2: Make The iOS Scanner Fail Closed And Quota Aware

**Files:**
- Modify: `PCOS/PCOSTests/GeminiMealScanTests.swift`
- Modify: `PCOS/PCOSTests/MealScanViewModelTests.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`

**Interfaces:**
- `MealScanOutcome(result:quota:cacheDisposition:)` replaces result-only remote completion.
- `MealScanQuota` carries `tier`, `used`, `limit`, `remaining`, `windowSeconds`, `resetAt`, and `retryAfterSeconds`.
- The remote request carries `requestId` and verified StoreKit `jwsRepresentation`; it omits model selection and does not trust a RevenueCat ID as identity.

- [ ] Add failing tests for outcome decoding, StoreKit-evidence failure, local/server cache disposition, quota warnings/exhaustion, and production no-mock fallback.
- [ ] Run focused tests and confirm expected failures.
- [ ] Implement StoreKit evidence acquisition, the request/response types, typed error handling, explicit ambiguous-timeout behavior, and same-photo retry only when no paid dispatch occurred.
- [ ] Update the SwiftUI consent/status/error surfaces with the rolling allowance, remaining/reset copy, warning at two remaining, and barcode/manual fallbacks.
- [ ] Add an explicit encoded-image-size guard and keep Release USDA credentials unset.
- [ ] Run focused scanner, localization, interface, and persistence tests.

### Task 3: Make The Public Quality Gate Authoritative

**Files:**
- Modify: `tools/meal-scan-quality-evaluation/test/score-cli.test.mjs`
- Modify: `tools/meal-scan-quality-evaluation/src/evaluation.mjs`
- Modify: `tools/meal-scan-quality-evaluation/score.mjs`
- Modify: `tools/meal-scan-quality-evaluation/README.md`

- [ ] Add failing tests requiring exactly two repeats for each of the 20 locked holdouts, no non-holdouts, all structured successes, one model/prompt/schema/normalizer/source commit, and nonzero CLI status on any failed gate.
- [ ] Add a failing MFDS calorie-WAPE guard and qualitative-review gate schema requiring at least 72/80 acceptable results and zero severe results.
- [ ] Run `npm test` and verify the failures.
- [ ] Implement the validation/report/exit behavior and rerun all Node and Python evaluator tests.
- [ ] Obtain the Food Safety Korea key through the helper's hidden prompt, acquire 10 MFDS records, freeze the 80-image manifest, and run exactly 120 paid benchmark calls while the customer endpoint remains private/disabled.
- [ ] Keep the scanner hidden if any numerical, stability, provenance, or qualitative gate fails.

### Task 4: Prepare The 1.0.5 Release Candidate

**Files:**
- Modify: `project.yml`
- Modify: `PCOS/PCOS/PrivacyInfo.xcprivacy`
- Modify: `PCOS/PCOSTests/PrivacyManifestTests.swift`
- Modify: `AppStoreReadinessChecklist.md`
- Modify: `docs/app_store_meal_scan_review_packet_2026-07-11.md`

- [ ] Add failing tests for `1.0.5 (18)`, secure Release flags, no Release USDA key, required privacy data categories, and no tracking.
- [ ] Update version/build, Release flags, privacy manifest, seven-localization store copy packet, retention/quota/reviewer notes, and RevenueCat verification checklist.
- [ ] Regenerate with XcodeGen and run the App Store configuration, privacy, localization, interface, scanner, and billing tests.
- [ ] Verify or regenerate the App Store profile so the exported app and profile contain production App Attest and HealthKit, with `get-task-allow=false`.
- [ ] Capture six `1290x2796` screenshots per localization from the exact candidate archive only after the binary is frozen.

### Task 5: Verify And Stop At External Approval Gates

- [ ] Run proxy, budget-controller, evaluator, focused iOS, and full relevant regression suites from clean commands.
- [ ] Complete dual-architecture Release build, archive/export, dSYM, privacy manifest, codesign/profile, credential scan, and Apple validation checks.
- [ ] Independently review the complete diff for security, spec compliance, regressions, and unrelated-file preservation.
- [ ] Verify Cloud Run remains private and disabled.
- [ ] Stop and request owner approval before public invoker/enablement, TestFlight distribution, or App Review submission.
