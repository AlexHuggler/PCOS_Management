# RevenueCat Premium QA Runbook

## Scope
- Validate premium purchase, entitlement, and restore behavior using the RevenueCat-backed paywall.
- Validate demo data import flows used for premium feature demos.

## Required Setup
1. Open `PCOS.xcodeproj` from the repo root.
2. Select scheme `PCOS`.
3. The shared `PCOS` scheme defaults the billing backend to RevenueCat via `-billing.backendMode revenuecat` and does not use the local Xcode StoreKit configuration.
4. Confirm run destination is an iOS Simulator or a signed device build with network access.
5. Verify `Config/LocalSecrets.xcconfig` contains a valid `REVENUECAT_PUBLIC_SDK_KEY`.
6. Confirm the relevant App Store Connect in-app purchase products and the `default` offering are fully configured and no RevenueCat dashboard warnings report `MISSING_METADATA`.

## Local Xcode Recovery
1. Close Xcode completely.
2. From the repo root, run `./scripts/open_pcos_xcode.sh`.
3. Confirm the active project is the root `PCOS.xcodeproj`.
4. In `Edit Scheme... > Run > Options`, verify `StoreKit Configuration` is `None`.
5. If `PCOS.storekit` still appears, delete local Xcode project state and reopen:
   - `PCOS.xcodeproj/xcuserdata/<user>.xcuserdatad`
   - `PCOS.xcodeproj/project.xcworkspace/xcuserdata/<user>.xcuserdatad`
6. Reopen the root project and re-check the shared `PCOS` scheme before testing purchases.

## Premium QA Flow
1. Launch app and complete onboarding, or use an existing profile.
2. Open `Settings > Debug: Premium QA`.
3. Verify `Entitlement` starts as `Free tier`.
4. Tap `Open Paywall`.
5. Confirm the RevenueCat paywall loads for offering `default`.
6. Buy either the monthly or annual product.
7. Do not use an `[Environment: Xcode]` purchase prompt for this shared scheme; that indicates a local StoreKit purchase path rather than the supported RevenueCat QA flow.
8. Verify the paywall dismisses automatically after the purchase completes.
9. Return to `Settings > Debug: Premium QA` and tap `Refresh Premium Status`.
10. Verify:
   - `Entitlement` becomes `Premium active`.
   - `Product IDs` includes the active purchased product.
   - Premium-gated screens are unlocked.

## Restore QA Flow
1. Launch the app on a profile with a previously purchased subscription.
2. Open the paywall from `Settings` or a premium gate.
3. Trigger restore from the RevenueCat paywall.
4. Verify the paywall dismisses after restore and premium-gated screens unlock.
5. Relaunch the app and confirm `Settings > Debug: Premium QA` still shows `Premium active`.

## Demo Data QA Flow
1. Open `Settings > Debug: Demo Data`.
2. Pick one scenario:
   - `Load Newly Diagnosed`
   - `Load Symptom Management`
   - `Load TTC / Fertility`
3. Confirm import replacement prompt and complete import.
4. Verify `Last Import` appears with record count and schema version.
5. Validate data rendering:
   - `Today` shows populated cycle and symptom context.
   - `Calendar` displays irregular period spacing.
   - `Insights` has pre-populated cards.
   - `Track` flows show historical records.

## Backup Import/Export QA
1. In `Settings > Data`, tap `Export Backup (JSON)` and then `Share JSON Backup`.
2. Tap `Delete All Data`.
3. Tap `Import Backup (JSON)` and select the exported file.
4. Confirm replacement prompt.
5. Verify data is restored and `Last Import` updates.

## Expected Safety Rules
- Import is replace-all only.
- Demo scenario loading is debug-only.
- CSV remains report-oriented export; JSON is canonical backup and restore format.
- If RevenueCat reports `MISSING_METADATA`, stop and fix App Store Connect before treating the build as review-ready.
