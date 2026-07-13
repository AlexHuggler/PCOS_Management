# CycleBalance Meal Scan Data Inventory

Date: 2026-07-11

Status: production-readiness evidence. The public scanner remains disabled. Reconcile this inventory against the exact archived build, live cloud configuration, provider terms, and App Store Connect answers before enabling Photo Estimate.

## Data Flow And Retention

| Data | Destination | Stored form | Retention | Purpose |
| --- | --- | --- | --- | --- |
| Selected meal photo | iOS app memory | Original `UIImage`, normalized JPEG, and SHA-256 while the flow is active | In memory until the flow releases it; a saved photo remains local only when the user enables saved-meal-photo retention | Local exact-repeat check and user-requested estimate |
| Exact-repeat fingerprint and reviewed draft | On-device SwiftData | Vision feature print, exact image hash, reviewed nutrition snapshot, source metadata, and timestamps; no raw image bytes | Until the source meal, repeat record, or all app data is deleted | Reuse a reviewed meal without network, quota, or model access |
| Fresh estimate request | Cloud Run process memory | Client JPEG, UUID request ID, StoreKit transaction JWS, meal type, locale, schema/prompt IDs, and limited-use Firebase App Check token; the image is decoded and re-encoded before hashing or provider use | Request lifetime only; raw JWS, raw transaction IDs, request IDs, and image bytes are not written to application logs | Integrity, Apple/RevenueCat authorization, idempotency, quota, canonicalization, cache, and model request |
| Rolling quota and lifetime ledger | Firestore `mealScanRollingQuota` | HMAC purchase principal with Apple production/sandbox namespace, dispatch timestamps, tier and limits, lifetime count, and a short provider-lease state | Rolling-only paid records receive a short cleanup TTL. Trial/sandbox records have no TTL timestamp so the 25-lifetime maximum cannot reset. | Enforce 10 paid or 5 trial/sandbox fresh dispatches per rolling 24 hours and 25 lifetime for trial/sandbox without an app account |
| Principal attempt record | Firestore `mealScanPrincipalAttempts` | HMAC purchase principal, bounded attempt timestamps, and limits | Three-day cleanup TTL | Enforce three attempts per minute and 30 per rolling 24 hours |
| Idempotency record | Firestore `mealScanIdempotency` | SHA-256 request-ID document key, canonical request hash, `pending`/`completed`/`unknown` state, and bounded response when completed; an active claim may temporarily reference the HMAC principal | Seven-day cleanup TTL | Prevent duplicate paid calls and preserve ambiguous provider outcomes |
| Successful estimate cache | Firestore `mealScanEstimateCache` | Composite hashed key, shortened HMAC-principal hash, 12-character canonical-image-hash prefix, model/schema/prompt IDs, structured estimate, usage, and quota snapshot; no JPEG | 24 hours, enforced by application expiry checks and Firestore TTL | Avoid repeat model calls and quota consumption for the same principal and canonical request |
| Application event | Cloud Logging `_Default` bucket | Identifier-free provider/model, token/cost, quota/cache decision, rejection reason, budget mode, status, and latency dimensions; no principal, request ID, transaction ID, image hash, meal name, estimate, or image | 30 days | Cost, reliability, quota, rejection, and cache operations |
| Cloud Run HTTP request metadata | Cloud Logging router | Excluded from the `_Default` sink for `cyclebalance-meal-scan-proxy`; application and audit logs remain | Not intentionally retained in `_Default`; verify the exclusion after every logging or project migration | Minimize IP, user-agent, and request metadata retention |
| Gemini request and response | Google Gemini paid service | Canonical JPEG, prompt metadata, and structured model output; no purchase principal, StoreKit evidence, or RevenueCat identifier is included in the Gemini payload | Standard posture: up to 55 days for abuse monitoring and required legal or regulatory disclosures | Generate the editable nutrition estimate |
| RevenueCat subscription corroboration | RevenueCat API V2 | Only the current Apple-verified transaction ID and environment are queried; no client App User ID, StoreKit JWS, meal photo, nutrition, HealthKit, symptom, or journal content | Per RevenueCat and Apple purchase-service policies | Secondarily corroborate the exact Apple-verified project, entitlement, product, environment, and transaction after Apple remains authoritative |
| Reviewed meal | On-device SwiftData | User-reviewed foods, portions, macros, confidence, warnings, provenance, and optionally a locally retained photo | Until the user deletes the meal or all local app data | Meal history and planning |

Firestore verification on 2026-07-11 found zero documents in both production meal-scan collections, so no pre-fix quota records required migration or deletion.

## Current Minimization Controls

- The iOS app never contains a Gemini or RevenueCat server secret.
- The proxy accepts no public model selector, decodes and re-encodes bounded images, strips metadata, rejects malformed/decompression-bomb inputs, and hashes only its canonical JPEG.
- The proxy does not use Gemini Files, grounding, stored Interactions, Live session resumption, or explicit context caching.
- Exact local reuse does not request App Check, contact RevenueCat, consume quota, call Cloud Run, or call Gemini.
- Similar-image reuse remains disabled until its private 100-image evaluation passes the approved precision and high-risk false-match gates.
- The Cloud Run service remains private and `MEAL_SCAN_ENABLED=false` outside a separately approved probe or rollout window.

## Preliminary App Privacy Mapping

Use the conservative standard-retention mapping until the final archived behavior and App Store Connect answers are verified:

| Apple data type | Purpose | Linked | Tracking | Basis |
| --- | --- | --- | --- | --- |
| User Content > Photos or Videos | App Functionality | Yes | No | Standard Gemini abuse monitoring may retain fresh user-confirmed photo requests; the request is associated with purpose-limited purchase/quota authorization inside CycleBalance's service |
| Health & Fitness > Health | App Functionality | Yes | No | Structured meal nutrition is cached for 24 hours under a stable pseudonymous app-user hash |
| Identifiers > User ID | App Functionality | Yes | No | Quota/cache records use an HMAC principal derived from Apple's verified original transaction ID and namespaced by environment |
| Usage Data > Product Interaction | App Functionality | Yes | No | Scan usage, rejection counts, quota tier, and cache behavior support limits and reliability |
| Purchases > Purchase History | App Functionality | Yes | No | Apple establishes current access and the HMAC principal; RevenueCat manages purchase/restore and secondarily corroborates the verified transaction |
| Other Data > Other Data Types | App Functionality | Yes | No | Optional UPC/EAN lookup sends the user-selected barcode to Open Food Facts |

Apple defines collection based on off-device retention by the developer or a third-party partner. Keep `Photos or Videos` declared for the enabled build under the selected standard Gemini retention posture.

## Open Decisions Before Enablement

- Keep the approved standard 55-day abuse-monitoring disclosure unless verified production-project ZDR is obtained later.
- Verify the implemented fresh-upload permission naming Google Gemini; exact local reuse must continue to bypass it.
- Correct the live legal pages' obsolete statement that trial-total records expire after thirty days; the lifetime ledger is durable by design.
- Update App Privacy, screenshots, and App Review notes only after they all describe the same verified enabled build.

## Authoritative References

- Apple App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines 5.1.2: https://developer.apple.com/app-store/review/guidelines/
- Gemini paid-service abuse monitoring: https://ai.google.dev/gemini-api/docs/usage-policies
- Gemini Zero Data Retention: https://ai.google.dev/gemini-api/docs/zdr
