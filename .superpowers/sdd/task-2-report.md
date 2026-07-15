# Task 2 report — scanner release experience

Date: 2026-07-14 (America/Chicago)

Independent-review remediation verified: 2026-07-15 (America/Chicago)

Base commit: `13e44565f850e94256d454113498585acf276631`

Task 2 commit: the commit containing this report. Its authoritative hash is supplied in the Task 2 handoff and `git log`; a commit cannot embed its own final object hash without changing that hash.

## Outcome

The scanner now uses one branded, scroll-owning phase shell for entry, camera, consent, processing, repeat suggestion, review, editing, failure recovery, ambiguous/new-attempt recovery, saved completion, and sharing. It adds exact four-fact Gemini consent, honest processing/quota language, adaptive editable nutrition review, saved View Meal/Add Context/Share actions, privacy-safe flattened share artwork, fail-closed campaign routing, seven-locale scanner strings, accessibility identifiers/labels, and DEBUG-only phase fixtures for deterministic recovery QA.

The independent review follow-up now records portion changes separately from generic edits, always renders and announces Net carbs including `0 g`, exposes each food row as one contextual VoiceOver element including any warning, uses the existing branded heading font for semantic scanner headings while preserving system/app fonts for nutrient data, and updates the exact saved meal's context in place. Add Context no longer constructs a blank meal form or duplicates a meal; its optional glucose action opens the separate after-meal glucose flow without mutating the saved meal.

The DEBUG sample path now loads the existing `botanical-meal-bowl` app asset instead of an empty `UIImage`, so consent and review evidence visibly exercises the selected-photo slot. The approved artifact `Artifacts/lunar-calm-meal-scan-entry.png` remains byte-for-byte identical to `e82007a` (`7168a5727f6fb44a04706a7cfafea9481fd498e5`).

## Files changed in the Task 2 commit

- `PCOS/PCOS/App/ContentView.swift`
- `PCOS/PCOS/App/SettingsDataBackupSchema.swift`
- `PCOS/PCOS/App/SettingsDataBackupService.swift`
- `PCOS/PCOS/App/SettingsDataImportService.swift`
- `PCOS/PCOS/Core/Data/SwiftData/MealScanRecords.swift`
- `PCOS/PCOS/Core/StoreKit/PaywallView.swift`
- `PCOS/PCOS/Features/Meals/MealScan/Models/MealScanModels.swift`
- `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealSuggestionView.swift`
- `PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift`
- `PCOS/PCOS/Features/Meals/MealScan/Services/MealScanServices.swift`
- `PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`
- `PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`
- `PCOS/PCOS/Features/Meals/Views/MealLogView.swift`
- `PCOS/PCOS/Features/Onboarding/Views/OnboardingMealScanDemoView.swift`
- `PCOS/PCOS/Info.plist`
- `PCOS/PCOS/Info.Release.plist`
- `PCOS/PCOS/de.lproj/Localizable.strings`
- `PCOS/PCOS/fr.lproj/Localizable.strings`
- `PCOS/PCOS/it.lproj/Localizable.strings`
- `PCOS/PCOS/ja.lproj/Localizable.strings`
- `PCOS/PCOS/ko.lproj/Localizable.strings`
- `PCOS/PCOS/nl.lproj/Localizable.strings`
- `PCOS/PCOSTests/InterfaceResilienceTests.swift`
- `PCOS/PCOSTests/LocalizationResourceTests.swift`
- `PCOS/PCOSTests/MealScanPersistenceTests.swift`
- `PCOS/PCOSTests/MealScanReleaseContractTests.swift`
- `PCOS/PCOSTests/MealScanViewModelTests.swift`
- `PCOS/PCOSUITests/PCOSUITests.swift`
- `.superpowers/sdd/task-2-report.md`

`docs/meal_scan_flash_lite_production_setup.md` contains the provider-token publication gate and canonical-link fallback, but it was already included in base commit `13e4456` by the adjacent canary task and therefore is not duplicated in this diff.

## Privacy, routing, and claims

- Default share output contains only CycleBalance branding, the reviewed headline, reviewed-food count, and adjusted-portion count.
- Food names, the meal photo, and macros are each off by default and require an explicit toggle.
- The optional photo is redrawn into an opaque PNG; ImageIO tests prove source EXIF user comments/date, TIFF make/model, GPS coordinates, and private markers do not survive.
- Default and optional visible text are tested not to include identity, date, symptoms, glucose, cycle phase, or luteal context.
- Share cancellation changes only presentation state; source inspection proves no view-model, model-context, save, or navigation mutation path exists in the composer.
- A numeric provider token produces `pt`, `ct=meal_scan_share`, and `mt=8`. Missing, unresolved, or invalid tokens fail closed to `https://cyclebalance.app/meal-scan`.
- No real provider token is present. Attribution remains publication-gated.
- Saved Add Context resolves the exact saved `MealEntry` ID, edits only its after-meal severity/note/timestamp in place, and never opens a blank manual-nutrition form or inserts another meal.
- The separate glucose action pre-fills an after-meal glucose route from that same meal identity without changing or duplicating the meal.
- Onboarding/paywall text describes an editable draft and removes unsupported cycle-aware nutrition positioning.

