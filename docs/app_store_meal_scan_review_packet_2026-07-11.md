# CycleBalance Meal Scan App Review Packet

Date: 2026-07-11

Status: preparation only. Do not upload a build, change App Store Connect metadata, or submit this packet without separate owner approval. This packet applies only when cloud photo estimates are deliberately enabled in a future review candidate; the currently submitted `1.0.4 (17)` release continues to present AI meal scanning as coming soon.

## Submission Gates

- Use a review candidate with a build number greater than `17`; do not alter `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` under this task.
- Complete the limited physical App Check probe and labeled meal-photo quality review before making the scanner available to App Review.
- Verify the production proxy remains App Check protected, entitlement gated, quota limited, budget controlled, and private/disabled outside the narrowly reviewed probe window.
- Update App Privacy, the live privacy policy, and terms before enabling the feature in a submitted build. Verify the deployed public pages rather than relying on local website copy.
- Confirm App Review can exercise the intended photo-estimate path without an owner credential, private device access, or unshared test account. Otherwise keep the feature disabled for review and describe it as coming soon.

## App Review Notes

Paste the following only for the approved build that enables photo estimates:

> CycleBalance is a PCOS-focused health and wellness tracker. No account or sign-in is required. Health logs and reviewed nutrition entries are stored locally on the user's device. HealthKit access is optional and read-only; users choose individual Apple Health permissions, and CycleBalance does not write to HealthKit.
>
> Photo Estimate is optional and user initiated. After the user chooses a meal photo and taps the estimate action, CycleBalance sends one compressed JPEG securely to the CycleBalance meal-analysis service to create an editable nutrition draft. The proxy does not retain raw uploaded image bytes. CycleBalance stores only nutrition the user reviews and saves in the local meal log, unless the user separately enables local saved-meal-photo retention in Settings.
>
> Photo Estimate is controlled by app-integrity validation, active trial/subscription entitlement checks, daily and trial quotas, and a monthly budget stop. It is an estimate for personal tracking, not medical advice, nutrition counseling, diagnosis, treatment, allergy guidance, or an exact measurement. Users can review and edit every result before saving.
>
> Barcode lookup and manual meal entry remain available without photo analysis. Barcode lookup is optional and user initiated; it sends only the UPC/EAN selected by the user to retrieve public product nutrition data.
>
> Review path: complete onboarding, open Track, choose Meals, then choose Photo Estimate. Select a meal photo, review the privacy notice, request an estimate, edit any suggested items as needed, and save the reviewed meal. Settings > Subscription contains the purchase and restore controls. Settings > Apple Health contains optional read-only HealthKit permissions.

## Reviewer Test Steps

1. Install the approved build with a build number greater than `17`; complete onboarding without creating an account.
2. Open `Track` > `Meals` and confirm manual entry and `Scan barcode` remain available.
3. Choose `Photo Estimate`, select a non-sensitive test meal photo, and read the in-app disclosure before sending it.
4. Verify the estimate result is presented as an editable draft. Change an item or amount, then save it and confirm the reviewed nutrition appears in the local meal log.
5. Return to the meal flow and confirm a user without an active trial or subscription receives the entitlement message and can still use barcode lookup or manual entry.
6. Open `Settings` > `Subscription` to review purchase/restore controls; do not require a private CycleBalance login.
7. Open `Settings` > `Apple Health` and verify HealthKit access is optional and read-only.

## App Privacy And Policy Delta

Update App Store Connect App Privacy for the approved cloud-photo build:

| Data type | Purpose | Linked to user | Used for tracking | Required disclosure |
| --- | --- | --- | --- | --- |
| User Content > Photos or Videos | App Functionality | No | No | A user-initiated meal photo is transmitted as one normalized JPEG to the CycleBalance proxy/Gemini for an editable estimate. The proxy does not retain raw image bytes. |
| Other Data > Other Data Types | App Functionality | No | No | Optional UPC/EAN barcode lookup continues to send only the barcode chosen by the user to obtain product nutrition. |
| Purchases > Purchase History | App Functionality | No | No | RevenueCat manages subscription/trial entitlement checks. |

The live privacy policy and terms must state all of the following before submission:

- A meal photo is uploaded only after the user selects it and requests a photo estimate.
- Processing is limited to creating the requested meal estimate; the proxy does not retain raw uploaded image bytes.
- Nutrition remains local unless the user reviews and saves it; saved-meal-photo retention is local and separately controlled in Settings.
- Active trial/subscription checks, daily/trial quotas, and a budget kill switch limit feature access.
- Barcode lookup and manual entry are available alternatives that do not require photo analysis.
- The result is an editable personal-tracking estimate, not medical advice or a diagnosis.

## Screenshot Checklist

- [ ] Capture the enabled meal entry screen with `Photo Estimate`, `Scan barcode`, and manual entry visible; never show a real person's health data or an unredacted meal photo.
- [ ] Capture the pre-send privacy notice explaining user-initiated upload and local reviewed-nutrition storage.
- [ ] Capture the editable estimate review screen, including the user-editable items and save action.
- [ ] Capture the entitlement/fallback state showing barcode and manual alternatives; do not expose test identifiers or backend errors.
- [ ] Capture subscription and restore controls with the final localized legal-link layout.
- [ ] Refresh iPhone screenshot sizes and every shipped App Store localization as required by the new feature; retain no misleading coming-soon copy on an enabled screenshot set.
- [ ] Verify screenshots, App Privacy answers, policy text, reviewer notes, and the archived build all describe the same enabled/disabled state.

## Owner Actions Pending Approval

- [ ] Approve a build number greater than `17` and the target review train.
- [ ] Confirm whether Photo Estimate is enabled for the review candidate or remains coming soon.
- [ ] Enter the approved App Privacy answers and updated reviewer notes in App Store Connect.
- [ ] Publish and verify the live privacy-policy and terms changes.
- [ ] Upload the approved screenshot set and submit only after the physical-device and quality gates pass.
