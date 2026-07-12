# App Store Readiness Checklist

## Verified In Repo

- Release simulator build succeeds for the `PCOS` app target.
- Onboarding copy is localized for every supported non-English locale: `ja`, `it`, `ko`, `fr`, `de`, `nl`.
- System-default launches show localized onboarding instead of English fallback when `app.language` remains `system`.
- Tab and navigation labels use polished locale-specific wording instead of literal machine-style translations.
- Paywall copy, legal links, feature labels, and subscription period units follow the selected app language or supported system locale without English fallback.
- `Localizable.strings` coverage includes onboarding, paywall, settings, submission, accessibility, pregnancy, and postpartum copy.
- `InfoPlist.strings` coverage includes photo, camera, and HealthKit usage descriptions for every supported locale.
- StoreKit product localizations remain present for each supported locale.
- `PCOSTests` in-memory SwiftData schema includes `PregnancyRecord`, so localization and app-language tests do not crash on fetch.
- Locale-matrix UI coverage validates localized onboarding phases, localized tab shell labels, and localized paywall presentation.
- The production meal-scan proxy, Firebase App Check/App Attest validation, RevenueCat V2 entitlement lookup, Firestore quotas/cache, and budget controller are deployed in `cyclebalance-prod-20260710` but remain private and disabled.
- The production Gemini key is valid for model metadata, but paid inference is not funded: both allowlisted model smoke requests currently stop with `429 RESOURCE_EXHAUSTED` because the Gemini Prepay balance is depleted. No App Store build may present Photo Estimate as available until owner-approved Prepay funding, the `$120` AI Studio project spend cap, and a successful generation smoke test are recorded.
- The current Release configuration keeps Meal Scan V2, Gemini scanning, mock scan data, and photo retention off. Its locally signed entitlements use the production App Attest environment, and its app configuration contains only the public proxy URL and mobile SDK keys.
- Exact repeat-meal reuse is implemented as an on-device reviewed-draft cache. Exact hits make no network request and consume no quota; similar-image matching remains disabled until its private labeled evaluation gate passes.

## App Store Connect Status

