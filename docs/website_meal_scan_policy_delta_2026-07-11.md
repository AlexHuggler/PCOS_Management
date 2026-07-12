# CycleBalance Website Meal Scan Policy Delta

Date: 2026-07-11

Status: owner and legal review draft. Do not publish this copy until the enabled build, Google retention posture, App Privacy answers, and in-app consent screen are final. The live privacy, terms, and support pages were verified on 2026-07-11 and still contain absolute on-device/no-server claims.

This is product/privacy drafting, not legal advice. Preserve the current website's RevenueCat, barcode, HealthKit, Apple Ads, support-form, and localization updates when applying it.

## Privacy Policy: Optional Photo Estimate

Add a dedicated subsection under both `Information We Collect` and `Third-Party Services`:

> **Optional Photo Estimate.** When Photo Estimate is available, CycleBalance first normalizes the meal photo on your device and checks whether it exactly matches a meal you previously reviewed. If you choose **Use Previous Meal**, the reviewed draft is restored locally and the photo is not sent to CycleBalance, Google, RevenueCat, or any other remote service.
>
> For a fresh estimate, CycleBalance identifies Google Gemini as the third-party AI processor and asks you to confirm before uploading. If you continue, the app sends one compressed JPEG through the CycleBalance meal-analysis service to Google Gemini. Barcode lookup and manual entry remain available without photo analysis.
>
> The CycleBalance proxy processes the JPEG in memory and does not retain raw uploaded image bytes. It may retain a structured meal-nutrition estimate for up to 24 hours under a pseudonymous identifier so an identical request can be reused without another AI call or quota charge. Daily scan-count records expire after three days and trial-total records expire after thirty days. Application logs retain only an image-hash prefix, provider/model, token and cost information, quota tier, budget mode, and cache status for up to thirty days; they do not contain the meal photo, meal name, structured estimate, or app-user identifier. Cloud Run HTTP request logs for the meal-analysis service are excluded from the project's default log bucket.
>
> Google states that paid Gemini requests are not used to improve its products. Under Google's standard paid-service posture, prompts, contextual information, and outputs may be retained for up to 55 days solely for abuse monitoring and required legal or regulatory disclosures. Google-authorized personnel may review content flagged by safety systems under controlled procedures.

Replace the final paragraph above with this only after Zero Data Retention is verified for `cyclebalance-prod-20260710`:

> Google states that paid Gemini requests are not used to improve its products. Google has approved Zero Data Retention for CycleBalance's production project, so user content and identifiable metadata are cleared before abuse-monitoring logs are written. CycleBalance does not use Gemini grounding, Files, stored interactions, Live session resumption, or explicit context caching for meal estimates.

## Privacy Policy: Choices, Retention, And Deletion

Add under `Your Rights and Choices`:

> Photo Estimate is optional. You can use manual meal entry or barcode lookup instead, close the confirmation without uploading, or reuse an exact previously reviewed meal locally. Deleting a saved meal removes its local repeat-meal record. Deleting all CycleBalance data removes local meal photos, nutrition records, and repeat-meal fingerprints. Pseudonymous server cache and quota records expire automatically on the schedules described above.

Before publishing, choose one final deletion sentence:

- Automatic-expiry posture: `CycleBalance does not maintain an account that can be used to retrieve these pseudonymous records; they are automatically deleted after their stated retention periods.`
- Self-service posture: `You can also use Settings > Privacy > Clear Cloud Meal Scan Data to request deletion of the current app installation's pseudonymous meal-scan cache and quota records.`

## Terms: AI Meal Estimate Clause

Add under `Description of Service` and cross-reference from `Data and Privacy`:

> **AI Meal Estimates.** Photo Estimate is an optional premium feature that creates an editable draft from a user-selected meal photo. A fresh estimate requires explicit confirmation before CycleBalance sends a compressed photo through its secure proxy to Google Gemini. Exact reuse of a previously reviewed meal remains on device. Availability may be limited by subscription or trial status, daily or trial quotas, provider availability, model safety controls, and CycleBalance budget safeguards.

Add under `Medical Disclaimer`:

> AI meal estimates may be incomplete, inaccurate, or unable to identify hidden ingredients, oils, sauces, preparation methods, allergens, or exact portions. They are provided only as an editable starting point for personal tracking. Review food labels and consult a qualified professional for medical, nutrition, allergy, pregnancy, or treatment decisions.

## Support FAQ

Replace the absolute `Everything stays on your device` answer with:

> Your health logs remain local by default. Optional services are clearly separated: Apple and RevenueCat manage purchases, barcode lookup sends only the UPC/EAN you choose, and a fresh Photo Estimate sends one compressed meal photo to Google Gemini only after you confirm. Exact reuse of a previously reviewed meal stays on device. CycleBalance does not use third-party advertising or analytics SDKs for health logs. See the Privacy Policy for cache, quota, and provider-retention details.

## Publication Checklist

- [ ] Owner chooses verified Google ZDR or standard 55-day disclosure.
- [ ] Owner chooses automatic expiry or self-service cloud deletion.
- [ ] In-app consent copy exactly matches the selected retention posture.
- [ ] English privacy, terms, support FAQ, metadata descriptions, and structured FAQ data are updated together.
- [ ] German, French, Italian, Japanese, Korean, and Dutch legal/support pages receive reviewed translations of the same facts.
- [ ] Legal links, language switchers, canonical URLs, and page dates remain correct.
- [ ] Render and inspect every locale at desktop and mobile widths.
- [ ] Publish only after owner approval, then verify `https://cyclebalance.app/privacy`, `/terms`, and `/support` from the live site.
- [ ] Reconcile the live pages with App Store Connect App Privacy and the exact archived build before submission.
