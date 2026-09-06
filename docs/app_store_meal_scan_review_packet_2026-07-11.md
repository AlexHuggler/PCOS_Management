# CycleBalance Meal Scan App Review Packet

Date: 2026-07-13

Status: staged local preparation for `1.0.5 (18)`. Build `18` was verified unused before this local version bump; it has not been archived, uploaded, distributed through TestFlight, or submitted. The owner approved the feature direction, per-upload Google Gemini confirmation, cache/expiry policy, model selection, and limited Gemini funding. The physical production App Attest probe is complete, but the App Store distribution profile, benchmark, App Privacy, RevenueCat, localized-policy review, and final screenshot gates below remain incomplete. The current production service is private and disabled; Release keeps Photo Estimate hidden rather than advertising an unavailable feature.

## Submission Gates

- Use local target `1.0.5 (18)`. Build `18` was verified unused, but this packet does not authorize an archive upload, TestFlight distribution, App Store Connect mutation, or submission.
- [x] Complete the physical App Attest side-effect probe. On `General Kenobi`, temporary revision `cyclebalance-meal-scan-proxy-00020-lqb` accepted one production limited-use App Check token and returned the expected non-entitled `403`. The isolated request gate advanced once, the billable probe quota remained absent, and no Gemini estimate event occurred. Labeled meal-photo quality review remains required before making the scanner available to App Review.
- Verify the production proxy remains App Check protected, entitlement gated, quota limited, budget controlled, and private/disabled outside the narrowly reviewed probe window.
- Live verification on July 13, 2026: rollback revision `cyclebalance-meal-scan-proxy-00021-gl2` serves 100% of traffic with `MEAL_SCAN_ENABLED=false`, a dedicated TTL-managed request-gate collection, and private IAM. An exact unauthenticated POST returns HTTP `403` at the IAM boundary; an authenticated POST returns `503 feature_disabled`.
- [x] Add an explicit pre-upload confirmation that names Google Gemini as the third-party AI processor. Returning from the camera or photo picker does not begin a fresh remote estimate until the user affirmatively continues; exact local reuse remains network-free.
- Use Google's standard paid-API disclosure: request content may be retained for up to 55 days. There is no verified project-specific Zero Data Retention approval or evidence that a ZDR request was submitted for `cyclebalance-prod-20260710`.
- Enter and verify the matching App Privacy answers before enabling the feature in a submitted build. The privacy, terms, and support pages are already live and current; support was published in commit `e119045`.
- Keep visual-similarity matching disabled until the private 100-image evaluation set passes the approved policy gate. Exact local repeat matching remains separate and available.
- Confirm App Review can exercise the intended photo-estimate path without an owner credential, private device access, or unshared test account. Otherwise keep the feature disabled and omit Photo Estimate from the review build, screenshots, and notes.
- [ ] Regenerate or verify the App Store distribution profile against the frozen archive. The embedded profile must include production App Attest and HealthKit entitlements with `get-task-allow=false`; the current profile evidence is not sufficient to clear this gate.
- [ ] Freeze and pass the 80-image paid benchmark and the separate similarity-policy evaluation. Until those gates pass, Release keeps the scanner UI, Gemini path, mock data, debug-direct path, fallback model, and visual similarity off.

## App Review Notes

Paste the following only for the approved build that enables photo estimates:

> CycleBalance is a PCOS-focused health and wellness tracker. No account or sign-in is required. Health logs and reviewed nutrition entries are stored locally on the user's device. HealthKit access is optional and read-only; users choose individual Apple Health permissions, and CycleBalance does not write to HealthKit.
>
> Photo Estimate is optional and user initiated. CycleBalance first checks on device whether the normalized photo exactly matches a previously reviewed meal. In that case, it offers to reuse the prior editable draft without sending the photo, consuming quota, or calling an AI model. The user can instead choose Scan as New. Before every fresh estimate, CycleBalance identifies Google Gemini as the third-party AI processor and asks the user to confirm the upload. After confirmation, CycleBalance sends one compressed JPEG through its secure meal-analysis service to Google Gemini to create an editable nutrition draft. The CycleBalance proxy does not retain raw uploaded image bytes. CycleBalance stores only nutrition the user reviews and saves in the local meal log, unless the user separately enables local saved-meal-photo retention in Settings.
>
> Fresh Photo Estimate access uses a verified StoreKit 2 transaction JWS. The proxy verifies the Apple transaction and current subscription state, then derives an HMAC-derived purchase principal from the verified original transaction identifier; it does not send or trust a RevenueCat App User ID as authorization evidence. RevenueCat remains the in-app paywall, purchase, and restore layer and must be checked separately before release.
>
> Paid access allows 10 fresh estimates per rolling 24 hours, with an immutable server maximum of 15 and an in-app warning at 2 remaining. Trial and sandbox access allows 5 fresh estimates per rolling 24 hours and 25 lifetime. Exact local or server cache hits do not consume AI quota. Monthly budget controls use a $15 alert, $20 degraded, and $25 disabled posture. Photo Estimate is an editable personal-tracking estimate, not medical advice, nutrition counseling, diagnosis, treatment, allergy guidance, or an exact measurement.
>
> Users can always choose manual meal entry and barcode lookup without photo analysis or AI quota. Barcode lookup is optional and user initiated; it sends only the UPC/EAN selected by the user to retrieve public product nutrition data.
>
> Review path: complete onboarding, open Track, choose Meals, then choose Photo Estimate under Add Nutrition. Select a meal photo, continue from the Google Gemini confirmation, edit any suggested items as needed, and save the reviewed meal. Settings > Subscription contains the purchase and restore controls. Settings > Apple Health contains optional read-only HealthKit permissions.

