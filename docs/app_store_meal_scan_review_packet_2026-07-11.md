# CycleBalance Meal Scan App Review Packet

Date: 2026-07-11

Status: preparation only. Do not upload a build, change App Store Connect metadata, or submit this packet without separate owner approval. This packet applies only when cloud photo estimates are deliberately enabled in a future review candidate; the currently submitted `1.0.4 (17)` release continues to present AI meal scanning as coming soon.

## Submission Gates

- Use a review candidate with a build number greater than `17`; do not alter `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` under this task.
- Complete the limited physical App Check probe and labeled meal-photo quality review before making the scanner available to App Review.
- Verify the production proxy remains App Check protected, entitlement gated, quota limited, budget controlled, and private/disabled outside the narrowly reviewed probe window.
- Add an explicit pre-upload confirmation that names Google Gemini as the third-party AI processor. Returning from the camera or photo picker must not begin a fresh remote estimate until the user affirmatively continues; exact local reuse must remain network-free.
- Choose and verify one provider-retention posture before enabling the feature: obtain Google approval for Zero Data Retention on `cyclebalance-prod-20260710`, or disclose Google's standard 55-day abuse-monitoring retention in the app, privacy policy, App Privacy answers, and review notes.
- Update App Privacy, the live privacy policy, and terms before enabling the feature in a submitted build. Verify the deployed public pages rather than relying on local website copy.
- Confirm App Review can exercise the intended photo-estimate path without an owner credential, private device access, or unshared test account. Otherwise keep the feature disabled for review and describe it as coming soon.

## App Review Notes

Paste the following only for the approved build that enables photo estimates:

> CycleBalance is a PCOS-focused health and wellness tracker. No account or sign-in is required. Health logs and reviewed nutrition entries are stored locally on the user's device. HealthKit access is optional and read-only; users choose individual Apple Health permissions, and CycleBalance does not write to HealthKit.
>
> Photo Estimate is optional and user initiated. CycleBalance first checks on device whether the normalized photo exactly matches a previously reviewed meal. In that case, it offers to reuse the prior editable draft without sending the photo, consuming quota, or calling an AI model. The user can instead choose Scan as New. Before every fresh estimate, CycleBalance identifies Google Gemini as the third-party AI processor and asks the user to confirm the upload. After confirmation, CycleBalance sends one compressed JPEG through its secure meal-analysis service to Google Gemini to create an editable nutrition draft. The CycleBalance proxy does not retain raw uploaded image bytes. CycleBalance stores only nutrition the user reviews and saves in the local meal log, unless the user separately enables local saved-meal-photo retention in Settings.
>
> Photo Estimate is controlled by app-integrity validation, active trial/subscription entitlement checks, daily and trial quotas, and a monthly budget stop. It is an estimate for personal tracking, not medical advice, nutrition counseling, diagnosis, treatment, allergy guidance, or an exact measurement. Users can review and edit every result before saving.
>
> Barcode lookup and manual meal entry remain available without photo analysis. Barcode lookup is optional and user initiated; it sends only the UPC/EAN selected by the user to retrieve public product nutrition data.
>
> Review path: complete onboarding, open Track, choose Meals, then choose Photo Estimate. Select a meal photo, review the privacy notice, request an estimate, edit any suggested items as needed, and save the reviewed meal. Settings > Subscription contains the purchase and restore controls. Settings > Apple Health contains optional read-only HealthKit permissions.

Use this additional sentence only after Zero Data Retention is verified for the production project:

> Google-approved Zero Data Retention removes user content and identifiable metadata before abuse-monitoring logs are written; CycleBalance does not use Gemini grounding, Files, explicit context caching, or stored interactions for meal estimates.

If Zero Data Retention is not approved, use this sentence instead and keep `Photos or Videos` disclosed in App Privacy:

> Google states that paid Gemini requests are not used to improve its products, but prompts, contextual information, and outputs may be retained for up to 55 days solely for abuse monitoring and required legal or regulatory disclosures.

## Reviewer Test Steps

