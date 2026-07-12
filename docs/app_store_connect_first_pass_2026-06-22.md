# CycleBalance App Store Connect First Pass

Date: 2026-06-22

Purpose: first-pass data for App Store Connect human review and owner verification. Do not publish App Privacy responses or submit the build until the account owner verifies these answers against the exact archived build.

## Source Basis

- Apple App Privacy guidance: data processed only on device is not "collected"; data transmitted off device and retained by the developer or third-party partner generally must be declared.
- RevenueCat bundled privacy manifest in the current dependency declares `Purchase History`, purpose `App Functionality`, not linked, not used for tracking.
- CycleBalance release code uses local SwiftData storage, read-only HealthKit, optional barcode lookup, RevenueCat billing, and local Apple Ads attribution diagnostics.
- Meal Scan V2 is release-disabled by default unless explicitly enabled; barcode lookup is visible and user-initiated.

## App Store Connect URLs

- Privacy Policy URL: `https://cyclebalance.app/privacy`
- Support URL: `https://cyclebalance.app/support`
- Marketing URL: `https://cyclebalance.app/`
- Privacy Choices URL: leave blank for now unless a dedicated privacy choices page is added.

## App Privacy Questionnaire

Recommended answer to "Do you or your third-party partners collect data from this app?": `Yes`.

Declare these data types:

| Data type | Purpose | Linked to user | Used for tracking | Notes |
| --- | --- | --- | --- | --- |
| Purchases > Purchase History | App Functionality | No | No | RevenueCat privacy manifest declares purchase history for subscription and entitlement management. Apple handles payment details outside the app. |
| Other Data > Other Data Types | App Functionality | No | No | Optional UPC/EAN barcode lookup sends the barcode the user chooses to look up to Open Food Facts. USDA FoodData Central lookup is used only when a local API key is configured. |

Do not declare these for the current release behavior unless the archived build changes:

- Health & Fitness: cycle logs, symptoms, glucose, nutrition entries, HealthKit samples, reproductive context, and insights stay on device and are not transmitted to CycleBalance or third-party analytics/ad SDKs.
- Sensitive Info: pregnancy, lactation, sexual activity, and similar context stay on device.
- Photos or Videos: meal, skin, and hair photos stay local unless the user exports or shares them outside the app.
- Contact Info: no account sign-up or in-app email collection found in the current app flow.
- Usage Data, Diagnostics, Location, Browsing History, Search History, Device ID, Advertising Data: no third-party analytics/ad SDK collection found in the current app flow.

## Ads And Attribution Disclosure

First-pass disclosure:

> CycleBalance does not display ads, does not include third-party advertising SDKs, and does not use App Tracking Transparency tracking. The app requests an Apple Ads attribution token through Apple's AdServices framework when available and stores attribution diagnostics locally for debugging Apple Search Ads attribution. Health logs, HealthKit samples, meal photos, symptom data, and journal photos are not sent to Apple Ads or ad networks.

App Privacy label impact: no additional App Privacy data type for Apple Ads attribution unless the build starts sending the attribution token or derived attribution data off device to CycleBalance, RevenueCat, analytics, or another third party.

## Nutrition And Meal Scan Claims

Safe reviewer/product wording:

> Meal and barcode features create editable, review-before-save meal drafts for personal tracking. Nutrition values are estimates or public food-database results and may vary by serving size, preparation, ingredients, and data completeness. CycleBalance is not a medical device and does not provide medical advice, nutrition counseling, allergy guidance, diagnosis, or treatment.

Build facts to verify before submission:

