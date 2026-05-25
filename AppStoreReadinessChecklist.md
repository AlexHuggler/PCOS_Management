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

## Manual App Store Connect Follow-Up

- Confirm the app record uses the final localized app name, subtitle, keywords, and promotional text for each storefront you plan to ship.
- Complete the App Privacy questionnaire with the current runtime behavior and any third-party SDK disclosures.
- Upload the current privacy policy URL, support URL, and marketing URL if required.
- Prepare localized screenshots for iPhone form factors that match the supported in-app locales.
- Add reviewer notes covering HealthKit read-only behavior, optional permissions, and any demo/test credentials if needed.
- Verify App Store Connect subscription localizations and RevenueCat offering/package metadata stay in sync with the in-app paywall copy and pricing plan names.
- Capture locale-specific paywall screenshots that match the final subscription naming and legal-link layout for each shipped localization.
- Confirm age rating, content rights, export compliance, and Sign in with Apple requirements are accurate for this build.

## Recommended Final Smoke Checks

- Launch a fresh install with `app.language = system` under each supported locale and walk onboarding through completion.
- Trigger the camera and HealthKit permission prompts in at least one non-English locale and confirm the system sheets use localized `InfoPlist.strings`.
- Open paywall, settings, calendar, track, insights, and pregnancy/postpartum surfaces in at least one Latin-script locale and one CJK locale.
- Validate restore purchases, privacy policy, and terms links from the paywall before submission.