Do not use the following sentence unless project-specific Zero Data Retention approval is verified in the future:

> Google-approved Zero Data Retention removes user content and identifiable metadata before abuse-monitoring logs are written; CycleBalance does not use Gemini grounding, Files, explicit context caching, or stored interactions for meal estimates.

Use this sentence for the current standard paid-API posture and keep `Photos or Videos` disclosed in App Privacy:

> Google states that paid Gemini requests are not used to improve its products, but prompts, contextual information, and outputs may be retained for up to 55 days solely for abuse monitoring and required legal or regulatory disclosures.

## Reviewer Test Steps

1. Install the approved `1.0.5 (18)` archive only after its profile, benchmark, App Privacy, RevenueCat, localization, screenshot, and external approval gates are complete; complete onboarding without creating an account.
2. Open `Track` > `Meals` and confirm manual entry and `Scan barcode` remain available.
3. Choose `Photo Estimate`, select a non-sensitive test meal photo, and verify the app names Google Gemini and waits for explicit confirmation before sending it. Verify the live policy and App Review notes disclose that request content may be retained for up to 55 days.
4. Verify the estimate result is presented as an editable draft. Change an item or amount, then save it and confirm the reviewed nutrition appears in the local meal log.
5. Repeat the same locally reviewed photo and verify CycleBalance offers `Use Previous Meal` and `Scan as New`. Confirm either path still lands in an editable draft before saving. Do not test or describe visual-similarity matching; it remains disabled until the private 100-image evaluation passes.
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
| Usage Data > Product Interaction | App Functionality | Yes | No | Scan attempts, outcomes, quota tier, and cache behavior enforce rolling and lifetime limits and support reliability. |
| Other Data > Other Data Types | App Functionality | Yes | No | Optional UPC/EAN barcode lookup sends only the barcode chosen by the user to obtain product nutrition. |
| Purchases > Purchase History | App Functionality | Yes | No | Apple StoreKit establishes current purchase status; RevenueCat supports the in-app paywall, purchase, and restore experience. |

The live privacy policy and terms must state all of the following before submission:

- A meal photo is uploaded only after the user selects it and requests a photo estimate.
- The pre-upload confirmation identifies Google Gemini as the third-party AI processor and states the verified provider-retention posture.
- Processing is limited to creating the requested meal estimate; the proxy does not retain raw uploaded image bytes. Do not imply that Google retains nothing unless ZDR approval has been verified for the production project.
- An exact match to a previously reviewed meal can be reused on device without sending the photo again; `Scan as New` remains available.
- Nutrition remains local unless the user reviews and saves it; saved-meal-photo retention is local and separately controlled in Settings.
- Active trial/subscription checks use verified StoreKit evidence and the HMAC-derived principal. Paid users receive 10 fresh estimates per rolling 24 hours with a hard maximum of 15; trial and sandbox users receive 5 per rolling 24 hours and 25 lifetime. Exact cache hits do not consume quota, and the app warns at 2 remaining.
- A pseudonymous structured estimate may be held in the 24-hour structured-result cache. The StoreKit JWS, raw original transaction identifier, estimate, and meal name are excluded from application logs, and service HTTP request logs are excluded from the default log bucket.
- Monthly budget handling is alert at `$15`, degraded at `$20`, and disabled at `$25`; unavailable budget state fails closed.
- Google may retain paid Gemini request content for up to 55 days for abuse monitoring under the current non-ZDR posture.
- Manual meal entry and barcode lookup are available alternatives that do not require photo analysis or consume AI quota.
- The result is an editable personal-tracking estimate, not medical advice or a diagnosis.

