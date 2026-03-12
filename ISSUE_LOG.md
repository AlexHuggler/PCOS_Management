# PCOS Issue Log

Audit date: 2026-03-11  
Evidence refresh run date: 2026-03-12  
Scope: current dirty working tree (`PCOS/PCOS`, `PCOS/PCOSTests`, `PCOS/PCOSUITests`) with parity mirror context in `CycleBalance`.

Severity policy:
- Critical: crash, data loss, or guaranteed App Store rejection
- High: likely App Review / performance / UX risk
- Medium: maintainability and quality debt with lower immediate user impact

## Critical (Open)

No open Critical findings.

Critical queue status: **empty** after closing C-ICON-1 in this cycle. Per workflow, pause at this boundary before beginning High-item remediation.

## High (Open)

No open High findings.

## Medium (Open)

No open Medium findings.

## Medium Remediation Cycle (Completed This Pass)

### M-5. Long-lived observer tasks lacked explicit teardown hooks -- RESOLVED (2026-03-12)

- Category: Memory safety
- Before:
  - `PremiumStateBridge` did not expose an explicit stop hook and had no deinit teardown for its notification observer task.
  - `SubscriptionManager` started an entitlement listener task without an explicit lifecycle stop method and used a strong self-locking listener loop pattern.
- After:
  - `PremiumStateBridge` now exposes idempotent `stop()` and explicit teardown via deinit:
    - `PCOS/PCOS/Core/StoreKit/PremiumStateBridge.swift:20`
    - `PCOS/PCOS/Core/StoreKit/PremiumStateBridge.swift:37-39`
  - Root app shell now invokes bridge lifecycle stop on disappearance:
    - `PCOS/PCOS/App/ContentView.swift:53-55`
  - `SubscriptionManager` now exposes idempotent `stopEntitlementListener()` and teardown via deinit:
    - `PCOS/PCOS/Core/StoreKit/SubscriptionManager.swift:67-69`
    - `PCOS/PCOS/Core/StoreKit/SubscriptionManager.swift:172-174`
  - Entitlement listener loop now consumes `billingClient` without `self.billingClient` strong-loop capture pattern:
    - `PCOS/PCOS/Core/StoreKit/SubscriptionManager.swift:188-193`
  - Added M-5 guardrail and behavior coverage in both test trees:
    - `PCOS/PCOSTests/SilentFailureRegressionTests.swift:114-146`
    - `CycleBalanceTests/SilentFailureRegressionTests.swift:114-146`
    - `PCOS/PCOSTests/PremiumStateBridgeTests.swift:52-81`
    - `CycleBalanceTests/PremiumStateBridgeTests.swift:52-81`
    - `PCOS/PCOSTests/SubscriptionManagerTests.swift:166-196`
    - `CycleBalanceTests/SubscriptionManagerTests.swift:166-196`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/StoreKitLifecycleRegressionTests test`
    - Failure assertions: missing `stop` hooks and `self.billingClient` listener-loop capture pattern.
  - Post-fix focused run passed:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/StoreKitLifecycleRegressionTests -only-testing:PCOSTests/PremiumStateBridgeTests -only-testing:PCOSTests/SubscriptionManagerTests test` (`17 tests in 3 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`223 tests in 43 suites passed`, plus UI tests).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### M-4. `InsightEngine` responsibility split into focused internal components -- RESOLVED (2026-03-12)

- Category: Protocol/object design
- Before:
  - `InsightEngine` mixed coordinator orchestration, SwiftData fetch helper logic, all analyzer domain logic, and dedup/cleanup concerns in one large unit.
  - This concentration increased review surface and made behavior-preserving changes riskier.
- After:
  - Coordinator/public API remained stable:
    - `InsightGenerating` and `generateInsights() throws -> [Insight]` are unchanged:
      - `PCOS/PCOS/Core/ML/InsightEngine.swift:6-7`
      - `PCOS/PCOS/Core/ML/InsightEngine.swift:54`
  - `InsightEngine` now delegates to focused internal components:
    - `InsightDataFetcher` (`PCOS/PCOS/Core/ML/InsightEngine.swift:90`)
    - `InsightDeduplicator` (`PCOS/PCOS/Core/ML/InsightEngine.swift:109`)
    - `CyclePatternInsightAnalyzer` (`PCOS/PCOS/Core/ML/InsightEngine.swift:186`)
    - `SymptomCorrelationInsightAnalyzer` (`PCOS/PCOS/Core/ML/InsightEngine.swift:291`)
    - `SupplementEfficacyInsightAnalyzer` (`PCOS/PCOS/Core/ML/InsightEngine.swift:475`)
    - `DietImpactInsightAnalyzer` (`PCOS/PCOS/Core/ML/InsightEngine.swift:571`)
    - `SleepActivityInsightAnalyzer` (`PCOS/PCOS/Core/ML/InsightEngine.swift:692`)
  - Added architecture guardrails in both test trees:
    - `PCOS/PCOSTests/SilentFailureRegressionTests.swift:96-126`
    - `CycleBalanceTests/SilentFailureRegressionTests.swift:96-126`
  - Updated insight dedup test seam usage in both test trees:
    - `PCOS/PCOSTests/InsightEngineTests.swift:82-83`
    - `CycleBalanceTests/InsightEngineTests.swift:82-83`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/InsightArchitectureRegressionTests test`
    - Failure assertions: coordinator still contained analyzer/fetch helper bodies before split.
  - Post-fix focused run passed:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/InsightArchitectureRegressionTests -only-testing:PCOSTests/InsightEngineTests -only-testing:PCOSTests/InsightErrorHandlingRegressionTests -only-testing:PCOSTests/InsightsViewModelErrorPropagationTests test` (`19 tests in 4 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### M-3. Dynamic Type resilience gaps in supplement history, blood sugar history, and calendar offsets -- RESOLVED (2026-03-12)

- Category: Interface resilience
- Before:
  - Supplement adherence rings used fixed `120x120` sizing, blood sugar history used a fixed `70pt` time column, and calendar blank offsets used fixed `44pt` height.
  - These fixed dimensions risk clipping/crowding at large Dynamic Type sizes and narrow split-screen widths.
- After:
  - Supplement history now uses scaled, clamped ring sizing:
    - `PCOS/PCOS/Features/Supplements/Views/SupplementHistoryView.swift:6`
    - `PCOS/PCOS/Features/Supplements/Views/SupplementHistoryView.swift:76`
    - `PCOS/PCOS/Features/Supplements/Views/SupplementHistoryView.swift:85`
    - `PCOS/PCOS/Features/Supplements/Views/SupplementHistoryView.swift:138`
  - Blood sugar time column now uses adaptive single-line width behavior (`minWidth` + `idealWidth` + scale factor):
    - `PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift:6`
    - `PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift:72`
    - `PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift:73`
  - Calendar blank-offset cells now use minimum height behavior (`minHeight: 44`) instead of rigid fixed height:
    - `PCOS/PCOS/Features/Cycle/Views/CalendarMonthView.swift:137`
  - Parity mirrors were applied to matching `CycleBalance` files.
  - Added/updated M-3 guardrails in both test trees:
    - `PCOS/PCOSTests/InterfaceResilienceTests.swift:47-77`
    - `CycleBalanceTests/InterfaceResilienceTests.swift:47-77`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/InterfaceResilienceTests test`
    - Failure assertions targeted fixed-size hotspots (`120x120` rings, `width: 70`, `height: 44`).
  - Post-fix focused run passed with same command (`4 tests in 1 suite passed`).
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### M-2. Quick-log silent failure path in `TodayView` -- RESOLVED (2026-03-12)

- Category: Error handling
- Before:
  - Quick-log used a silent fallback fetch for undo-anchor lookup and suppressed quick-log save errors via empty catch behavior.
  - Users could lose quick-log actions without inline/error visibility in the quick-log row.
- After:
  - `CycleLogService.logPeriodDay` now returns the persisted entry identifier (`PersistentIdentifier`) and `CycleViewModel.logPeriodDay` now threads this return value:
    - `PCOS/PCOS/Features/Cycle/Models/CycleLogService.swift:16-35`
    - `PCOS/PCOS/Features/Cycle/ViewModels/CycleViewModel.swift:69-80`
  - `TodayView` quick-log now uses explicit `do/try/catch`, derives undo state from returned identifier, logs failures, and shows an inline non-modal error banner:
    - `PCOS/PCOS/Features/Cycle/Views/TodayView.swift:341-349`
    - `PCOS/PCOS/Features/Cycle/Views/TodayView.swift:376-399`
  - Added M-2 guardrail tests for no silent fetch fallback/no silent catch suppression in both test trees:
    - `PCOS/PCOSTests/SilentFailureRegressionTests.swift:184-208`
    - `CycleBalanceTests/SilentFailureRegressionTests.swift:184-208`
  - Added `CycleLogService` return-identifier behavior test in both test trees:
    - `PCOS/PCOSTests/CycleLogServiceTests.swift:58-76`
    - `CycleBalanceTests/CycleLogServiceTests.swift:58-76`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/SilentFailureRegressionTests test`
    - Failure assertions: silent undo-anchor fetch fallback and silent quick-log catch suppression.
  - Post-fix focused run passed:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/SilentFailureRegressionTests -only-testing:PCOSTests/CycleLogServiceTests test` (`18 tests in 2 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### M-1. Media import silent failures in photo-selection flows -- RESOLVED (2026-03-12)

- Category: Error handling
- Before:
  - Library photo imports in meal logging and photo journal flows used silent `try? await ...loadTransferable(...)` paths, which dropped import failures without user feedback.
- After:
  - Meal import handler now uses explicit `do/try/catch` and alerts on import failure while preserving existing form state:
    - `PCOS/PCOS/Features/Meals/Views/MealLogView.swift:208-220`
  - Photo journal import handler now uses explicit `do/try/catch` and alerts on import failure while preserving existing form state:
    - `PCOS/PCOS/Features/PhotoJournal/Views/PhotoCaptureView.swift:128-145`
  - Added source-guardrail tests for both handlers:
    - `PCOS/PCOSTests/SilentFailureRegressionTests.swift:140-164`
    - `CycleBalanceTests/SilentFailureRegressionTests.swift:140-164`
  - Mirrored parity updates were applied to matching `CycleBalance` view files.
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/SilentFailureRegressionTests test`
  - Post-fix focused run passed with same command (`11 tests in 1 suite passed`).
  - Focused regression pass:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/SilentFailureRegressionTests -only-testing:PCOSTests/MealViewModelTests -only-testing:PCOSTests/PhotoJournalViewModelTests test` (`27 tests in 3 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

## High Remediation Cycle (Completed This Pass)

### H-3. HealthKit full-sync main-actor isolation risk -- RESOLVED (2026-03-12)

- Category: Modern concurrency
- Before:
  - `HealthKitManager` (main-actor isolated) contained direct sync orchestration that mixed UI-state coordination with persistence-heavy full-sync logic.
  - Sync boundary did not enforce delegation away from manager-owned code paths.
- After:
  - Introduced off-main actor worker extraction:
    - `HealthKitSyncWorker` actor with worker-owned `ModelContext` for fetch/upsert paths:
      - `PCOS/PCOS/Core/HealthKit/HealthKitSyncWorker.swift:16`
      - `PCOS/PCOS/Core/HealthKit/HealthKitSyncWorker.swift:47-76`
      - `PCOS/PCOS/Core/HealthKit/HealthKitSyncWorker.swift:80-185`
  - `HealthKitManager` now acts as UI coordinator with injected sync operation seam and delegates full-sync execution:
    - `PCOS/PCOS/Core/HealthKit/HealthKitManager.swift:14`
    - `PCOS/PCOS/Core/HealthKit/HealthKitManager.swift:57-84`
    - `PCOS/PCOS/Core/HealthKit/HealthKitManager.swift:119-140`
  - Mirrored parity implementation in canonical tree:
    - `CycleBalance/Core/HealthKit/HealthKitManager.swift`
    - `CycleBalance/Core/HealthKit/HealthKitSyncWorker.swift`
  - Added/updated guardrail + behavior coverage in both test trees:
    - `PCOS/PCOSTests/HealthKitManagerTests.swift:348-363`
    - `PCOS/PCOSTests/HealthKitManagerTests.swift:192-345`
    - `CycleBalanceTests/HealthKitManagerTests.swift:348-363`
    - `CycleBalanceTests/HealthKitManagerTests.swift:192-345`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected (delegation boundary guardrail):
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/HealthKitSyncConcurrencyRegressionTests test`
  - Post-fix focused run passed:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/HealthKitSyncConcurrencyRegressionTests -only-testing:PCOSTests/HealthKitManagerTests -only-testing:PCOSTests/HealthKitSyncWorkerTests test` (`15 tests in 3 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### H-2. Insight generation silent fetch failures -- RESOLVED (2026-03-12)

- Category: Error handling
- Before:
  - `InsightEngine` used silent SwiftData fetch fallbacks `(try? modelContext.fetch(...)) ?? []` in analyzer paths, which made persistence failures look like "no data/no insights".
  - `InsightsViewModel` had no dedicated error state for generation failures, so UI could not show an explicit inline failure state.
- After:
  - `InsightEngine.generateInsights` now throws and engine fetches use fail-fast stage-aware typed errors via `InsightDataFetcher.fetch(...)`:
    - `PCOS/PCOS/Core/ML/InsightEngine.swift:6-29`
    - `PCOS/PCOS/Core/ML/InsightEngine.swift:54-79`
    - `PCOS/PCOS/Core/ML/InsightEngine.swift:90-103`
  - `InsightsViewModel` now exposes `errorMessage`, wraps refresh in `do/try/catch`, and rolls back on failure:
    - `PCOS/PCOS/Features/Insights/ViewModels/InsightsViewModel.swift:15`
    - `PCOS/PCOS/Features/Insights/ViewModels/InsightsViewModel.swift:31-49`
  - `InsightsView` now renders an inline error banner when `errorMessage` is set:
    - `PCOS/PCOS/Features/Insights/Views/InsightsView.swift:14-23`
  - Parity mirror updates were applied for matching CycleBalance files and tests.
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed as expected (silent fallback guardrail):
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/InsightErrorHandlingRegressionTests test`
  - Post-fix focused run passed:
    - `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/InsightErrorHandlingRegressionTests -only-testing:PCOSTests/InsightsViewModelErrorPropagationTests -only-testing:PCOSTests/InsightEngineTests test` (`18 tests in 3 suites passed`)
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).

### H-1. `UIBackgroundModes` remote-notification mismatch -- RESOLVED (2026-03-12)

- Category: App Store rejection risk
- Before:
  - App metadata declared `UIBackgroundModes = remote-notification` in the active app plist (March 11 snapshot), but app code only implemented local notification flows.
  - This created a metadata/implementation mismatch for background push capability claims.
- After:
  - Removed `UIBackgroundModes` / `remote-notification` declaration from `PCOS/PCOS/Info.plist`.
  - Added parity test coverage in both test trees:
    - `PCOS/PCOSTests/PrivacyManifestTests.swift:85-107`
    - `CycleBalanceTests/PrivacyManifestTests.swift:85-107`
  - Current plist evidence shows no `UIBackgroundModes` entry: `PCOS/PCOS/Info.plist:39-45`.
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed: `xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:PCOSTests/AppStoreConfigTests test`
  - Post-fix focused run passed with same command.
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator regression gate passed (`TEST SUCCEEDED`).
  - Release no-sign build gate passed (`BUILD SUCCEEDED`).
  - Built release metadata sanity check passed: release `PCOS.app/Info.plist` no longer declares `UIBackgroundModes` and retains icon metadata.

## Critical Remediation Cycle (Completed This Pass)

### C-ICON-1. Missing App Icon image assets in active icon set -- RESOLVED (2026-03-11)

- Category: App Store rejection risk
- Before:
  - Active `AppIcon.appiconset/Contents.json` did not map required image entries to concrete files.
  - No concrete icon PNGs were present for required default/dark/tinted variants.
- After:
  - Added production-valid temporary icon files in active and mirror trees:
    - `appicon-default-1024.png`
    - `appicon-dark-1024.png`
    - `appicon-tinted-1024.png`
  - Wired filenames in both icon manifests:
    - `PCOS/PCOS/Assets.xcassets/AppIcon.appiconset/Contents.json:4`, `:16`, `:28`
    - `CycleBalance/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
  - Added resource validation test suite in both trees:
    - `PCOS/PCOSTests/PrivacyManifestTests.swift:45-83`
    - `CycleBalanceTests/PrivacyManifestTests.swift:45-83`
- Test-first sequence and verification evidence:
  - Pre-fix focused run failed on missing `filename` entries in app icon manifest assertions.
  - Post-fix focused resource gate passed.
  - Parity gate passed: `./scripts/check_tree_parity.sh`.
  - Full simulator test gate passed (`TEST SUCCEEDED`).
  - Release no-sign build passed (`BUILD SUCCEEDED`).
  - Built artifact checks passed:
    - release `Info.plist` includes `CFBundleIcons` + `CFBundleIconName = AppIcon`
    - release `Assets.car` contains `AppIcon` icon-image renditions via `assetutil`.

## Open Findings Summary

| Severity | Open |
|---|---:|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Total | 0 |

Step 3 queue seed (next after approval): **empty** (all currently logged findings resolved).