- Barcode lookup is user-initiated and discloses that UPC codes are sent to Open Food Facts.
- USDA lookup is only used when a local USDA FoodData Central API key is configured.
- Meal Scan V2 is release-disabled by default unless explicitly enabled for the submitted build.
- If Meal Scan V2 is enabled, it must remain local-first, editable, and review-before-save; do not claim exact nutrition scanning.
- If Gemini/cloud meal-photo estimation is enabled, update App Privacy, privacy policy, terms, screenshots, and review notes before submission. The submitted build must name Google Gemini as the third-party AI processor, wait for explicit confirmation before every fresh upload, state the verified provider-retention posture, and keep barcode/manual logging available without photo analysis.
- Limited-production cloud photo estimates require the production proxy gates: `MEAL_SCAN_ENABLED` kill switch, App Attest enforcement with a configured verifier, RevenueCat entitlement/trial verification, Firestore quota storage, 5/day and 25/trial limits for trial users, 5/day soft and 10/day hard limits for paid users, monthly budget thresholds (`$75` alert, `$90` degrade to Flash-Lite only, `$120` disable), and no raw image retention on the proxy.
- The proxy's no-retention guarantee does not cover Google. Under the standard paid Gemini posture, Google may retain prompts, context, and outputs for 55 days for abuse monitoring. Before enabling uploads, either verify ZDR approval for `cyclebalance-prod-20260710` or disclose the 55-day posture throughout the app and policy surfaces.

Conditional App Privacy update if cloud photo estimates are enabled:

| Data type | Purpose | Linked to user | Used for tracking | Notes |
| --- | --- | --- | --- | --- |
| User Content > Photos or Videos | App Functionality | No | No | A user-confirmed meal photo estimate sends one normalized JPEG through the CycleBalance proxy to Google Gemini. The proxy does not retain raw bytes; standard Gemini abuse monitoring may retain request content for up to 55 days unless production-project ZDR is verified. |
| Other Data > Other Data Types | App Functionality | No | No | Continue declaring optional UPC/EAN barcode lookup. Add proxy quota metadata only if retained in a way that qualifies as collected data under Apple guidance. |

## App Review Notes

Status: saved in App Store Connect for iOS version 1.0.2 on 2026-06-22.

> CycleBalance is a PCOS-focused health and wellness tracker. The app stores user health logs locally on device using SwiftData. HealthKit access is optional and read-only; users choose individual Apple Health permissions, and CycleBalance does not write to HealthKit.
>
> No account or sign-in is required. App Store purchases are handled by Apple and subscription entitlements are managed with RevenueCat. RevenueCat does not receive CycleBalance health logs.
>
> Barcode meal lookup is optional and user-initiated. The app sends only the UPC/EAN barcode to Open Food Facts to retrieve public product nutrition data, and the user reviews the result before saving a meal. USDA FoodData Central lookup is used only when a local API key is configured. AI meal estimate features are local-first, editable, and review-before-save when enabled; they should not be treated as exact nutrition scanning.
>
> Nutrition and meal features are estimates for personal tracking only and are not medical advice, nutrition counseling, diagnosis, treatment, or allergy guidance.
>
> The app does not display ads and does not include third-party advertising or analytics SDKs. It may request an Apple Ads attribution token through Apple's AdServices framework and stores attribution diagnostics locally for Apple Search Ads debugging. Health logs, HealthKit samples, meal photos, symptom data, and journal photos are not sent to Apple Ads or ad networks.
>
> Native App Store review prompts are not shown during onboarding. They are only eligible after high-value moments such as a sustained logging streak, first insight, generated report, or saved photo progress.
>
> Testing notes:
> - Free flow: launch, complete onboarding, then use Today, Calendar, Track, and Insights.
> - Premium flow: Settings > Subscription. RevenueCat/StoreKit manages the subscription.
> - HealthKit: Settings > Apple Health, then grant optional read permissions.

## Website And Legal Sync

Updated in the GitHub Pages source tree:

- Privacy policy last updated to June 22, 2026.
- HealthKit scope now matches the app's current read-only categories.
- Optional barcode lookup, RevenueCat purchases, and Apple Ads attribution diagnostics are disclosed separately.
- Support FAQ no longer says "everything" stays on device; it now distinguishes local health logs from limited optional services.
- Landing page no longer uses unsupported `10K+`, `4.9 App Store Rating`, or testimonial claims.

## Final Owner Verification

- Verify the App Store Connect privacy preview after entering the above.
- Verify the archived build has no enabled cloud meal-photo analysis, analytics SDK, third-party ad SDK, or CloudKit health sync.
- Verify the public `https://cyclebalance.app/privacy` and `https://cyclebalance.app/terms` pages are deployed after the GitHub Pages source changes are merged/published.
- Verify subscription products, RevenueCat offering IDs, and App Store Connect pricing are aligned before final submit.
