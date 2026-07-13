# CycleBalance Meal Scan App Review Packet

Date: 2026-07-13

Status: staged local preparation for `1.0.5 (18)`. Build `18` was verified unused before this local version bump; it has not been archived, uploaded, distributed through TestFlight, or submitted. The owner approved the feature direction, per-upload Google Gemini confirmation, standard 55-day disclosure, durable lifetime quota, model selection, and limited Gemini funding. The negative invalid-JWS physical production App Attest probe is complete, but it does not satisfy the positive sandbox-JWS real-device TestFlight gate, which remains open. The App Store distribution profile, benchmark, App Privacy, RevenueCat, localized-policy correction, and final screenshot gates below also remain incomplete. The production service is private and disabled; Release keeps Photo Estimate hidden until every gate passes.

## Submission Gates

- Use local target `1.0.5 (18)`. Build `18` was verified unused, but this packet does not authorize an archive upload, TestFlight distribution, App Store Connect mutation, or submission.
- Pass the positive sandbox-JWS real-device TestFlight gate and complete the exact 80-image/120-call quality benchmark before making the scanner available to App Review. The completed negative invalid-JWS probe does not satisfy that positive gate.
- Verify the production proxy remains App Check protected, entitlement gated, quota limited, budget controlled, and private/disabled outside the narrowly reviewed probe window.
- Add an explicit pre-upload confirmation that names Google Gemini as the third-party AI processor. Returning from the camera or photo picker must not begin a fresh remote estimate until the user affirmatively continues; exact local reuse must remain network-free.
- Keep Google's standard 55-day abuse-monitoring disclosure consistent in the app, privacy policy, App Privacy answers, and review notes. Do not claim Zero Data Retention unless the production project later receives verified approval and every surface is updated together.
- Update App Privacy before enabling the feature in a submitted build. The live privacy policy and terms already disclose Gemini, but their trial-total thirty-day language must be corrected to the durable lifetime ledger and read back from the deployed pages.
- Confirm App Review can exercise the intended photo-estimate path without an owner credential, private device access, or unshared test account. Otherwise do not submit an archive that exposes the feature.
- [ ] Regenerate or verify the App Store distribution profile against the frozen archive. The embedded profile must include production App Attest and HealthKit entitlements with `get-task-allow=false`; the current profile evidence is not sufficient to clear this gate.
- [ ] Freeze and pass the exact 80-image/120-call paid benchmark. Visual similarity remains out of scope and disabled for this release; it must not block exact local cache reuse or weaken the scanner benchmark.

## App Review Notes

Paste the following only for the approved build that enables photo estimates:

> CycleBalance is a PCOS-focused health and wellness tracker. No account or sign-in is required. Health logs and reviewed nutrition entries are stored locally on the user's device. HealthKit access is optional and read-only; users choose individual Apple Health permissions, and CycleBalance does not write to HealthKit.
>
> Photo Estimate is optional and user initiated. CycleBalance first checks on device whether the normalized photo exactly matches a previously reviewed meal. In that case, it offers to reuse the prior editable draft without sending the photo, consuming quota, or calling an AI model. The user can instead choose Scan as New. Before every fresh estimate, CycleBalance identifies Google Gemini as the third-party AI processor and asks the user to confirm the upload. After confirmation, CycleBalance sends one compressed JPEG through its secure meal-analysis service to Google Gemini to create an editable nutrition draft. The CycleBalance proxy does not retain raw uploaded image bytes. CycleBalance stores only nutrition the user reviews and saves in the local meal log, unless the user separately enables local saved-meal-photo retention in Settings.
>
> Fresh Photo Estimate access uses a verified StoreKit 2 transaction JWS. The proxy verifies the Apple transaction and current subscription state, derives an HMAC purchase principal from the verified original transaction identifier, and then asks RevenueCat API v2 to corroborate only that current Apple-verified transaction ID and environment. Apple remains authoritative for identity and tier. The proxy never trusts a RevenueCat App User ID and never sends the raw StoreKit JWS to RevenueCat.
>
> Paid access allows 10 fresh estimates per rolling 24 hours, with an immutable server maximum of 15 and an in-app warning at 2 remaining. Trial and sandbox access allows 5 fresh estimates per rolling 24 hours and 25 lifetime. Exact local or server cache hits do not consume AI quota. Monthly budget controls use a $15 alert; at $20 trial dispatches stop and paid access falls to 5 fresh estimates per rolling 24 hours; at $25 all fresh AI dispatches stop. Photo Estimate is an editable personal-tracking estimate, not medical advice, nutrition counseling, diagnosis, treatment, allergy guidance, or an exact measurement.
>
> Users can always choose manual meal entry and barcode lookup without photo analysis or AI quota. Barcode lookup is optional and user initiated; it sends only the UPC/EAN selected by the user to retrieve public product nutrition data.
>
> Review path: complete onboarding, open Track, choose Meals, then choose Photo Estimate. Select a meal photo, review the privacy notice, request an estimate, edit any suggested items as needed, and save the reviewed meal. Settings > Subscription contains the purchase and restore controls. Settings > Apple Health contains optional read-only HealthKit permissions.