## Screenshot Checklist

- [x] Capture the enabled meal entry screen with `Photo Estimate`, `Scan barcode`, and manual entry visible; local non-private implementation evidence is in `Artifacts/lunar-calm-add-nutrition.png`.
- [x] Capture the pre-send privacy notice explaining user-initiated upload and local reviewed-nutrition storage; local implementation evidence is in `Artifacts/lunar-calm-meal-scan-consent.png`.
- [x] Capture the explicit Google Gemini confirmation immediately before a fresh remote upload; local evidence in `Artifacts/lunar-calm-meal-scan-consent.png` names Google Gemini, shows manual/retake fallbacks, and discloses that request content may be retained for up to 55 days.
- [x] Capture the editable estimate review screen, including user-editable foods, `Add Food`, `Save Meal`, `Edit Portions`, and `Retake Photo`; local non-private evidence is in `Artifacts/lunar-calm-meal-estimate-review.png`.
- [x] Capture the exact-repeat suggestion in Botanical Journal and Lunar Calm at accessibility XXXL without real health data; local evidence is in `Artifacts/botanical-repeat-meal-standard-text.png` and `Artifacts/lunar-calm-repeat-meal-accessibility-xxxl-actions.png`.
- [ ] Capture the entitlement/fallback state showing barcode and manual alternatives; do not expose test identifiers or backend errors.
- [ ] Capture subscription and restore controls with the final localized legal-link layout.
- [ ] Refresh iPhone screenshot sizes and every shipped App Store localization as required by the new feature; retain no misleading coming-soon copy on an enabled screenshot set.
- [ ] Verify screenshots, App Privacy answers, policy text, reviewer notes, and the archived build all describe the same enabled/disabled state.

The existing consent and exact-repeat screenshots remain valid implementation evidence but are not App Store upload assets. Final assets must be recaptured from the same archived build submitted to review.

## Decisions And Remaining Owner Actions

- [x] Approve Photo Estimate as the intended review-candidate experience, with the server remaining disabled until every launch gate passes.
- [x] Use Google's standard paid-API disclosure that request content may be retained for up to 55 days. No project-specific ZDR approval or request submission has been verified.
- [x] Choose automatic 24-hour cache, 3-day daily-quota, and 30-day trial-total expiry for accountless v1. Local Delete All removes saved nutrition, retained local photos, and repeat-meal fingerprints immediately; the proxy stores no raw photo and has no durable CycleBalance account record to expose through a cloud deletion UI.
- [x] Deny all direct Firestore mobile/web access. Proxy quota, cache, and budget records are server-only through Cloud Run IAM.
- [x] Verify the privacy, terms, and support pages are live and current. Support was published in commit `e119045`.
- [x] Approve Gemini 3.1 Flash-Lite as the production candidate, `$25` Prepay with auto-reload off, and conservative launch quotas.
- [x] Complete the production physical App Attest side-effect probe against the isolated request-gate implementation and restore the initially absent app state on `General Kenobi`.
- [ ] Approve the final build number greater than `17` and target review train after quality, App Privacy, localized-policy, and screenshot evidence are complete.
- [x] Implement and run the targeted Nutrition5k acquirer. The three official source documents matched pinned SHA-256 values, and the owner-only evaluation directory retains exactly 40 depth-test RGB images plus per-image hash provenance (16 MB total), without the 181.4 GB archive or side-angle videos.
- [x] Implement and run the one-pass SNAPMe acquirer. The full 2,034,227,035-byte archive passed the pinned MD5 check, and the owner-only evaluation directory retains exactly 30 selected public images plus the source-index/provenance fragments (6.7 MB total), without the tarball or participant identifiers.
- [x] Implement the bounded MFDS acquisition helper with a hidden local key prompt, deterministic record selection, HTTPS host allowlisting, image size/type/dimension validation, owner-only output, and failure cleanup.
- [ ] Obtain a Food Safety Korea API key for at least ten distinct MFDS recipe records; the unauthenticated sample exposes only five fixed recipes. Enter it through the helper's local hidden prompt, never in chat, source, shell history, environment variables, or app configuration.
- [ ] Enter the approved App Privacy answers and updated reviewer notes in App Store Connect.
- [ ] Verify the production RevenueCat offering, monthly/annual packages, localized products, pricing, purchase, restore, and receipt synchronization against the exact candidate archive. RevenueCat is not the proxy authorization principal.
- [ ] Native-speaker/legal review the six localized drafts and verify all seven live locales. The pages are published, but this human review remains required before scanner enablement.
- [ ] Upload the approved screenshot set and submit only after the quality and App Store metadata gates pass.
