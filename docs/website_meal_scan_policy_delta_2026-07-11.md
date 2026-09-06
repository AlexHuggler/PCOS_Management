# CycleBalance Website Meal Scan Policy Delta

Date: 2026-07-12

Status: published and live. The privacy, terms, and support pages are current. The Privacy Policy uses Google's standard paid-API disclosure that request content may be retained for up to 55 days, and the Terms and Support FAQ describe the remote Photo Estimate path. Support was published in commit `e119045`. App Privacy answers and App Store screenshots remain incomplete and must not be represented as submitted.

This file records the live meal-scan policy delta; it is product/privacy documentation, not legal advice. The published pages preserve the website's RevenueCat, barcode, HealthKit, Apple Ads, support-form, and localization disclosures.

## Privacy Policy: Optional Photo Estimate

The live Privacy Policy includes the following substance under `Information We Collect` and `Third-Party Services`:

> **Optional Photo Estimate.** When Photo Estimate is available, CycleBalance first normalizes the meal photo on your device and checks whether it exactly matches a meal you previously reviewed. If you choose **Use Previous Meal**, the reviewed draft is restored locally and the photo is not sent to CycleBalance, Google, RevenueCat, or any other remote service.
>
> For a fresh estimate, CycleBalance identifies Google Gemini as the third-party AI processor and asks you to confirm before uploading. If you continue, the app sends one compressed JPEG through the CycleBalance meal-analysis service to Google Gemini. Barcode lookup and manual entry remain available without photo analysis.
>
> The CycleBalance proxy processes the JPEG in memory and does not retain raw uploaded image bytes. It may retain a structured meal-nutrition estimate for up to 24 hours under a pseudonymous identifier so an identical request can be reused without another AI call or quota charge. Daily scan-count records expire after three days and trial-total records expire after thirty days. Application logs retain only an image-hash prefix, provider/model, token and cost information, quota tier, budget mode, and cache status for up to thirty days; they do not contain the meal photo, meal name, structured estimate, or app-user identifier. Cloud Run HTTP request logs for the meal-analysis service are excluded from the project's default log bucket.
>
> Google states that paid Gemini requests are not used to improve its products. Under Google's standard paid-service posture, prompts, contextual information, and outputs may be retained for up to 55 days solely for abuse monitoring and required legal or regulatory disclosures. Google-authorized personnel may review content flagged by safety systems under controlled procedures.

Do not replace the standard disclosure above unless project-specific Zero Data Retention approval is verified for `cyclebalance-prod-20260710`. There is currently no verified ZDR approval or evidence that a ZDR request was submitted. If approval is verified in the future, the replacement text is:

> Google states that paid Gemini requests are not used to improve its products. Google has approved Zero Data Retention for CycleBalance's production project, so user content and identifiable metadata are cleared before abuse-monitoring logs are written. CycleBalance does not use Gemini grounding, Files, stored interactions, Live session resumption, or explicit context caching for meal estimates.

## Privacy Policy: Choices, Retention, And Deletion

The live Privacy Policy includes the following substance under `Your Rights and Choices`:

> Photo Estimate is optional. You can use manual meal entry or barcode lookup instead, close the confirmation without uploading, or reuse an exact previously reviewed meal locally. Deleting a saved meal removes its local repeat-meal record. Deleting all CycleBalance data removes local meal photos, nutrition records, and repeat-meal fingerprints. Pseudonymous server cache and quota records expire automatically on the schedules described above.

Visual-similarity reuse is not part of the live policy posture. It remains disabled unless the private 100-image evaluation set passes the approved similarity-policy gate; exact on-device matching is separate.

The live page uses the automatic-expiry posture: `CycleBalance does not maintain an account that can be used to retrieve these pseudonymous records; they are automatically deleted after their stated retention periods.` It does not claim that a self-service cloud deletion control is available.

## Terms: AI Meal Estimate Clause

The live Terms include the following substance under `Description of Service`, with the remote-photo exception cross-referenced from `Data and Privacy`:

> **AI Meal Estimates.** Photo Estimate is an optional premium feature that creates an editable draft from a user-selected meal photo. A fresh estimate requires explicit confirmation before CycleBalance sends a compressed photo through its secure proxy to Google Gemini. Exact reuse of a previously reviewed meal remains on device. Availability may be limited by subscription or trial status, daily or trial quotas, provider availability, model safety controls, and CycleBalance budget safeguards.

The live Terms include the following substance under `Medical Disclaimer`:

> AI meal estimates may be incomplete, inaccurate, or unable to identify hidden ingredients, oils, sauces, preparation methods, allergens, or exact portions. They are provided only as an editable starting point for personal tracking. Review food labels and consult a qualified professional for medical, nutrition, allergy, pregnancy, or treatment decisions.

## Support FAQ

The live Support FAQ, published in commit `e119045`, replaces the former absolute on-device answer with:

> Your health logs remain local by default. Optional services are clearly separated: Apple and RevenueCat manage purchases, barcode lookup sends only the UPC/EAN you choose, and a fresh Photo Estimate sends one compressed meal photo to Google Gemini only after you confirm. Exact reuse of a previously reviewed meal stays on device. CycleBalance does not use third-party advertising or analytics SDKs for health logs. See the Privacy Policy for cache, quota, and provider-retention details.

## Publication And Submission Checklist

- [x] Use the standard paid-API disclosure that request content may be retained for up to 55 days; do not claim project-specific ZDR without verified approval.
- [x] Publish and verify the privacy, terms, and support pages; support publication is commit `e119045`.
- [x] Keep the live policy limited to exact on-device repeat matching while the private 100-image similarity evaluation remains pending.
- [ ] Complete final owner/legal and native-speaker review of every published locale.
- [ ] Confirm in-app consent copy exactly matches the live standard 55-day retention disclosure.
- [ ] Recheck legal links, language switchers, canonical URLs, page dates, and desktop/mobile rendering for every locale before scanner enablement.
- [ ] Complete and submit App Store Connect App Privacy answers.
- [ ] Capture and upload the final App Store screenshot set from the archived review build.
- [ ] Reconcile the live pages with App Store Connect App Privacy and the exact archived build before submission.
