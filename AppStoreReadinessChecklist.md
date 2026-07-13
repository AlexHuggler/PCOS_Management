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
- The live production meal-scan proxy remains private, `MEAL_SCAN_ENABLED=false`, and pinned to Gemini secret version `2`. The release candidate adds strict RevenueCat API v2 corroboration after Apple StoreKit transaction and current-status verification; that new revision has not been deployed. Apple remains authoritative for the HMAC principal and quota tier, and no client RevenueCat App User ID is trusted.
- Gemini has an owner-approved `$25` Prepay balance, auto-reload is off, and `gemini-3.1-flash-lite` passed a production-key mechanics smoke test. Funding is no longer a launch blocker, but the full 80-image/120-call quality benchmark remains mandatory.
- Local target `1.0.5 (18)` records explicit Release settings that keep the Meal Scan UI, Gemini path, mock data, debug-direct path, fallback model, and visual similarity off until benchmark approval. The Release USDA client key is forced empty; the mobile app uses only the proxy path for AI estimates.
- Exact repeat-meal reuse is implemented as an on-device reviewed-draft cache. Exact hits make no network request and consume no quota; similar-image matching remains disabled until its private labeled evaluation gate passes.

## App Store Connect Status

- Build `18` was verified unused before the local `1.0.5 (18)` version bump. It has not been archived, uploaded, distributed through TestFlight, attached to a version, or submitted; this checklist does not authorize those actions.
- Current submission: App Store Connect rejected a replacement `1.0.3` build `17` upload on July 3, 2026 because the `1.0.3` train is closed and the approved version is already `1.0.3`. Per the fallback release plan, `MARKETING_VERSION` was moved to `1.0.4` and `CURRENT_PROJECT_VERSION` remains `17`.
- Build `1.0.4` (`17`) was archived, exported, uploaded, attached to iOS version `1.0.4`, and submitted for App Review on July 3, 2026. App Store Connect read-back: app version `WAITING_FOR_REVIEW`, build `VALID`, export compliance `usesNonExemptEncryption = false`, release `AFTER_APPROVAL`, review submission relationship present. The exported IPA is at `Artifacts/Exports/CycleBalance-1.0.4-b17/PCOS.ipa`.
- Version `1.0.4` App Store listing carry-forward was verified in App Store Connect before submission: seven localizations remain present (`de-DE`, `en-US`, `fr-FR`, `it`, `ja`, `ko`, `nl-NL`); descriptions, keywords, support URL, marketing URL, and promotional text match `1.0.3`; localized `What's New` text was added for `1.0.4`; App Review contact/testing notes were copied forward.
- Media carry-forward was verified in App Store Connect Media Manager for `1.0.4`: the page shows `6 of 10 Screenshots` for iPhone, and the six unique screenshot image URLs match the existing `1.0.3` listing. App Store Connect indicates those screenshots are used for all iOS display sizes and localizations. No app preview sets are present.
- Build `1.0.3` (`16`) was archived, exported, validated, uploaded, attached to iOS version `1.0.3`, and submitted for App Review on June 23, 2026. App Store Connect read-back: app version `WAITING_FOR_REVIEW`, build `VALID`, export compliance `usesNonExemptEncryption = false`, release `AFTER_APPROVAL`, review submission `WAITING_FOR_REVIEW`. The exported IPA is at `Artifacts/Exports/CycleBalance-1.0.3-b16/PCOS.ipa`.
- Apple did not block the June 23, 2026 API submission for the developer license agreement; keep monitoring Agreements, Tax, and Banking for any account-level prompts before approval/release.
- Re-check the live `cyclebalance.app` legal/policy pages during review; the local website repo has been aligned, but the live privacy/terms pages still need to be verified after deployment.
- Live verification on July 11, 2026 found that `/privacy`, `/terms`, and `/support` still show the May 11 on-device/no-external-server wording. Do not enable Photo Estimate until the reviewed policy delta in `docs/website_meal_scan_policy_delta_2026-07-11.md` is approved, localized, published, and read back from the live site.
- Confirm the app record uses the final localized app name, subtitle, keywords, and promotional text before future storefront metadata changes. The `1.0.4` submission preserved the existing `1.0.3` descriptions, keywords, support URL, marketing URL, promotional text, and media assets.
- Review the ASO and custom product page plan in `docs/app_store_optimization_review_2026-06-22.md` before changing live title, subtitle, keyword, screenshot, or custom product page metadata.
- The App Privacy questionnaire was sufficient for the June 23, 2026 submission. Keep using the first-pass answer sheet in `docs/app_store_connect_first_pass_2026-06-22.md` before future privacy-affecting build changes.
- Do not enable cloud AI meal photo estimates in a submitted build until App Privacy, privacy policy, terms, screenshots, and App Review notes disclose user-initiated photo analysis through the CycleBalance proxy/Gemini, and the frozen 80-image/120-call benchmark passes every release gate. Disabled builds must hide Photo Estimate cleanly rather than advertise an unavailable feature.
- Explicit per-upload permission now names Google Gemini and waits for an affirmative action before every fresh upload. Use Google's standard disclosure that request content may be retained for up to 55 days; no project-specific Zero Data Retention approval is verified.
- App Privacy preparation must conservatively cover Photos or Videos, Health, Fitness, Purchase History, User ID, Product Interaction, and Other Data Types for App Functionality. Each is marked linked to the user, not used for tracking, with no tracking domains. The disclosure must explain the 24-hour structured-result cache, HMAC-derived StoreKit principal, rolling/lifetime allowance records, and current Gemini retention of up to 55 days.
- Upload the current privacy policy URL (`https://cyclebalance.app/privacy`), support URL (`https://cyclebalance.app/support`), and marketing URL (`https://cyclebalance.app/`) if required.
- Finish entering the remaining custom product pages from `/Users/alexhuggler/Desktop/AI Work/PCOS/App Images/AppStore Images/Custom Product Pages/app_store_connect_handoff_2026-06-22.md`; do not submit those custom product pages until after the build review is ready.
- Future ASO improvement: prepare locale-specific screenshots for iPhone form factors that match the supported in-app locales. The `1.0.4` submission intentionally carries forward the existing six iPhone screenshots across all locales.
- App Review notes were updated in App Store Connect on June 22, 2026 to cover read-only HealthKit behavior, local-first storage, optional barcode lookup, RevenueCat purchase handling, Apple Ads attribution diagnostics, high-value-moment review prompts, and review-before-save nutrition estimates. Version `1.0.4` release notes were updated across the existing seven App Store locales before submission.
- Verify App Store Connect subscription localizations and RevenueCat offering/package metadata stay in sync with the in-app paywall copy and pricing plan names.
- Before release, verify the exact candidate archive against the production RevenueCat offering, monthly/annual packages, localized products, pricing, purchase, restore, receipt synchronization, and a least-privilege API v2 secret with `customer_information:subscriptions:read`. This remains incomplete. RevenueCat is a strict secondary server check; Apple StoreKit remains the principal and tier authority.
- Capture locale-specific paywall screenshots that match the final subscription naming and legal-link layout for each shipped localization.
- Confirm age rating, content rights, export compliance, and Sign in with Apple requirements are accurate for this build.