Use this additional sentence only after Zero Data Retention is verified for the production project:

> Google-approved Zero Data Retention removes user content and identifiable metadata before abuse-monitoring logs are written; CycleBalance does not use Gemini grounding, Files, explicit context caching, or stored interactions for meal estimates.

If Zero Data Retention is not approved, use this sentence instead and keep `Photos or Videos` disclosed in App Privacy:

> Google states that paid Gemini requests are not used to improve its products, but prompts, contextual information, and outputs may be retained for up to 55 days solely for abuse monitoring and required legal or regulatory disclosures.

## Reviewer Test Steps

1. Install the approved `1.0.5 (18)` archive only after its profile, benchmark, App Privacy, RevenueCat, localization, screenshot, and external approval gates are complete; complete onboarding without creating an account.
2. Open `Track` > `Meals` and confirm manual entry and `Scan barcode` remain available.
3. Choose `Photo Estimate`, select a non-sensitive test meal photo, and verify the app names Google Gemini, describes the verified retention posture, and waits for explicit confirmation before sending it.
4. Verify the estimate result is presented as an editable draft. Change an item or amount, then save it and confirm the reviewed nutrition appears in the local meal log.
5. Repeat the same locally reviewed photo and verify CycleBalance offers `Use Previous Meal` and `Scan as New`. Confirm either path still lands in an editable draft before saving.
6. Return to the meal flow and confirm a user without an active trial or subscription receives the entitlement message for a fresh estimate and can still use barcode lookup or manual entry.
7. Open `Settings` > `Subscription` to review purchase/restore controls; do not require a private CycleBalance login.
8. Open `Settings` > `Apple Health` and verify HealthKit access is optional and read-only.

## App Privacy And Policy Delta

Update App Store Connect App Privacy for the approved cloud-photo build:

| Data type | Purpose | Linked to user | Used for tracking | Required disclosure |
| --- | --- | --- | --- | --- |
| User Content > Photos or Videos | App Functionality | Yes | No | For a fresh user-confirmed estimate, one normalized JPEG is transmitted through the CycleBalance proxy to Google Gemini for an editable draft. Exact on-device reuse avoids transmission. The proxy does not retain raw bytes; under the current provider posture, Google may retain request content for up to 55 days for abuse monitoring. |
| Health & Fitness > Health | App Functionality | Yes | No | Structured meal nutrition is associated with the requested estimate and may be held in the 24-hour structured-result cache. Saved nutrition and HealthKit health records remain on device. |
| Health & Fitness > Fitness | App Functionality | Yes | No | Optional Apple Health fitness context supports on-device insights. It is declared conservatively for App Functionality; the meal-scan proxy is not sent Fitness records. |
| Identifiers > User ID | App Functionality | Yes | No | The server derives a stable HMAC-derived purchase principal from Apple's verified original transaction identifier. The raw identifier and StoreKit JWS are not used as stored application identifiers. |
| Usage Data > Product Interaction | App Functionality | Yes | No | Scan attempts, outcomes, quota tier, and cache behavior enforce rolling and lifetime limits and support reliability. The HMAC-keyed trial/sandbox lifetime counter remains durable so the 25-lifetime maximum cannot reset. |
| Other Data > Other Data Types | App Functionality | Yes | No | Optional UPC/EAN barcode lookup sends only the barcode chosen by the user to obtain product nutrition. |
| Purchases > Purchase History | App Functionality | Yes | No | Apple StoreKit establishes current purchase status and the HMAC quota principal; RevenueCat supports purchase/restore and secondarily corroborates the current Apple-verified transaction. |