1. Install the approved build with a build number greater than `17`; complete onboarding without creating an account.
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
| User Content > Photos or Videos | App Functionality | No | No | For a fresh user-confirmed estimate, one normalized JPEG is transmitted through the CycleBalance proxy to Google Gemini for an editable draft. An exact on-device repeat can be reused without transmission. The proxy does not retain raw bytes. Under the standard provider posture, Google may retain request content for up to 55 days for abuse monitoring; reevaluate whether this row remains required only after production-project ZDR is verified against Apple's current definition of collection. |
| Health & Fitness > Health | App Functionality | Yes | No | A successful structured meal-nutrition estimate is cached for 24 hours under a stable pseudonymous app-user hash so an identical request can be reused without another model call or quota charge. |
| Identifiers > User ID | App Functionality | Yes | No | Daily/trial quota and estimate-cache records use a stable one-way hash derived from the anonymous RevenueCat App User ID. The raw ID is not stored in CycleBalance Firestore or application logs. |
| Usage Data > Product Interaction | App Functionality | Yes | No | Scan usage, rejections, quota tier, and cache behavior enforce limits and support reliability. Daily records expire after three days; trial totals expire after thirty days. |
| Other Data > Other Data Types | App Functionality | No | No | Optional UPC/EAN barcode lookup continues to send only the barcode chosen by the user to obtain product nutrition. |
| Purchases > Purchase History | App Functionality | No | No | RevenueCat manages subscription/trial entitlement checks. |

The live privacy policy and terms must state all of the following before submission:

- A meal photo is uploaded only after the user selects it and requests a photo estimate.
- The pre-upload confirmation identifies Google Gemini as the third-party AI processor and states the verified provider-retention posture.
- Processing is limited to creating the requested meal estimate; the proxy does not retain raw uploaded image bytes. Do not imply that Google retains nothing unless ZDR approval has been verified for the production project.
- An exact match to a previously reviewed meal can be reused on device without sending the photo again; `Scan as New` remains available.
- Nutrition remains local unless the user reviews and saves it; saved-meal-photo retention is local and separately controlled in Settings.
- Active trial/subscription checks, daily/trial quotas, and a budget kill switch limit feature access.
- A pseudonymous structured estimate may be cached for 24 hours; daily quota records expire after three days and trial totals after thirty days. The app-user hash, estimate, and meal name are excluded from application logs, and service HTTP request logs are excluded from the default log bucket.
- Barcode lookup and manual entry are available alternatives that do not require photo analysis.
- The result is an editable personal-tracking estimate, not medical advice or a diagnosis.

## Screenshot Checklist

- [ ] Capture the enabled meal entry screen with `Photo Estimate`, `Scan barcode`, and manual entry visible; never show a real person's health data or an unredacted meal photo.
- [ ] Capture the pre-send privacy notice explaining user-initiated upload and local reviewed-nutrition storage.
- [ ] Capture the explicit Google Gemini confirmation immediately before a fresh remote upload; the screenshot must match the verified ZDR or 55-day retention posture.
- [ ] Capture the editable estimate review screen, including the user-editable items and save action.
- [x] Capture the exact-repeat suggestion in Botanical Journal and Lunar Calm at accessibility XXXL without real health data; local evidence is in `Artifacts/botanical-repeat-meal-standard-text.png` and `Artifacts/lunar-calm-repeat-meal-accessibility-xxxl-actions.png`.
- [ ] Capture the entitlement/fallback state showing barcode and manual alternatives; do not expose test identifiers or backend errors.
- [ ] Capture subscription and restore controls with the final localized legal-link layout.
- [ ] Refresh iPhone screenshot sizes and every shipped App Store localization as required by the new feature; retain no misleading coming-soon copy on an enabled screenshot set.
- [ ] Verify screenshots, App Privacy answers, policy text, reviewer notes, and the archived build all describe the same enabled/disabled state.

## Owner Actions Pending Approval

- [ ] Approve a build number greater than `17` and the target review train.
- [ ] Confirm whether Photo Estimate is enabled for the review candidate or remains coming soon.
- [ ] Approve the retention posture: verified Google ZDR for the production project, or the standard 55-day abuse-monitoring disclosure.
- [ ] Decide whether automatic 24-hour/3-day/30-day expiry is sufficient or whether the enabled app must include a self-service cloud meal-scan deletion action.
- [ ] Enter the approved App Privacy answers and updated reviewer notes in App Store Connect.
- [ ] Publish and verify the live privacy-policy and terms changes.
- [ ] Upload the approved screenshot set and submit only after the physical-device and quality gates pass.