## Recommended Final Smoke Checks

- Launch a fresh install with `app.language = system` under each supported locale and walk onboarding through completion.
- Trigger the camera and HealthKit permission prompts in at least one non-English locale and confirm the system sheets use localized `InfoPlist.strings`.
- Open paywall, settings, calendar, track, insights, and pregnancy/postpartum surfaces in at least one Latin-script locale and one CJK locale.
- Validate restore purchases, privacy policy, and terms links from the paywall before submission.

## Meal Scan Review Preparation (Pending Owner Approval)

- A preparation-only packet now exists at `docs/app_store_meal_scan_review_packet_2026-07-11.md`. It is not App Store Connect metadata and has not been submitted.
- The currently submitted `1.0.4 (17)` build remains scanner-disabled. Local target `1.0.5 (18)` is also fail-closed: Photo Estimate stays hidden until the benchmark and release gates pass. Build `18` is verified unused and has not been uploaded.
- The physical App Check probe is complete. Before enabling Photo Estimate for App Review, pass the 80-image quality benchmark, update and verify App Privacy, complete native-speaker/legal review, confirm reviewer access, and capture final screenshots from the exact frozen archive.
- The App Store distribution profile is a blocker: regenerate or verify that the profile embedded in the exact archive contains production App Attest and HealthKit with `get-task-allow=false`. Local entitlements alone do not clear this gate.
- Before the labeled model comparison, purchase only an owner-approved `$10-$25` Gemini evaluation balance. Keep auto-reload off for evaluation; any production auto-reload requires a separate approval and a monthly auto-charge limit no greater than `$150`.
- Fresh proxy access uses a verified StoreKit 2 transaction JWS and live Apple subscription status. The backend derives an HMAC principal from the verified original transaction identifier, then corroborates only the current Apple-verified transaction ID/environment through RevenueCat API v2. No RevenueCat App User ID or raw JWS is sent to RevenueCat.
- Paid users receive 10 fresh estimates per rolling 24 hours, an in-app warning at 2 remaining, and an immutable server maximum of 15. Trial and sandbox users receive 5 fresh estimates per rolling 24 hours and 25 lifetime. Exact local/server cache hits, manual entry, and barcode lookup consume no AI quota.
- Monthly controls are `$15` alert, `$20` degraded, and `$25` disabled. Structured server results cache for 24 hours. The current non-ZDR Gemini posture permits request-content retention for up to 55 days.
- The required App Privacy/policy posture is user-confirmed photo upload to Google Gemini for purpose-limited analysis, no raw-image retention on the proxy, local-only reviewed nutrition storage, server-metered limits, and continued barcode/manual fallbacks.
- Repeat-meal review screenshots are captured in Botanical Journal and Lunar Calm at accessibility XXXL. App Review copy must state that an exact previously reviewed meal can be reused locally or deliberately scanned as new.
- Those local screenshots are implementation evidence only. Final App Store screenshots, the distribution profile, RevenueCat verification, benchmark result, and archive remain incomplete.
- Exact staged release notes and replacement description paragraphs for `en-US`, `de-DE`, `fr-FR`, `it`, `ja`, `ko`, and `nl-NL` are in `docs/app_store_1.0.5_localized_metadata.md`; none have been entered in App Store Connect.
