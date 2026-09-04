# CycleBalance: current state and the path to broadest PCOS-niche adoption

## Context

CycleBalance (iOS, SwiftUI + SwiftData, Swift 6, iOS 17+, RevenueCat, read-only HealthKit) is live on the App Store as **1.0.4 (build 17), released 2026-07-04**. The owner asked for a review of the project's current state and the improvements and fixes that would most increase adoption within the PCOS niche.

Facts verified 2026-09-03 against the repo and the live listing:

- **Canonical code is the `cyclebalance-1.0.5-rc` worktree** (`PCOS_Management/.worktrees/cyclebalance-1.0.5-rc`, branch `codex/cyclebalance-1.0.5-rc`, last commit 2026-07-17). It already contains the `ui-reconcile`, `ios-release-fixes`, and `rc-security-fixes` branch work. The **main checkout** (`PCOS_Management/`, branch `codex/dirty-tree-reconcile-20260312`) is stale with ~41 uncommitted files of older scanner work the RC superseded.
- **Every commit since 2026-07-03 (68 commits) exists on no remote.** Last fetch was 2026-05-10. `origin/main` is the website lineage, so the app CI workflow has never run.
- **1.0.5 (18)** adds a server-metered Gemini "Photo Estimate" meal scanner, fail-closed and hidden in Release until self-imposed gates pass. Not uploaded. No commits in 7 weeks.
- Live listing: 5.0 stars from **2 ratings**, Premium **$6.99/month, $39.99/year** (the repo's StoreKit config still says 9.99/79.99), description still says "No accounts required, no cloud uploads, no ads.", What's New still says photo estimates are "coming soon". 7 locales (en, de, fr, it, ja, ko, nl); no Spanish, Portuguese, or Hindi.
- Build/test baseline of the RC: Debug and Release builds succeed with 0 Swift warnings; **759 unit tests in 83 suites pass**.
- No analytics/crash SDK, no widgets, Watch, App Intents, deep links, or Live Activities; iPhone only; HealthKit read-only; no free trial.

## Audit coverage and how findings were verified

Eleven read-only lenses ran as subagents against the RC (daily loop, PCOS clinical coverage, persistence, monetization, onboarding, market research, build/test baseline, platform growth, cycle engine, App Store compliance, accessibility/localization). Session token limits prevented dedicated security and architecture lenses; those areas are partially covered by the persistence lens and by direct greps (0 `try!`, 0 `as!`, no health values in logs, no file-protection attributes, 5 `fatalError` sites in container startup, no crash reporting). I spot-checked 35+ claims directly in source; every one held. Items marked "(agent)" in the appendix were not independently re-read but carry file:line evidence.

## Honest assessment

The foundation is unusually strong for an indie health app: honest uncertainty-gated predictions, a phase-inference policy that refuses to fake phases for long cycles, a real pregnancy/postpartum lifecycle, cited evidence sheets, 7 locales, clean billing plumbing, a passing 759-test suite, and a store that never depends on iCloud. The gap is not features. It is that (1) the work of the last two months sits unpushed while the live app has known trust defects, (2) the daily loop never pays off for the PCOS user it targets (first free insight needs a perfect 14-day streak or ~6 months of cycles; Today shows fabricated "Mood: Calm" and a fake trend chart), (3) a PCOS user with no period for 70 days sees "Cycle day 70" with no acknowledgement and cannot even record "no period", (4) several clinically wrong details (Vitamin D "2000 mg", weight in "lb" for kg data, mg/dL-only glucose in mmol/L markets) undermine the evidence-based positioning with exactly the dietitians and endocrinologists who drive word of mouth, and (5) the two things PCOS-specific competitors and users name first (medication and lab tracking) are absent.

## Progress log (2026-09-04, branch `codex/1.0.5-trust-release` in the RC worktree, pushed to origin)

Landed with TDD (RED observed, then GREEN, full unit suite green before each commit):

- `b7eaddb` drop stale export artifacts so the worktree matches a commit
- `317f8c1` ITSAppUsesNonExemptEncryption; scanner-gated camera/photo prompts (+6 locales); Firebase configured only when the scanner can run; App Check provider throws instead of trapping
- `38d5a16` remove unused AdServices attribution capture (+ guardrail test, docs)
- `85db04b` Insights dashboard drawn from real data only (placeholders below thresholds); Today snapshot "Not logged"
- `4f1895d` supplement dose units (IU/mcg/mg/g/cup) end to end incl. backup/CSV, unit picker, demo fixture; marker-gated fixture regeneration
- `675638a` localization: 555 missing keys merged (fr/it +95, ja/ko/nl +112, de +29), table-parity test, locale keeps device region
- In flight (chained): trust copy/pregnancy/glucose guardrails; weight units + energy/weight in check-in; paywall renewal terms/EULA/per-month/manage-subscriptions + live-tier prices; data-safety net (backup v6 parity, pre-import snapshots + restore, portable photos, tmp cleanup, delete-all rollback)

Deferred to Tranche 2 (not started): HealthKit glucose provenance (needs UUID-bearing glucose fetcher), VersionedSchema + recovery sheet, owner App Store Connect/website actions (handoff drafted).

## Recommended approach: three tranches across three releases

### Tranche 1: secure the work and ship 1.0.5 as a scanner-hidden trust release (target: 2 to 3 weeks)

Do this before anything else. The scanner stays hidden exactly as the RC already builds it; its gates (benchmark, canary, TestFlight JWS, Cloud Run) move to 1.1.

1. **Repository safety (owner + engineering, S).** Push `codex/cyclebalance-1.0.5-rc` to origin today. Then: make the RC branch the app's default branch (or an `app/main` branch), retire the stale main checkout (verify its 41 dirty files against the RC, then discard), delete the merged `ui-reconcile` / `ios-release-fixes` / `rc-security-fixes` worktrees, and point `.github/workflows/ios-ci.yml` at the app branch with `-disableAutomaticPackageResolution -skipPackageUpdates` on the test step. Refresh `ISSUE_LOG.md` from this plan.
2. **Apple-required release items (S).** Add `ITSAppUsesNonExemptEncryption = false` to `PCOS/PCOS/Info.plist` and `Info.Release.plist`. Make the camera and photo usage strings conditional on `MEAL_SCAN_RELEASE_UI_ENABLED` in `Info.Release.plist` and the six `InfoPlist.strings` so a hidden-scanner build mentions only barcodes and hair/skin photos. Gate `configureFirebase()` in `App/CycleBalanceApp.swift:92` behind the scanner flag. Decide what to do with the unused AdServices token capture (`CycleBalanceApp.swift:94`): remove it or wire it to RevenueCat.
3. **Store metadata and privacy label (owner, S).** Replace the "no cloud uploads" absolute and the "coming soon" line in all 7 localizations with the qualified paragraph already drafted in `docs/app_store_1.0.5_localized_metadata.md`. Reconcile App Privacy to the first-pass guidance (`docs/app_store_connect_first_pass_2026-06-22.md`): on-device health data is not "collected"; declare Purchase History and Other Data only, and trim `PCOS/PCOS/PrivacyInfo.xcprivacy` plus the assertion in `PCOSTests/PrivacyManifestTests.swift` to match. Fix the 30-day vs durable-ledger sentence on the live privacy page and mark Photo Estimate as not yet available.
4. **Trust defects on the most-viewed screens (S each).**
   - Remove fabricated values: `Features/Insights/Views/InsightsView.swift` fallback arrays at 549/923/1288, static "Feb…Jul" labels at 864, invented percentages at 1178 (show a labelled "not enough data" placeholder below 3 insights; derive labels from `generatedDate`); `Features/Cycle/Views/TodayView.swift:751-768` mood/energy fallbacks become "Not logged" and tap into the logger.
   - Supplement dose units: add a `DosageUnit` (mg, mcg, IU, g, cups) to `PCOSSupplement` and `SupplementLog` (lightweight migration, default mg), fix presets in `Features/Supplements/Models/PCOSSupplements.swift:37,142,157`, render `"\(dose) \(unit)"` at `SupplementLogView.swift:401,527,571` and in CSV/JSON export.
   - Weight: store kg, format with `Measurement<UnitMass>` and locale on `TodayView.swift:1457`; fix `App/DemoDataBuilder.swift:385` seeds; add an optional weight field to the daily check-in.
   - Pregnancy: pass `appState.lifecycleMode` into every `generateInsights()` call (`InsightsViewModel.swift:32,273`, `CycleBalanceApp.swift:697`) and add a test that `.pregnant` yields no cycle/forecast insights; branch `PregnancyViewModel.endPregnancyMode` (line 133-148) so `.loss`/`.other` do not produce "Postpartum – Day N / log your first period" copy; add a `pregnancySafety` flag to the supplement catalog with a caution banner when pregnant.
   - Copy truth: "After 2 cycles" (`Features/Onboarding/Views/YourPlanView.swift:78`) becomes a threshold-driven, goal-aware sentence sharing constants with the analyzers; drop "growing community of women" (`OnboardingCompletionView.swift:155,157`, `SocialProofView.swift:90`) for a promise the app keeps and gender-neutral wording; rename "Insulin Resistance Indicators" to "Glucose patterns" and route its phase split through `CyclePhaseInferencePolicy`.
   - Localization gaps: translate the 83 keys missing in ja/ko/nl and 66 in fr/it (Today copy first: "Are you bleeding today?", "Cycle day %lld"), add the 22 bare `Text("…")` literals to all tables, and add a full-parity test in `PCOSTests/LocalizationResourceTests.swift`. Build the render locale from language plus device region in `Core/LocalizationSupport.swift:376-393` instead of pinning `en_US`.
5. **Data-safety net (S to M).** Add `painLevel0To10`, `privateNote`, `positiveActionRawValues` to `DailyLogRecord` (`App/SettingsDataBackupSchema.swift:382-392`, schema v6) with a `Mirror`-based DTO parity test; write an automatic pre-import snapshot before `clearAllTrackedModels()` (`App/SettingsDataImportService.swift:148-152`) and offer undo; make backups self-contained by decrypting photo bytes on export and re-encrypting on import (`Core/Services/PhotoEncryptionService.swift:83` key is `ThisDeviceOnly`); delete tmp export files after the share sheet; `rollback()` in the delete-all catch and state full scope in its alert; add `HealthKitImportedSampleRecord` provenance for glucose samples (`Core/HealthKit/HealthKitSyncWorker.swift:366-393`); freeze the shipped models as `SchemaV1: VersionedSchema` with a one-stage `SchemaMigrationPlan`, and show a recovery sheet when `local_only_after_reset` is recorded.
6. **Paywall compliance (S).** Add the localized auto-renew/cancel sentence and an Apple standard EULA link to `Core/StoreKit/PaywallView.swift` footer; show annual as "39.99 / year (3.33 / month)"; route the Settings "Subscription" row (`App/SettingsView.swift:190-200`) to a manage-subscription screen when `isPremium`. Reconcile `StoreKit/PCOS.storekit` and the readiness checklist to the live $6.99/$39.99 tier (or correct App Store Connect if the live tier is unintended).

### Tranche 2: make the daily loop pay off and cut activation friction (1.0.6, target: 4 to 6 weeks after 1.0.5)

7. **First free insight within a week (S + M).** Widen `Core/ML/InsightSymptomCorrelationAnalyzer.swift:12-24` to a 90-day fetch requiring 14 distinct days, and drive `fetchDataReadiness` and the planner copy from the same constant. Add a free `StarterInsightAnalyzer` (days logged, top symptom this week with severity direction, cycle-day context for long cycles, countdown to the next threshold) and rank it into `AhaMomentService.topMoment` ahead of the static starter (`Core/Services/NutritionIntegrationServices.swift:544-558`). Add a `WeeklyRecapService` card on Today from day 2, plus an optional Sunday recap notification. Surface the newest persisted `Insight` on Today and badge the tab.
8. **Notifications that actually fire (S to M).** Call `schedulePeriodPredictionReminder` from `CycleViewModel.updatePrediction()` when the prediction is actionable (today it has zero callers). Fix the cancel-then-add ordering in `Core/Notifications/NotificationManager.swift:147-176,290-302` by awaiting removal before `add` (add a test with an injected center). Add `AppNotificationRoute.symptomLog`/`.periodLog`, schedule the daily reminder as non-repeating next-day requests suppressed when today already has a log, and offer the time picker at onboarding completion.
9. **Long-cycle honesty (M).** Add an `.overdue(daysLate:)` prediction presentation once `now > latestDate` (`Features/Cycle/ViewModels/CycleViewModel.swift:319-336`, `TodayView.swift:635-668`) with supportive copy and no calendar shading of past predicted days. Let "No period today" work without an open cycle by creating a provisional cycle from an approximate last-period date (`Features/Cycle/Models/CycleLogService.swift:189-200`). Ship a "No period this cycle" action that marks the open cycle anovulatory/skipped instead of the unwired, unsafe `logSkippedPeriod`. Cycle-engine fixes: attach back-dated entries to the containing closed cycle instead of rewriting boundaries (`CycleLogService.swift:729-748`); exclude spotting-only days from the 10-day gap anchor and new-cycle detection (`CycleLogService.swift:126-141,313,422,488`); fence completed lengths to 15…120 days in `CyclePredictionEngine.swift:37,96-111`; wire `predictNextPeriodPostpartum` (currently dead code); anchor phase buckets to expected length in `Core/Services/CyclePhaseInferencePolicy.swift:72-77`.
10. **Onboarding: 13 pages to about 5 (M).** Reorder `OnboardingPhase` in `Features/Onboarding/Views/OnboardingContainerView.swift:274-287` to welcome+language, 3-question quiz, last-period seed, first log, Apple Health (only), all set; move theme/font to Settings; drop results/how-it-helps/social-proof/health-context fallback quiz (its two answers are never stored, `OnboardingHealthContextRevealView.swift:13-14,187-199`); request camera in-context, not in `PermissionsStepView.swift:46-55`. Add a "My last period was a while ago / not sure" card to `GuidedActionView` that routes to the symptom logger and stores recency, and a two-field last-period-date / usual-cycle-length step that seeds the first `Cycle`. Compute progress over available phases only.
11. **Conversion mechanics (S to M).** Add a 7-day introductory free trial on the annual product in App Store Connect and `PCOS.storekit`, model `introOffer` on `BillingProduct`, and render "7 days free, then …" with a "Start free trial" CTA. Add a `requiresPremium` flag to `LoggerShortcut` so locked Track/Today tiles show a lock chip before the tap, pass a feature-specific `PremiumPaywallReason`, and set `lastLoggerShortcut` only after the gate passes. Allow free users to log on any past date and gate only viewing beyond 90 days (`FreeTierPolicyService.swift:19-27`, `CalendarMonthView.swift:315-323`). Add one soft post-onboarding "free vs premium" moment with equal-weight "Continue free". Replace the blanket TestFlight premium override (`App/AppState.swift:152-161`) with an opt-in so testers can exercise purchase/restore/trial. Owner decision: move basic supplement logging (capped) into the free tier so the "supplement efficacy" teaser has data.
12. **Apple Health as the switching bridge (M).** On first authorization backfill 24 months of menstrual flow and group imported `CycleEntry` days into `Cycle` records through `CycleLogService.prepareTargetCycle` (`HealthKitSyncWorker.swift:210,230,545-570` today imports 7 days and never creates cycles); show "We found N cycles in Apple Health" in onboarding. Sync on foreground with a throttle and widen the window to cover the gap since `lastSyncDate`. Fix the review prompt so first PDF/photo cannot spend the single prompt (`Core/Services/ReviewPromptService.swift:72-79`), call it from the Today quick log, and count DailyLog/meal/supplement/glucose days in `Features/Cycle/Models/StreakService.swift`.

### Tranche 3: PCOS depth and growth (1.1 and 1.2)

13. **Medications and labs (L, the largest PCOS-specific gap).** Generalize supplements into a "Medications & supplements" regimen (`Medication` model: name from a curated PCOS list, dose + unit, schedule, class incl. hormonal contraception, start/stop, reminders, daily taken/missed) and add a `LabResult` model (curated PCOS panel with SI and conventional units, date, reference range) with a trend list and a Labs section in the PDF. Derive an `isOnHormonalContraception` flag that suppresses regularity praise and forecasts. Keep basic medication logging free.
14. **Clinical coverage (M).** Add a glucose unit preference (mmol/L default by region, mg/dL canonical storage, validator 2.2…33.3) across `Features/BloodSugar`, `InsulinResistanceMetricService`, charts and PDF; add ~8 guideline-aligned symptoms (sleep quality, brain fog, libido, night sweats, heavy/prolonged bleeding, dark patches, joint pain, binge urges) plus a custom symptom; expand `PrimaryGoal` with trying-to-conceive, metabolic, skin/hair, perimenopause and a contraception question; label the heuristic hair density score honestly or hide it; make the FSA/HSA letter patient-voiced and US-only.
15. **Reach (M each).** Follow-system dark mode (`SharedUI/Styles/AppearancePreferences.swift:49-51` never returns nil; dark tokens already exist). Add es (es-419 + es-ES) and pt-BR, then en-IN/hi with "PCOD" in India keywords; the L10n pipeline makes this a 1,542-key table plus two enum arrays. Honour Reduce Motion, Increase Contrast and Differentiate Without Color beyond the hero ring; add chart accessibility descriptors and labels in Supplements/PhotoJournal/Onboarding; add AX-size layout branches to Today, Calendar and paywall.
16. **Re-engagement surfaces (L).** `cyclebalance://` scheme + universal links and `onOpenURL` routing (prerequisite for everything below); App Intents for "log period"/"log symptom" with an `AppShortcutsProvider`; a widget extension (App Group + shared store) for cycle day, days since last period, streak, and an interactive quick log; opt-in HealthKit write-back of menstrual flow and symptoms; a shareable weekly-recap image on Home/Insights; offer codes and win-back offers via App Store Connect.
17. **Scanner (1.1, only after its gates).** Ship the fail-closed Gemini Photo Estimate once the benchmark, App Privacy (Photos), distribution profile and TestFlight JWS gates pass, with the already-drafted localized metadata.

### Explicitly not now

Android, any community or coaching feature, CGM vendor integrations, clinician portal, iPad, meal response scoring, and the General Kenobi canary work beyond keeping it compiling. Capture Android demand with a waitlist link in the existing social replies instead.

## Decisions for the owner (non-blocking; defaults in bold)

- Pricing: **keep the live $6.99/$39.99 tier** and make the repo match, or revert App Store Connect to 9.99/79.99.
- 1.0.5 scope: **scanner-hidden trust release now**, scanner in 1.1.
- Free tier: **add capped supplement logging and any-date back-fill to free**; keep glucose, meals, photo journal, forecasts premium.
- App Privacy posture: **declare only Purchase History and Other Data for the hidden-scanner build** (on-device health data is not "collected").
- AdServices token capture: **remove** unless Apple Search Ads campaigns are planned.
- Next locales: **es and pt-BR in 1.1**, then en-IN/hi.

## Verification approach for any change made from this plan

Build and test from the RC worktree root (paths contain spaces, quote them):

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -disableAutomaticPackageResolution -skipPackageUpdates build
```

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build -disableAutomaticPackageResolution -skipPackageUpdates test -only-testing:PCOSTests
```

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath build -disableAutomaticPackageResolution -skipPackageUpdates build
```

- Run `xcodegen generate` after any file add/delete; `project.yml` is the source of truth. Add a `PCOS-Unit` scheme so the 12-second suite does not build the UI-test runner (today ~18 minutes wall time).
- Visual check with seeded data and forced theme, no tapping needed: `xcrun simctl launch booted alex.PCOS UITestMode -uiTest.demoScenario symptomManagement -appearance.themeOption lunarCalm` then `xcrun simctl io booted screenshot <path>`. Scenarios: `newlyDiagnosed | symptomManagement | ttcFertility`. `-onboarding.startPhase <phase>` jumps into an onboarding phase. Add a long-cycle demo scenario (open cycle at day 70, no completed cycles) for the Tranche 2 Today work, and run Today/Calendar/Paywall at `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` in German.
- Swift Testing (`@Suite/@Test/#expect`) in `PCOS/PCOSTests`. Add a behaviour test for every fix above (named in each item); prefer behaviour tests over the existing source-grep guardrail style (15 of 70 test files).
- Release gates for 1.0.5: `AppStoreConfigTests` and `PrivacyManifestTests` pass against the trimmed manifest; the archive's `Info.plist` contains `ITSAppUsesNonExemptEncryption`; the hidden build's camera/photo strings mention no AI analysis; storefront re-fetch shows the qualified privacy paragraph.

## Appendix A: confirmed defects and risks (spot-checked in RC source unless marked "(agent)")

All paths relative to `.worktrees/cyclebalance-1.0.5-rc/PCOS/PCOS` unless noted.

| id | sev | what is wrong today | where |
|---|---|---|---|
| repo-01 | critical (risk) | 68 commits since 2026-07-03 on no remote; `origin/main` is the website, so app CI never ran; last fetch 2026-05-10 | `PCOS_Management/.git`, `.github/workflows/ios-ci.yml` |
| persist-01 | critical (risk) | No `VersionedSchema`/`SchemaMigrationPlan`; on Release store-open failure `StoreRecovery` moves the SQLite aside and boots empty with no user notice or restore | `App/CycleBalanceApp.swift:225-245`, `Core/Data/StoreRecovery.swift:16-46` |
| loop-01 | high | "Period Predictions" reminder toggle does nothing: `schedulePeriodPredictionReminder` has zero callers | `Core/Notifications/NotificationManager.swift:80`, `Features/Cycle/ViewModels/CycleViewModel.swift:168-170` |
| loop-04b | high (plausible) | `cancelReminders(withPrefix:)` removes inside a deferred `Task` after the synchronous `add`, so the just-scheduled `symptom.daily` request can be deleted | `Core/Notifications/NotificationManager.swift:147-176,290-302` |
| loop-02 | high | Symptom analyzer fetches 14 days and requires 14 distinct days (perfect streak); readiness copy counts lifetime days | `Core/ML/InsightSymptomCorrelationAnalyzer.swift:12-24`, `Features/Insights/ViewModels/InsightPresentationPlanner.swift:90-127` |
| loop-04 | high | Insights dashboard plots hard-coded fallback arrays under static "Feb…Jul" labels and invented percentages (July UX P0, unfixed) | `Features/Insights/Views/InsightsView.swift:549,864,923,1178,1288` |
| clin-01 | high | Vitamin D "2000 mg", Folate "400 mg", Chromium "200 mg" (values are IU/mcg; only unit is `dosageMg`) | `Features/Supplements/Models/PCOSSupplements.swift:37,142,157`, `SupplementLogView.swift:401,527,571` |
| clin-02 | high | Glucose mg/dL-only, validator `(40...600)`, zero "mmol" in the app; blocks mmol/L users in shipped locales | `Features/BloodSugar/ViewModels/BloodSugarViewModel.swift:23-26,261` |
| clin-06 | high | All `generateInsights()` callers use default `.cycling`; pregnant users get cycle/forecast insights; no GDM targets; no pregnancy-unsafe supplement flag | `Features/Insights/ViewModels/InsightsViewModel.swift:32,273`, `App/CycleBalanceApp.swift:697` |
| CE-1 | high | Logging a period day before the open cycle's start rewrites the current start and previous cycle's end, allowing overlapping cycles and negative lengths | `Features/Cycle/Models/CycleLogService.swift:120-125,729-748` |
| CE-3 | high | Spotting is a period day: it anchors the 10-day gap, so mid-cycle spotting triggers false "Start a new cycle?" or swallows a real period start | `CycleLogService.swift:126-141,313,422,488`, `TodayView.swift:991` |
| CE-2 | high | Overdue predictions keep showing a past "may arrive between" range; countdown returns nil but the range text has no date check | `Features/Cycle/ViewModels/CycleViewModel.swift:319-336,409-422`, `TodayView.swift:644-661` |
| PG-1 | high | Apple Health import bounded to 7 days and never creates `Cycle` records (0 references) | `Core/HealthKit/HealthKitSyncWorker.swift:210,230,545-570` |
| persist-02 | high | Photo key is `AfterFirstUnlockThisDeviceOnly`; backup exports encrypted bytes verbatim, so photos restore blank on a new phone | `Core/Services/PhotoEncryptionService.swift:83`, `App/SettingsDataBackupService.swift:143,172` |
| persist-03 | high | `DailyLogRecord` lacks pain, private note, positive actions; daily check-ins dropped by backup | `App/SettingsDataBackupSchema.swift:382-392`, `App/SettingsDataImportService.swift:1286-1300` |
| persist-04 | high (risk) | Replace-all import clears everything with no pre-import snapshot | `App/SettingsDataImportService.swift:148-152` |
| MR-1 | high (risk) | Live prices $6.99/$39.99 vs repo 9.99/79.99; tier intent undocumented | `StoreKit/PCOS.storekit:83,140` |
| MR-3 | high (risk) | Live listing absolutes ("no cloud uploads") and "coming soon" contradict barcode lookup and 1.0.5 | App Store Connect; `docs/app_store_1.0.5_localized_metadata.md:3-5` |
| ASC-01 | high (risk) | Privacy manifest and live label declare Health, Fitness, Photos, User ID as collected and linked, contrary to own first-pass guidance and in-app copy | `PrivacyInfo.xcprivacy` (7 linked types), `AppStoreReadinessChecklist.md:33-36` |
| L10N-01 | high | Locale falls back to `en_US` for any unsupported device language; explicit picks pin one region | `Core/LocalizationSupport.swift:60-77,376-393` |
| L10N-02 | high | 83 keys missing in ja/ko/nl and 66 in fr/it vs de, including "Are you bleeding today?" and "Cycle day %lld" | `*.lproj/Localizable.strings` (de 1542, fr 1476, it 1480, ja 1460, ko 1457, nl 1458 keys) |
| ONB-3 | high (gap) | Guided first action defaults to "log a period day"; no path for months without a period | `Features/Onboarding/Models/OnboardingProfile.swift:339-344`, `GuidedActionView.swift:55-63` |
| clin-03 | medium | Weight imported in kg, Today shows "lb", PDF shows "kg" | `HealthKitSyncWorker.swift:996`, `TodayView.swift:1457`, `PDFReportGenerator.swift:691,715` |
| clin-07 | medium | Pregnancy loss/"other" endings become `.postpartum` with "log your first period" copy (July UX P0, unfixed) | `Features/Pregnancy/PregnancyViewModel.swift:133-148`, `PregnancyDashboardCard.swift:34-56` |
| loop-05 | medium | Today snapshot shows "Mood: Calm"/"Energy: Medium" when nothing logged | `TodayView.swift:751-768` |
| loop-06 | medium | Symptom logger Flow slider defaults to Medium and is never saved; Great/Good moods store nothing; Save enabled with no input | `Features/Symptoms/Views/SymptomLogView.swift:19,458,835,847-860,936-949` |
| loop-09 | medium | Single review prompt spent on first PDF or photo | `Core/Services/ReviewPromptService.swift:72-79` |
| loop-10 | medium | Streak counts only symptom/cycle entries | `Features/Cycle/Models/StreakService.swift:6,55,66` |
| loop-11 | medium | "No period today" fails without an open cycle; no long-gap acknowledgement | `CycleLogService.swift:189-200`, `TodayView.swift:532-564,1167-1178` |
| persist-08 | medium | HealthKit glucose dedupes by timestamp, no provenance; deleted readings resurrect; type hard-coded `.random` | `HealthKitSyncWorker.swift:366-393` |
| BB-2 / ASC-05 | medium (risk) | `FirebaseApp.configure()` runs unconditionally in Release with the scanner hidden | `App/CycleBalanceApp.swift:88-94,106-112` |
| ASC-02 | medium | Camera/photo usage strings advertise nutrition estimates in the hidden-scanner build | `Info.Release.plist`, `*.lproj/InfoPlist.strings` |
| ASC-03 | medium | `ITSAppUsesNonExemptEncryption` absent from both plists (0 hits) | `Info.plist`, `Info.Release.plist` |
| MON-03 / ASC-04 | medium (risk) | No auto-renew disclosure or EULA link; no per-month framing | `Core/StoreKit/PaywallView.swift:60-463,615-728` |
| MON-08 | medium (risk) | Any sandbox receipt grants premium and hides subscription UI on TestFlight | `App/AppState.swift:120-130,152-161` |
| MON-05 | medium | Calendar taps older than 30 days hit a generic paywall; back-fill blocked | `CalendarMonthView.swift:315-323`, `FreeTierPolicyService.swift:19-27` |
| ONB-4 | medium (risk) | "After 2 cycles" promise vs 3-cycle analyzer threshold | `YourPlanView.swift:78`, `InsightCyclePatternAnalyzer.swift:16-17` |
| ONB-5 | medium (risk) | One tap fires camera prompt (premium feature) then HealthKit | `PermissionsStepView.swift:46-55` |
| MR-6 | medium (risk) | "Growing community of women" promise; no community | `OnboardingCompletionView.swift:155,157`, `SocialProofView.swift:90` |
| CE-4 | medium | `predictNextPeriodPostpartum` has no callers (verified, 0 hits); postpartum users get pre-pregnancy-weighted predictions | `CyclePredictionService.swift:26-69`, `CyclePredictionEngine.swift:169-220` |
| CE-5 (agent) | medium | Phase buckets fixed at 28-day day counts for cycles up to 45 days | `Core/Services/CyclePhaseInferencePolicy.swift:72-77` |
| CE-6 (agent) | medium (risk) | No fencing of completed cycle lengths feeding prediction/statistics | `CyclePredictionEngine.swift:37,96-111` |
| CE-7 (agent) | medium (gap) | `logSkippedPeriod` unwired and unsafe (uses `existingCycles.last`, raw `Date()`, no undo) | `CycleLogService.swift:584-594`, `CycleViewModel.swift:161-164` |
| L10N-03 (agent) | medium | 22 bare `Text("…")` literals with no translation (notification settings, histories, meal log) | `NotificationSettingsView.swift:122,181,239` and others |
| L10N-04 | medium (gap) | `preferredColorScheme` never nil; 8 of 9 themes force light | `SharedUI/Styles/AppearancePreferences.swift:49-51` |
| ONB-2 (agent) | medium | Health-context fallback quiz answers never persisted; English in all locales | `OnboardingHealthContextRevealView.swift:13-14,187-199` |
| MON-07 | low | Settings "Subscription" row opens the buy paywall for subscribers | `App/SettingsView.swift:190-200` |
| ASC-06 (agent) | low | AdServices token captured every launch, never used | `App/CycleBalanceApp.swift:16,94,936-957` |
| ONB-6 (agent) | low | Progress bar counts the hidden `mealScanDemo` phase | `OnboardingContainerView.swift:18-21` |
| persist-05/06/09/10/11/12 (agent) | low to medium | Plaintext tmp backup never removed; StoreRecovery leaves `_EXTERNAL_DATA` blobs; meal delete orphans scan rows and photo; scanner photos keyed by absolute path; delete-all understates scope and never rolls back; four delete/toggle saves are log-only | `App/SettingsDataBackupService.swift:26-30`, `Core/Data/StoreRecovery.swift:29`, `Features/Meals/ViewModels/MealViewModel.swift:243-253`, `App/SettingsDataDeletionService.swift:21-42` |
| BB-1 / BB-3 | low | `xcodebuild test` hangs on package resolution without `-disableAutomaticPackageResolution`; unit run builds the UI-test runner (~18 min for a 12 s suite) | `project.yml` schemes |

## Appendix B: gaps and opportunities by lens (agent evidence, not code defects)

- **Retention:** no early/descriptive insights (loop-03); no weekly recap (loop-08); insights generated only when the tab opens, no badge (loop-12); Today "Insight for you" is a permanent meal-centric starter for symptom-only users (loop-12b).
- **Clinical:** no medication tracking (clin-04/MR-4); no lab results (clin-05/MR-5); symptom catalog misses sleep, brain fog, libido, night sweats, heavy bleeding, dark patches, joint pain, binge urges, custom (clin-09); onboarding goals lack TTC/metabolic/contraception/perimenopause (clin-10); FSA/HSA letter in clinician voice, all locales (clin-11); heuristic hair density score shown as a number (clin-12); catalog descriptions English-only (clin-13); "Lower-carb meal" scored positive action without disordered-eating safeguard (clin-14).
- **Monetization:** no trial (MON-01/MR-2); reactive-only paywall (MON-02); no lock affordance before tap (MON-04); free tier is a generic period tracker with every PCOS differentiator gated (MON-06); no win-back/offer codes (PG-8).
- **Market:** doctor-ready export under-sold in the listing while competitors headline it (MR-8); 2 ratings after two months (MR-9); iPhone-only where every scaled competitor ships Android (MR-7, strategy decision).
- **Platform:** no last-period/cycle-length onboarding step (PG-2); no HealthKit write-back (PG-3); manual-only sync (PG-4/persist-13); no widgets/App Intents (PG-5); proprietary CSV import only, no Flo/Clue/Health-export adapters (PG-6); no share card (PG-7); no deep links (PG-9); Xcode 16 baseline, no iOS 26 adoption (PG-10).
- **Accessibility/localization:** Reduce Motion/contrast/differentiate-without-color honoured only by the hero ring (L10N-05); thin VoiceOver outside Cycle/Meals, charts unlabelled (L10N-06); es/pt-BR/en-IN+hi missing (L10N-07); AX sizes shrink instead of reflow (L10N-08).
- **Release process:** scanner-only gates block a scanner-hidden release (ASC-03); live privacy pages describe a Gemini feature the live app lacks and contain a known-inaccurate quota sentence (ASC-07); RC worktree has uncommitted artifact deletions on top of the last commit (BB-5).
