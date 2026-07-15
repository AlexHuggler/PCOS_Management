# CycleBalance Meal Scan Security Best-Practices Review

Date: 2026-07-12

> **Historical snapshot — superseded.** This review predates the signed scanner-gate and StoreKit authorization hardening in RC commits `d865640`, `f5f2162`, and `5f6bc55`. It is retained as implementation history, not current release evidence. Use `AppStoreReadinessChecklist.md`, the current source, and the current verification suites as the release source of truth; any findings or live-service details below require revalidation before relying on them.

## Executive Summary

This targeted review covers the production meal-scan proxy, Gemini secret handoff, Cloud Run deployment defaults, and the public quality-evaluation toolkit. No validated Critical or High severity issue was found in this scope. One known Medium trust gap remains for limited production: a RevenueCat anonymous App User ID is not cryptographically bound to the App Attest installation that submits it.

This is a focused security-best-practices review, not a completed exhaustive Codex Security repository scan. The separate Codex Security setup did not enter its scan phase, so this report does not claim repository-wide coverage.

## Medium

### SEC-001: Entitlement identifier is not bound to the verified app installation

- Location: `cloud/meal-scan-proxy/src/server.js:96`, `cloud/meal-scan-proxy/src/server.js:163`, `cloud/meal-scan-proxy/src/server.js:185`, `cloud/meal-scan-proxy/src/server.js:667`
- Evidence: Firebase App Check verifies that a request came from a valid app installation, then the proxy trusts the separately submitted `revenueCatAppUserId` for request limits, entitlement lookup, quota, and cache identity.
- Impact: a paid anonymous RevenueCat ID copied to another valid CycleBalance installation could share the original subscriber's scanner entitlement and quota. App Check prevents generic scripts and modified clients from directly reaching this path, but it does not prove that the RevenueCat ID belongs to the attested installation.
- Current mitigation: limited-use App Check token consumption, 30/minute and 200/day per-ID request gates, 300/minute and 3,000/day global pre-entitlement gates, 10/day paid scan cap, 25-total trial cap, a `$120` service kill switch, and private/disabled production posture until release gates close.
- Required hardening before materially broader rollout: verify signed StoreKit transaction JWS server-side, or bind entitlement access to a stable direct App Attest installation identity and reject cross-install ID reuse.

## Implemented Controls

- Production-enabled startup fails closed unless App Check, Firestore quota/cache/request/budget stores, RevenueCat, Gemini, and bounded numeric limits are configured.
- Gemini and RevenueCat server credentials are Secret Manager references, not app configuration or plaintext Cloud Run environment values. The active Gemini key is API-restricted and has no user-managed service-account key.
- Gemini authorization is sent in the `x-goog-api-key` header, never the URL. Provider errors are generic and do not echo the key or raw response.
- The paid evaluation uses fixed `execFile` argument arrays, a pinned project/service/region/secret/model, exact confirmation text, a private/disabled Cloud Run read-back, and a fixed maximum of 120 sequential calls.
- Source and normalized evaluation images must be regular non-symlink files confined to declared owner-controlled roots. All 80 images and hashes are validated before the first paid call.
- Benchmark outputs exclude source paths, raw provider responses, provider errors, and the API key. Files are mode `0600` and use atomic no-overwrite publication.
- The MFDS acquirer accepts its API key only through a hidden prompt, keeps key-bearing URLs out of output and errors, allowlists API/image hosts, bounds responses and image dimensions, and removes partial output on failure.
- The Nutrition5k acquirer pins the official split/metadata digests, allowlists the public bucket host, bounds and validates each PNG, records per-image hashes, and downloads only the selected test slice.
- The proxy does not persist raw images. Firestore mobile/web rules deny all direct access to server-owned quota, cache, and budget records.

## Residual Notes

- The local benchmark's path checks and later file opens are separate filesystem operations. A malicious local process with write access to the private benchmark directories could attempt a time-of-check/time-of-use swap. Hash validation prevents unnoticed normalized-image substitution before paid calls, and generated bundle directories are mode `0700`; keep source datasets in an owner-controlled directory as documented.
- Google Zero Data Retention remains an external privacy gate, not a confirmed control. Until exact-project approval is verified, production photo uploads remain disabled and disclosures must use the standard provider-retention posture.

## Verification

- Proxy tests: 59 passed.
- Quality toolkit tests: 35 Node tests and 17 Python acquisition tests passed after hardening.
- Production dependency audit: `npm audit --omit=dev` reported zero vulnerabilities.
- Live read-back: revision `cyclebalance-meal-scan-proxy-00008-x4v`, `MEAL_SCAN_ENABLED=false`, no public invoker binding.