The live privacy policy and terms must state all of the following before submission:

- A meal photo is uploaded only after the user selects it and requests a photo estimate.
- The pre-upload confirmation identifies Google Gemini as the third-party AI processor and states the verified provider-retention posture.
- Processing is limited to creating the requested meal estimate; the proxy does not retain raw uploaded image bytes. Do not imply that Google retains nothing unless ZDR approval has been verified for the production project.
- An exact match to a previously reviewed meal can be reused on device without sending the photo again; `Scan as New` remains available.
- Nutrition remains local unless the user reviews and saves it; saved-meal-photo retention is local and separately controlled in Settings.
- Active trial/subscription checks use verified StoreKit evidence and the HMAC-derived principal. Paid users receive 10 fresh estimates per rolling 24 hours with a hard maximum of 15; trial and sandbox users receive 5 per rolling 24 hours and 25 lifetime. Exact cache hits do not consume quota, and the app warns at 2 remaining. Trial/sandbox lifetime counters are retained under the HMAC principal so the lifetime maximum cannot reset; rolling-only paid records expire after their short cleanup window.
- A pseudonymous structured estimate may be held in the 24-hour structured-result cache. The StoreKit JWS, raw original transaction identifier, request ID, image hash, estimate, and meal name are excluded from application logs, and service HTTP request logs are excluded from the default log bucket.
- Monthly budget handling is alert at `$15`, degraded at `$20`, and disabled at `$25`; unavailable budget state fails closed.
- Google may retain paid Gemini request content for up to 55 days for abuse monitoring under the current non-ZDR posture.
- Manual meal entry and barcode lookup are available alternatives that do not require photo analysis or consume AI quota.
- The result is an editable personal-tracking estimate, not medical advice or a diagnosis.

## Screenshot Checklist

- [ ] Capture exactly six clean `1290 x 2796` screenshots per store localization from the submitted archive: Add Nutrition with photo/barcode/manual choices; Google Gemini consent; editable estimate; quota/fallback with barcode/manual alternatives; paywall/restore; and core cycle/health tracking. Never show real health data, private identifiers, raw backend errors, or a real person's unredacted photo.
- [ ] Keep the existing repeat-meal images only as implementation evidence; they are not submission screenshots.
- [ ] Verify screenshots, App Privacy answers, policy text, reviewer notes, and the archived build all describe the same enabled/disabled state.

## Owner Actions Pending Approval

- [x] Use `1.0.5 (18)` unless App Store Connect later reports that build `18` has become unavailable.
- [x] Prepare Photo Estimate for the review candidate, but keep it hidden and the cloud disabled until every benchmark, security, profile, archive, and approval gate passes.
- [x] Use Google's standard 55-day abuse-monitoring disclosure; do not claim unverified ZDR.
- [x] Preserve the 24-hour result cache and durable HMAC-keyed trial/sandbox lifetime ledger required to enforce the 25-lifetime maximum.
- [ ] Enter the approved App Privacy answers and updated reviewer notes in App Store Connect.
- [ ] Verify the production RevenueCat offering, monthly/annual packages, localized products, pricing, purchase, restore, receipt synchronization, API v2 project/entitlement/product mappings, and the least-privilege `customer_information:subscriptions:read` secret against the exact candidate archive. RevenueCat remains secondary; it is not the quota principal or tier authority.
- [ ] Publish and verify the live privacy-policy and terms changes.
- [ ] Upload the approved screenshot set and submit only after the physical-device and quality gates pass.