- Current submission: App Store Connect rejected a replacement `1.0.3` build `17` upload on July 3, 2026 because the `1.0.3` train is closed and the approved version is already `1.0.3`. Per the fallback release plan, `MARKETING_VERSION` was moved to `1.0.4` and `CURRENT_PROJECT_VERSION` remains `17`.
- Build `1.0.4` (`17`) was archived, exported, uploaded, attached to iOS version `1.0.4`, and submitted for App Review on July 3, 2026. App Store Connect read-back: app version `WAITING_FOR_REVIEW`, build `VALID`, export compliance `usesNonExemptEncryption = false`, release `AFTER_APPROVAL`, review submission relationship present. The exported IPA is at `Artifacts/Exports/CycleBalance-1.0.4-b17/PCOS.ipa`.
- Version `1.0.4` App Store listing carry-forward was verified in App Store Connect before submission: seven localizations remain present (`de-DE`, `en-US`, `fr-FR`, `it`, `ja`, `ko`, `nl-NL`); descriptions, keywords, support URL, marketing URL, and promotional text match `1.0.3`; localized `What's New` text was added for `1.0.4`; App Review contact/testing notes were copied forward.
- Media carry-forward was verified in App Store Connect Media Manager for `1.0.4`: the page shows `6 of 10 Screenshots` for iPhone, and the six unique screenshot image URLs match the existing `1.0.3` listing. App Store Connect indicates those screenshots are used for all iOS display sizes and localizations. No app preview sets are present.
- Build `1.0.3` (`16`) was archived, exported, validated, uploaded, attached to iOS version `1.0.3`, and submitted for App Review on June 23, 2026. App Store Connect read-back: app version `WAITING_FOR_REVIEW`, build `VALID`, export compliance `usesNonExemptEncryption = false`, release `AFTER_APPROVAL`, review submission `WAITING_FOR_REVIEW`. The exported IPA is at `Artifacts/Exports/CycleBalance-1.0.3-b16/PCOS.ipa`.
- Apple did not block the June 23, 2026 API submission for the developer license agreement; keep monitoring Agreements, Tax, and Banking for any account-level prompts before approval/release.
- Re-check the live `cyclebalance.app` legal/policy pages during review; the local website repo has been aligned, but the live privacy/terms pages still need to be verified after deployment.
- Confirm the app record uses the final localized app name, subtitle, keywords, and promotional text before future storefront metadata changes. The `1.0.4` submission preserved the existing `1.0.3` descriptions, keywords, support URL, marketing URL, promotional text, and media assets.
- Review the ASO and custom product page plan in `docs/app_store_optimization_review_2026-06-22.md` before changing live title, subtitle, keyword, screenshot, or custom product page metadata.
- The App Privacy questionnaire was sufficient for the June 23, 2026 submission. Keep using the first-pass answer sheet in `docs/app_store_connect_first_pass_2026-06-22.md` before future privacy-affecting build changes.
- Do not enable cloud AI meal photo estimates in a submitted build until App Privacy, privacy policy, terms, screenshots, and App Review notes disclose user-initiated photo analysis through the CycleBalance proxy/Gemini, and 50-100 representative meal photos pass a labeled quality review. The deployed proxy security gates are ready, but the current release must continue to show the photo estimate as coming soon.
- Upload the current privacy policy URL (`https://cyclebalance.app/privacy`), support URL (`https://cyclebalance.app/support`), and marketing URL (`https://cyclebalance.app/`) if required.
- Finish entering the remaining custom product pages from `/Users/alexhuggler/Desktop/AI Work/PCOS/App Images/AppStore Images/Custom Product Pages/app_store_connect_handoff_2026-06-22.md`; do not submit those custom product pages until after the build review is ready.
- Future ASO improvement: prepare locale-specific screenshots for iPhone form factors that match the supported in-app locales. The `1.0.4` submission intentionally carries forward the existing six iPhone screenshots across all locales.
- App Review notes were updated in App Store Connect on June 22, 2026 to cover read-only HealthKit behavior, local-first storage, optional barcode lookup, RevenueCat purchase handling, Apple Ads attribution diagnostics, high-value-moment review prompts, and review-before-save nutrition estimates. Version `1.0.4` release notes were updated across the existing seven App Store locales before submission.
- Verify App Store Connect subscription localizations and RevenueCat offering/package metadata stay in sync with the in-app paywall copy and pricing plan names.
- Capture locale-specific paywall screenshots that match the final subscription naming and legal-link layout for each shipped localization.
- Confirm age rating, content rights, export compliance, and Sign in with Apple requirements are accurate for this build.

## Recommended Final Smoke Checks

- Launch a fresh install with `app.language = system` under each supported locale and walk onboarding through completion.
- Trigger the camera and HealthKit permission prompts in at least one non-English locale and confirm the system sheets use localized `InfoPlist.strings`.
- Open paywall, settings, calendar, track, insights, and pregnancy/postpartum surfaces in at least one Latin-script locale and one CJK locale.
- Validate restore purchases, privacy policy, and terms links from the paywall before submission.

## Meal Scan Review Preparation (Pending Owner Approval)

- A preparation-only packet now exists at `docs/app_store_meal_scan_review_packet_2026-07-11.md`. It is not App Store Connect metadata and has not been submitted.
- The currently submitted `1.0.4 (17)` build must continue to describe AI meal scanning as coming soon. A future cloud-photo review candidate requires a build number greater than `17` and separate approval for every build-number, metadata, screenshot, and submission action.
- Before enabling Photo Estimate for App Review, complete the physical App Check probe, labeled meal-photo quality review, App Privacy update, deployed privacy-policy/terms verification, reviewer test-access confirmation, and screenshot refresh.
- Before the labeled model comparison, purchase only an owner-approved `$10-$25` Gemini evaluation balance. Keep auto-reload off for evaluation; any production auto-reload requires a separate approval and a monthly auto-charge limit no greater than `$150`.
- The required App Privacy/policy posture is user-initiated photo upload for purpose-limited analysis, no raw-image retention on the proxy, local-only reviewed nutrition storage, quota/budget limits, and continued barcode/manual fallbacks.
- Repeat-meal review screenshots are captured in Botanical Journal and Lunar Calm at accessibility XXXL. App Review copy must state that an exact previously reviewed meal can be reused locally or deliberately scanned as new.
