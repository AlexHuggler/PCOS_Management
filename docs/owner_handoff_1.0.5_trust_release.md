# 1.0.5 trust release: owner actions (App Store Connect, website, repo)

Status: engineering work for the scanner-hidden 1.0.5 (18) trust release lives on branch `codex/1.0.5-trust-release` (pushed to origin). Everything below needs the account owner and cannot be done from the codebase.

## App Store Connect (before uploading build 18)

1. **App Privacy labels.** Reconcile to the first-pass guidance in `docs/app_store_connect_first_pass_2026-06-22.md`: health, symptom, cycle and photo data are processed on device and are not "collected". Declare only **Purchase History** (App Functionality, not linked to identity beyond the pseudonymous StoreKit/RevenueCat ID) and **Other Data Types** (barcode sent to Open Food Facts). Remove Health, Fitness, Photos/Videos, User ID and Product Interaction until the scanner ships. Engineering keeps `PrivacyInfo.xcprivacy` and `PrivacyManifestTests` in sync once you confirm the final answers.
2. **Store description (all 7 localizations).** Replace the absolute paragraph ("No accounts required, no cloud uploads, no ads.") with the qualified paragraph already drafted in `docs/app_store_1.0.5_localized_metadata.md` (local-first by default; optional barcode lookup sends only the UPC; purchases via Apple/RevenueCat). Remove the "photo-based meal estimates are marked as coming soon" line from What's New. Do not describe Photo Estimate until its gates pass.
3. **App Review notes.** Delete the Apple Ads attribution sentence (the token capture was removed from the binary) and state that the build does not initialize Firebase unless the scanner is enabled (it is not in 1.0.5).
4. **Pricing.** The live tier is $6.99/month and $39.99/year. The repo now matches it. If you want a different tier, change App Store Connect first and tell engineering to mirror it.
5. **Introductory offer (recommended, Tranche 2).** Add a 7-day free trial on the annual product; the paywall will render trial eligibility once the RevenueCat offering carries it.
6. **Export compliance.** `ITSAppUsesNonExemptEncryption = false` is now in both Info.plists, so the upload dialog will stop asking.

## Website (cyclebalance.app)

- Fix the trial-quota sentence on `/privacy` and `/terms` (records are durable, not 30-day).
- Add "Photo Estimate is not yet available in the current App Store version" (or move Gemini text under an "upcoming" heading) until the scanner ships.
- Third-party list: mention Firebase App Check (Google) only for the meal-photo proxy, and drop Apple Ads attribution.

## Repository

- `codex/cyclebalance-1.0.5-rc` and `codex/1.0.5-trust-release` are pushed. When the trust release is accepted, merge `codex/1.0.5-trust-release` into the RC branch (or make it the app's default branch) and delete the stale worktrees `cyclebalance-1.0.5-ui-reconcile`, `ios-release-fixes`, `rc-security-fixes`; the 41 uncommitted files in the main `PCOS_Management` checkout are older scanner work already superseded by the RC and can be discarded.
- `.github/workflows/ios-ci.yml` triggers on `main`, which is the website lineage; point it at the app branch and add `-disableAutomaticPackageResolution -skipPackageUpdates` to the test step.

## Verification the owner can run

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -disableAutomaticPackageResolution -skipPackageUpdates test -only-testing:PCOSTests
```

Then `xcrun simctl launch booted alex.PCOS UITestMode -uiTest.demoScenario symptomManagement -appearance.themeOption lunarCalm` and screenshot Today, Insights, Track > Supplements (add sheet), and Settings > Subscription to review the visible changes.
