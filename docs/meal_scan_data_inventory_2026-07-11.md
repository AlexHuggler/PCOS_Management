# CycleBalance Meal Scan Data Inventory

Date: 2026-07-11

Status: production-readiness evidence. The public scanner remains disabled. Reconcile this inventory against the exact archived build, live cloud configuration, provider terms, and App Store Connect answers before enabling Photo Estimate.

## Data Flow And Retention

| Data | Destination | Stored form | Retention | Purpose |
| --- | --- | --- | --- | --- |
| Selected meal photo | iOS app memory | Original `UIImage`, normalized JPEG, and SHA-256 while the flow is active | In memory until the flow releases it; a saved photo remains local only when the user enables saved-meal-photo retention | Local exact-repeat check and user-requested estimate |
| Exact-repeat fingerprint and reviewed draft | On-device SwiftData | Vision feature print, exact image hash, reviewed nutrition snapshot, source metadata, and timestamps; no raw image bytes | Until the source meal, repeat record, or all app data is deleted | Reuse a reviewed meal without network, quota, or model access |
| Fresh estimate request | Cloud Run process memory | Normalized JPEG, full image hash, meal type, locale, schema/prompt/model IDs, anonymous RevenueCat App User ID, and limited-use Firebase App Check token | Request lifetime only; raw bytes and raw App User ID are not written to Firestore or application logs | Integrity, entitlement, dedupe, quota, and model request |
| Daily quota record | Firestore `mealScanDailyQuota` | 16-character SHA-256 prefix of the anonymous App User ID, UTC day, used/rejected counts, and limits | `expiresAt` is a Firestore-compatible timestamp three days after the write | Enforce daily trial/paid limits and investigate abuse without an account |
| Trial-total record | Firestore `mealScanDailyQuota` | Same pseudonymous app-user hash plus trial usage/rejection counts | `expiresAt` is a Firestore-compatible timestamp thirty days after the write | Enforce the 25-scan trial total |
| Successful estimate cache | Firestore `mealScanEstimateCache` | Composite hashed key, pseudonymous app-user hash, 12-character image-hash prefix, model/schema/prompt IDs, structured estimate, usage, and quota snapshot; no JPEG | 24 hours, enforced by application expiry checks and Firestore TTL | Avoid repeat model calls and quota consumption for the same user/request |
| Application event | Cloud Logging `_Default` bucket | 12-character image-hash prefix, provider/model, token/cost, quota tier, budget mode, and cache-hit status; no app-user hash, meal name, estimate, or image | 30 days | Cost, reliability, quota, and cache operations |
| Cloud Run HTTP request metadata | Cloud Logging router | Excluded from the `_Default` sink for `cyclebalance-meal-scan-proxy`; application and audit logs remain | Not intentionally retained in `_Default`; verify the exclusion after every logging or project migration | Minimize IP, user-agent, and request metadata retention |
| Gemini request and response | Google Gemini paid service | Normalized JPEG, prompt metadata, and structured model output; no RevenueCat App User ID is included in the Gemini payload | Standard posture: up to 55 days for abuse monitoring. Approved project ZDR: user content and identifiable metadata are cleared before abuse-monitoring logs are written | Generate the editable nutrition estimate |
| RevenueCat entitlement request | RevenueCat API V2 | Anonymous App User ID and subscription/trial status; no meal photo, nutrition, HealthKit, symptom, or journal content | Per RevenueCat and Apple purchase-service policies | Confirm trial or paid feature access |
| Reviewed meal | On-device SwiftData | User-reviewed foods, portions, macros, confidence, warnings, provenance, and optionally a locally retained photo | Until the user deletes the meal or all local app data | Meal history and planning |

Firestore verification on 2026-07-11 found zero documents in both production meal-scan collections, so no pre-fix quota records required migration or deletion.

## Current Minimization Controls

- The iOS app never contains a Gemini or RevenueCat server secret.
- The proxy validates the image hash and accepts only bounded JPEG requests and allowlisted models.
- The proxy does not use Gemini Files, grounding, stored Interactions, Live session resumption, or explicit context caching.
- Exact local reuse does not request App Check, contact RevenueCat, consume quota, call Cloud Run, or call Gemini.
- Similar-image reuse remains disabled until its private 100-image evaluation passes the approved precision and high-risk false-match gates.
- The Cloud Run service remains private and `MEAL_SCAN_ENABLED=false` outside a separately approved probe or rollout window.

## Preliminary App Privacy Mapping

Use the most conservative accurate mapping until production-project ZDR and the final archived behavior are verified:

| Apple data type | Purpose | Linked | Tracking | Basis |
| --- | --- | --- | --- | --- |
| User Content > Photos or Videos | App Functionality | No | No | Standard Gemini abuse monitoring retains fresh user-confirmed photo requests; the provider does not receive the RevenueCat App User ID |
| Health & Fitness > Health | App Functionality | Yes | No | Structured meal nutrition is cached for 24 hours under a stable pseudonymous app-user hash |
| Identifiers > User ID | App Functionality | Yes | No | Quota/cache records use a stable hash derived from the anonymous RevenueCat App User ID |
| Usage Data > Product Interaction | App Functionality | Yes | No | Scan usage, rejection counts, quota tier, and cache behavior support limits and reliability |
| Purchases > Purchase History | App Functionality | Follow the bundled RevenueCat privacy manifest | No | RevenueCat manages subscription and trial entitlement |
| Other Data > Other Data Types | App Functionality | No | No | Optional UPC/EAN lookup sends the user-selected barcode to a public nutrition database |

Apple defines collection based on off-device retention by the developer or a third-party partner. Reevaluate `Photos or Videos` only after Google ZDR is approved for the exact production project and the enabled build has been verified against Apple's current guidance.

## Open Decisions Before Enablement

- Obtain Google ZDR approval for `cyclebalance-prod-20260710`, or approve the standard 55-day abuse-monitoring disclosure.
- Add explicit fresh-upload permission naming Google Gemini; exact local reuse must bypass it.
- Decide whether automatic expiry is sufficient for pseudonymous server records or whether the enabled app must add a self-service cloud meal-scan deletion action.
- Update and publish the live privacy policy, terms, support FAQ, App Privacy answers, screenshots, and App Review notes only after they all describe the same verified retention posture.

## Authoritative References

- Apple App Privacy details: https://developer.apple.com/app-store/app-privacy-details/
- Apple App Review Guidelines 5.1.2: https://developer.apple.com/app-store/review/guidelines/
- Gemini paid-service abuse monitoring: https://ai.google.dev/gemini-api/docs/usage-policies
- Gemini Zero Data Retention: https://ai.google.dev/gemini-api/docs/zdr