## TDD evidence

Intentional RED evidence:

- `/tmp/cyclebalance-task2-red.log` — initial focused compile failed because `ScannerShareCard` and release contracts did not exist (exit 65).
- `/tmp/cyclebalance-task2-provider-token-red.log` — provider-token campaign/fallback contracts failed before implementation (exit 65).
- `/tmp/cyclebalance-task2-real-photo-red.log` — the new real-sample-photo contract failed against `UIImage()` (16-test suite, two expectation issues).
- `/tmp/cyclebalance-task2-ui-recovery-red.xcresult` and `.log` — recovery UI test failed at the unseeded processing phase, as intended.
- `/tmp/cyclebalance-task2-review-red.xcresult` and `.log` — independent-review contracts failed to compile before the portion-specific state existed (exit 65), establishing RED for the five review findings.

Final GREEN evidence:

- `/tmp/cyclebalance-task2-final-unit.xcresult` and `.log` — 154 tests in 12 scanner-related suites passed in 4.652 seconds. Suites include accessibility labels, interface resilience, localization resources, persistence, pipeline, release contract, view model, repeat cache, privacy manifest, Gemini contracts, metabolic profile, nutrition calculator, and production App Check probe.
- `/tmp/cyclebalance-task2-final-build.log` — `xcodebuild build` for iPhone 17 Pro simulator succeeded.
- `/tmp/cyclebalance-task2-ui-phase-refresh.xcresult` and `.log` — four-theme entry/review/saved/share matrix passed in isolation (1/1, 170.647 seconds) with 16 refreshed attachments and the real sample asset.
- `/tmp/cyclebalance-task2-ui-recovery-3.xcresult` and `.log` — camera, processing, fallback/retake, ambiguous, new-attempt, and return-to-ambiguous fixture journey passed (1/1, 95.347 seconds) with five attachments. The phase title and Close control remained reachable after scrolling to recovery actions.
- `/tmp/cyclebalance-task2-smallest.xcresult` and `.log` — iPhone SE (3rd generation), accessibility XXXL review/save journey passed (1/1, 98.594 seconds) with two attachments.
- `/tmp/cyclebalance-task2-increase-contrast.xcresult` and `.log` — real simulator Increase Contrast run passed (1/1, 16.970 seconds) with one attachment. The setting read back `enabled` before XCTest and was restored/read back `disabled` afterward.
- `/tmp/cyclebalance-task2-ui-audit.xcresult` and `.log` — five UI tests passed, including seven-language saved/share smoke. Its pre-refresh blank-photo/light evidence is superseded by the refresh bundles below.
- `/tmp/cyclebalance-task2-ui-refresh.xcresult` and `.log` — refreshed consent (four themes) and corrected Fruit Grove light/Lunar Calm dark test cases passed. The combined bundle is not counted as wholly green because its phase test lost the XCTest helper connection after Lunar save; the phase test was immediately rerun green in `/tmp/cyclebalance-task2-ui-phase-refresh.xcresult`.
- `/tmp/cyclebalance-task2-review-green-2.xcresult` and `.log` — 69 focused localization, persistence, release-contract, and view-model tests passed in 4.391 seconds.
- `/tmp/cyclebalance-task2-review-full-unit.xcresult` and `.log` — the broader scanner regression set passed 160 tests in 12 suites in 5.108 seconds.
- `/tmp/cyclebalance-task2-review-context-ui-4.xcresult` and `.log` — the complete save/View Meal/Add Context/separate-glucose/save/reopen journey passed (1/1, 52.260 seconds). It verifies the saved-detail food-row accessibility identifier and contextual label, exact saved meal name, and persisted severity/note. Earlier context UI bundles were diagnostic and are superseded by this green result.
- `/tmp/cyclebalance-task2-review-final-build.log` — exact-head incremental `xcodebuild build` for iPhone 17 Pro simulator succeeded.
- `git diff --check` passed.
- Debug plist plus all six `.strings` files pass `plutil -lint`. The Release plist contains intentional C preprocessor gates; its fully enabled preprocessed output passes `plutil -lint` at `/tmp/cyclebalance-info-release-preprocessed.plist`.

Final simulator readback after restoration: Increase Contrast `disabled`, appearance `dark`, content size `large`.

## UI coverage matrix

| Phase / surface | Automated coverage | Themes / languages / form factors | Status and limits |
|---|---|---|---|
| Entry | Opens from Meal Log; branded shell/actions/privacy; screenshots | Lunar, Botanical, Fruit, High Contrast; Fruit light; Lunar dark | Covered |
| Camera | Guidance, permission status, import/take/sample/barcode/manual actions; screenshot | Lunar, iPhone 17 Pro | Covered for not-requested state. Real allow/deny/restricted permission transitions remain manual. |
| Consent | Exact four facts, disclosure, send/manual/retake, visible selected asset | All four themes | Covered in English. Consent was not traversed in every locale. |
| Processing | Deterministic DEBUG fixture and stage copy; no fake percentage | Lunar | Covered as a stable fixture. Real network-duration transitions remain outside UI automation. |
| Repeat suggestion | Existing UI tests define Lunar AXXXL reuse and Botanical Scan as New journeys; repeat cache/view-model units passed | Lunar AXXXL, Botanical standard | Journey definitions present; those two UI methods were not rerun in the final focused artifact set. |
| Review | Real sample image, food rows, adaptive nutrients, confidence, warnings, save | All four themes; iPhone SE AXXXL | Covered |
| Food editor | Existing UI journey opens fields and cancels; editor source/contract removes `Form` and validates fields | Lunar | Defined in suite; not rerun in final focused artifact set. |
| Manual fallback | Deterministic fixture, manual/barcode/retake reachability, retake returns to camera | Lunar | Covered |
| Ambiguous outcome | Deterministic fixture, same-request/new-analysis truth, request-new action | Lunar | Covered |
| New-attempt confirmation | Ambiguous-to-confirmation transition, billable warning, Go Back returns to ambiguous | Lunar | Covered. Confirming a real second remote request is intentionally not exercised. |
| Saved | View Meal/Add Context/Share actions; exact meal identity; contextual saved-row VoiceOver label; separate glucose route; context save/reopen | All four themes; iPhone SE AXXXL; focused Lunar context journey | Covered. Unit persistence proves the meal count and food IDs remain unchanged; the focused UI journey proves exact-name routing and persisted context without a blank form. |
| Share composer | Private defaults, preview, opt-in toggles present; screenshots | All four themes; en/de/fr/it/ja/ko/nl | Covered. Actual activity completion/cancel is unit/source tested, not manually invoked on a real device. |
| Share image/privacy | Default/optional content, flattened PNG, metadata stripping, cancellation state, URL routing | Unit contract | Covered |

## Localization and accessibility

- Scanner strings are covered by English development values plus German, French, Italian, Japanese, Korean, and Dutch resources.
- Final localization-resource tests passed and require scanner strings across models, services, repeat suggestion, view model, scanner flow, Meal Log, onboarding, and paywall.
- The seven-language UI smoke reaches saved/share and routes exclusively by identifiers rather than English labels.
- This is not a seven-language every-phase matrix; consent, camera, recovery, and editor remain source/resource validated outside English.
- The smallest-phone AXXXL journey passed on an iPhone SE (3rd generation).
- Real OS Increase Contrast passed and was restored.
- Statuses and actions use text plus symbols; a contract prevents color-only camera, review, or saved cues.
- Semantic scanner headings use the existing `appHeadingFont`; nutrient values, confidence, and other data retain `appFont`/system treatment.
- Nutrition summaries always include Net carbs visually and in the aggregate accessibility label, including `0 g`. Each food row is one contextual accessibility element with name, grams, calories, confidence, and any warning.
- The shared after-meal context editor preserves Meal Log note focus and keyboard-toolbar coordination while giving the scanner its own stable child identifiers.
- Simulator tooling exposes no deterministic Differentiate Without Color toggle. Actual OS-level Differentiate Without Color remains a named manual Settings/real-device gap.

## Exported visual evidence

Root: `/Users/alexhuggler/.codex/visualizations/2026/07/15/019f636f-b3a1-7cb1-bc85-bdf9003b706b`

- `task-2-ui-phase-refresh/` — 16 all-theme entry/review/saved/share screenshots plus manifest.
- `task-2-ui-refresh-combined/` — refreshed four-theme consent and corrected light/dark screenshots; also contains diagnostics from the superseded transport failure.
- `task-2-ui-recovery/` — five camera/processing/fallback/ambiguous/new-attempt screenshots plus manifest.
- `task-2-smallest/` — two SE AXXXL screenshots plus manifest.
- `task-2-increase-contrast/` — one real OS Increase Contrast screenshot plus manifest.
- `task-2-ui-audit/` — older broad audit; superseded where noted above.

Friendly host copies are ignored under `.superpowers/sdd/task-2-screenshots/` and are not committed. No generated screenshot was written to `Artifacts/`.

## Remaining release/manual gates

1. Obtain and verify the official numeric App Store provider token, archive with it, read it back from the signed plist, validate the `pt`/`ct`/`mt` link, and verify attribution reporting. Until then, sharing intentionally uses the canonical web URL.
2. Exercise real camera allow/deny/restricted transitions and Differentiate Without Color through Settings or a physical device.
3. Perform a real share-completion and share-cancellation pass, plus an opted-in photo/macros share, on the distribution candidate.
4. Run a true seven-language every-phase visual review if full-language phase parity is a release requirement; current automation covers every language at saved/share and validates all resources.
5. Real Gemini/TestFlight/distribution canary work remains governed by the separate approval-gated Task 3 runbook; no live cloud, secret, device, TestFlight, or App Store mutation occurred in Task 2.
