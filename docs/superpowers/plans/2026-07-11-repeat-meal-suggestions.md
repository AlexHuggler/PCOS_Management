# CycleBalance Repeat Meal Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local, user-confirmed repeat-meal cache that quietly suggests a previously reviewed meal before any remote scan, while keeping visual-similarity rollout behind a measured precision gate.

**Architecture:** Preserve the existing 24-hour exact provider-response cache, and add a separate SwiftData cache whose canonical payload is a versioned editable-draft snapshot. Exact normalized-image hashes are eligible immediately; Vision revision-2 feature prints are stored locally and compared only when a calibrated policy is enabled. `MealScanViewModel` owns the one-tap choice between reuse and a fresh scan, and every reused result still lands in the existing review screen.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Vision, CryptoKit, Swift Testing, XcodeGen, Node.js built-in test runner, Firebase App Check/App Attest, Cloud Run.

## Global Constraints

- Never store or transmit raw photos for repeat matching; existing optional local photo retention remains independent.
- Never send exact hashes or Vision feature prints to Cloud Run, Gemini, RevenueCat, or analytics.
- Reuse only final user-confirmed values, never an unreviewed provider response.
- Reuse must make zero App Check, RevenueCat, proxy, Gemini, or quota calls.
- `Use Previous Meal` and `Scan as New` are the exact English action labels.
- The suggestion title is `Looks familiar`; supporting copy is `You can adjust anything before saving.`
- Exact reviewed-meal suggestions may be enabled in Release after verification.
- Similar-photo suggestions remain disabled in Release until a 100-image evaluation reaches at least 95% precision and has zero reviewed high-risk cross-meal matches.
- Keep at most 100 repeat records and evict least-recently-used records.
- Keep all existing meal-scan security, trial, paid-quota, budget, and manual-fallback behavior unchanged for fresh scans.
- Preserve all unrelated work in the dirty tree; never reset, revert, or stage files outside the task's explicit file list.

## File Map

- `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealModels.swift`: versioned snapshot, suggestion, fingerprint, and policy value types.
- `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealImageFingerprinter.swift`: injectable Vision revision-2 fingerprint creation and distance comparison.
- `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/MealScanRepeatCache.swift`: SwiftData lookup, exact/similar matching, corruption cleanup, usage updates, and LRU eviction.
- `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealSuggestionView.swift`: compact botanical/lunar suggestion UI.
- `PCOS/PCOS/Core/Data/SwiftData/MealScanRecords.swift`: `MealScanRepeatCacheRecord` persistence model, assigned only to the local cache configuration.
- `PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`: preflight matching, reuse, bypass-once, and save orchestration.
- `PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`: phase routing and suggestion presentation.
- `PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift`: mark reused meals without losing item-level nutrition sources.
- `PCOS/PCOS/Features/Meals/ViewModels/MealViewModel.swift` and `PCOS/PCOS/App/SettingsDataDeletionService.swift`: record cleanup.
- `tools/meal-repeat-evaluation/`: private-dataset manifest, Vision distance extractor, deterministic policy calibrator, tests, and capture guide.
- `PCOS/PCOSTests/RepeatMealCacheTests.swift`: model, fingerprint, cache, and policy tests.
- `PCOS/PCOSTests/MealScanViewModelTests.swift`: reuse and fresh-scan orchestration tests.
- `PCOS/PCOSTests/ProductionMealScanAppCheckProbeTests.swift`: opt-in physical-device integrity probe.

---

### Task 1: Add The Versioned Snapshot And SwiftData Record

**Files:**
- Create: `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealModels.swift`
- Modify: `PCOS/PCOS/Core/Data/SwiftData/MealScanRecords.swift`
- Modify: `PCOS/PCOS/App/CycleBalanceApp.swift`
- Modify: `PCOS/PCOS/App/ContentView.swift`
- Modify: `PCOS/PCOSTests/TestHelpers.swift`
- Create: `PCOS/PCOSTests/RepeatMealCacheTests.swift`

**Interfaces:**
- Produces: `RepeatMealDraftSnapshot`, `RepeatMealSourceMetadata`, `MealImageFingerprint`, `RepeatMealSuggestion`, `MealRepeatSimilarityPolicy`, and `MealScanRepeatCacheRecord`.
- `RepeatMealDraftSnapshot.schemaVersion` is exactly `1`.
- `MealScanRepeatCacheRecord` is registered in production, preview, and test containers but never in the optional CloudKit configuration.

- [ ] **Step 1: Write failing snapshot and schema tests**

Add a `@Suite("Repeat Meal Cache", .serialized)` that verifies a snapshot round-trip preserves name, meal type, items, totals, confidence, warnings, hidden-ingredient choice, and source model metadata. Add a schema test that inserts and fetches one `MealScanRepeatCacheRecord` through `TestHelpers.makeModelContainer()`.

```swift
@Test("versioned repeat draft snapshot round trips reviewed state")
func snapshotRoundTrips() throws {
    let snapshot = RepeatMealDraftSnapshot(
        mealName: "Chicken rice bowl",
        mealType: .lunch,
        items: [Self.riceDraft],
        nutrition: NutritionSnapshot(caloriesKcal: 540, proteinGrams: 32, carbsGrams: 61, fatGrams: 17),
        confidence: .medium,
        warnings: ["Review the sauce amount."],
        hiddenIngredientEstimate: .aLittle,
        source: RepeatMealSourceMetadata(modelVersion: "gemini-2.5-flash-lite", pipelineVersion: "meal-scan-v2")
    )
    let data = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(RepeatMealDraftSnapshot.self, from: data) == snapshot)
    #expect(snapshot.schemaVersion == 1)
}
```

- [ ] **Step 2: Run the test and confirm the intended compile failure**

Run:

```sh
xcodegen generate
xcodebuild -project PCOS.xcodeproj -scheme PCOS \
  -destination 'platform=iOS Simulator,id=65704604-59EC-439F-B764-64FD273067BD' \
  -only-testing:PCOSTests/RepeatMealCacheTests test
```

Expected: FAIL because the repeat-meal types and model do not exist.

- [ ] **Step 3: Implement the value types and persistence model**

Define the canonical snapshot as Codable, Equatable, and Sendable:

```swift
struct RepeatMealSourceMetadata: Codable, Equatable, Sendable {
    var modelVersion: String
    var pipelineVersion: String
}

struct RepeatMealDraftSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion = Self.currentSchemaVersion
    var mealName: String
    var mealType: MealType
    var items: [MealFoodItemDraft]
    var nutrition: NutritionSnapshot
    var confidence: NutritionConfidence
    var warnings: [String]
    var hiddenIngredientEstimate: HiddenIngredientEstimate
    var source: RepeatMealSourceMetadata
}

struct MealImageFingerprint: Equatable, Sendable {
    var sourceImageHash: String
    var featurePrintArchive: Data?
    var visionRevision: Int
}

struct RepeatMealSuggestion: Identifiable, Equatable, Sendable {
    enum MatchKind: String, Sendable { case exactImage, similarImage }
    var id: UUID { recordID }
    var recordID: UUID
    var sourceMealID: UUID
    var snapshot: RepeatMealDraftSnapshot
    var lastUsedAt: Date
    var matchKind: MatchKind
}

struct MealRepeatSimilarityPolicy: Codable, Equatable, Sendable {
    var version: Int
    var enabled: Bool
    var maximumDistance: Float
    var minimumNeighborMargin: Float
    var evaluatedImageCount: Int
    var precision: Double
    var highRiskFalseMatches: Int
    static let disabled = Self(
        version: 1,
        enabled: false,
        maximumDistance: 0,
        minimumNeighborMargin: 0,
        evaluatedImageCount: 0,
        precision: 0,
        highRiskFalseMatches: 0
    )
}
```

Add `MealScanRepeatCacheRecord` with the exact fields from the approved design: IDs, hash, optional archived feature print, Vision revision, snapshot JSON/schema, display macros, timestamps, and reuse count.

Split `CycleBalanceApp.makeSharedModelContainer()` into a primary schema and a cache schema. The full `ModelContainer` receives both configurations, but the CloudKit configuration receives only the primary schema. The cache configuration uses `cloudKitDatabase: .none` and its own `MealScanRepeatCache.sqlite` URL. Tests use two in-memory configurations; Release and local-debug modes use two local configurations. If only the cache store fails to open, back up/reset that cache store without resetting user health or meal data. Preview containers remain local/in-memory.

Add source-contract coverage proving `MealScanRepeatCacheRecord.self` is absent from the schema passed to `makeCloudKitConfiguration`.

- [ ] **Step 4: Regenerate and run the focused test**

Expected: the snapshot and schema tests PASS.

- [ ] **Step 5: Commit only this task's paths**

```sh
git add PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealModels.swift \
  PCOS/PCOS/Core/Data/SwiftData/MealScanRecords.swift \
  PCOS/PCOS/App/CycleBalanceApp.swift PCOS/PCOS/App/ContentView.swift \
  PCOS/PCOSTests/TestHelpers.swift PCOS/PCOSTests/RepeatMealCacheTests.swift
git commit -m "feat: add repeat meal cache models"
```

### Task 2: Add Local Vision Fingerprinting

**Files:**
- Create: `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealImageFingerprinter.swift`
- Modify: `PCOS/PCOSTests/RepeatMealCacheTests.swift`

**Interfaces:**
- Consumes: normalized JPEG `Data` and `MealImageFingerprint`.
- Produces: `protocol MealImageFingerprinting` and `actor VisionRepeatMealImageFingerprinter`.

- [ ] **Step 1: Add failing protocol and round-trip tests**

Test that the production fingerprinter creates a 64-character SHA-256 hash, archives a feature print with revision 2, and computes a near-zero distance when comparing an image with itself. Do not assert a magic cross-image distance.

```swift
let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { context in
    UIColor.systemGreen.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 120, height: 120))
}
let normalized = try MealScanImageNormalizer().normalizeJPEGData(from: image)
let fingerprinter = VisionRepeatMealImageFingerprinter()
let fingerprint = try await fingerprinter.makeFingerprint(for: normalized.jpegData)
#expect(fingerprint.sourceImageHash.count == 64)
#expect(fingerprint.visionRevision == 2)
#expect(try await fingerprinter.distance(between: fingerprint, and: fingerprint) < 0.0001)
```

- [ ] **Step 2: Run the focused test and confirm it fails because the protocol is absent**

- [ ] **Step 3: Implement the actor**

```swift
protocol MealImageFingerprinting: Sendable {
    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint
    func distance(between lhs: MealImageFingerprint, and rhs: MealImageFingerprint) async throws -> Float
}

actor VisionRepeatMealImageFingerprinter: MealImageFingerprinting {
    func makeFingerprint(for data: Data) async throws -> MealImageFingerprint {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        try VNImageRequestHandler(data: data).perform([request])
        guard let observation = request.results?.first else { throw RepeatMealFingerprintError.noObservation }
        let archive = try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        return MealImageFingerprint(
            sourceImageHash: MealScanImageNormalizer.sha256Hex(data),
            featurePrintArchive: archive,
            visionRevision: Int(request.revision)
        )
    }
}
```

Unarchive with `NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from:)`, reject revision mismatches, and wrap Vision/archiving errors in `RepeatMealFingerprintError`. Never log image bytes or archive contents.

- [ ] **Step 4: Run `RepeatMealCacheTests` and confirm PASS**

- [ ] **Step 5: Commit the fingerprinter and tests**

### Task 3: Implement Exact And Policy-Gated Similar Matching

**Files:**
- Create: `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/MealScanRepeatCache.swift`
- Modify: `PCOS/PCOSTests/RepeatMealCacheTests.swift`

**Interfaces:**
- Consumes: `ModelContext`, `any MealImageFingerprinting`, `MealRepeatSimilarityPolicy`, `MealImageFingerprint`, and `RepeatMealDraftSnapshot`.
- Produces: `suggestion(for:now:)`, `save(snapshot:sourceMealID:fingerprint:now:)`, `markReused(recordID:now:)`, and `removeRecords(sourceMealID:)`.

- [ ] **Step 1: Add failing behavioral tests**

Cover these cases with an injected `StubRepeatMealFingerprinter`:

- exact hash returns `.exactImage` and does not call distance;
- policy disabled suppresses different-hash matches;
- nearest candidate passes only when `distance <= maximumDistance` and `secondDistance - firstDistance >= minimumNeighborMargin`;
- an ambiguous tie produces no suggestion;
- corrupt snapshot/archive and missing source meal are deleted and scanning fails open;
- exact-hash save upserts instead of duplicating;
- the 101st save evicts the least-recently-used record;
- a missing, malformed, incomplete, or sub-95%-precision policy resolves to `.disabled`.

- [ ] **Step 2: Run the tests and verify failures reference missing cache behavior**

- [ ] **Step 3: Implement `MealScanRepeatCache` on `@MainActor`**

Fetch at most 100 records sorted by `lastUsedAt` descending. Validate the source `MealEntry`, snapshot schema, and snapshot JSON before returning a suggestion. Check exact hash first. For similarity, compare compatible archives, sort successful distances, and require both the maximum and margin conditions. Delete invalid records in one maintenance save. Cache maintenance errors are logged through `Logger.meals` without payloads and return `nil` rather than blocking the scan.

When saving, JSON-encode the snapshot, upsert by exact hash, set denormalized display values, and evict overflow records after sorting by `lastUsedAt` ascending.

Add `MealRepeatSimilarityPolicy.loadApproved(from:)`, which looks for `MealRepeatSimilarityPolicy.json` and returns `.disabled` unless the artifact has `enabled = true`, `version = 1`, exactly 100 evaluated images, precision at least `0.95`, zero high-risk false matches, finite nonnegative thresholds, and a positive maximum distance. No policy resource is bundled during this task, so Release remains similarity-disabled.

- [ ] **Step 4: Run the focused suite and confirm every cache test passes**

- [ ] **Step 5: Commit the cache service and tests**

### Task 4: Wire Save, Source Metadata, And Deletion

**Files:**
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Models/MealScanModels.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift`
- Modify: `PCOS/PCOS/Features/Meals/ViewModels/MealViewModel.swift`
- Modify: `PCOS/PCOS/App/SettingsDataDeletionService.swift`
- Modify: `PCOS/PCOS/App/SettingsDataImportService.swift`
- Modify: `PCOS/PCOSTests/MealScanPersistenceTests.swift`
- Modify: `PCOS/PCOSTests/MealViewModelTests.swift`
- Modify: `PCOS/PCOSTests/SettingsDataDeletionServiceTests.swift`
- Modify: `PCOS/PCOSTests/SettingsDataBackupImportServiceTests.swift`
- Modify: `PCOS/PCOSTests/RepeatMealCacheTests.swift`

**Interfaces:**
- Produces: `ConfirmedMealScan.repeatSourceRecordID: UUID?`.
- Reused meals keep item-level USDA/Open Food Facts/manual sources, but persist `sourceName = "Repeated reviewed meal"` and `mealSource = "reusedMeal"` at the meal/import level.

- [ ] **Step 1: Add failing persistence and deletion tests**

Assert that a confirmed meal with `repeatSourceRecordID` persists the repeated source labels without rewriting item nutrition sources. Assert swipe deletion and delete-then-insert timestamp/type replacement both remove records whose `sourceMealID` matches the deleted meal. Extend Delete All Data and replace-all backup import to assert `MealScanRepeatCacheRecord` is empty. Assert backup/CSV export still omit internal hash and feature-print data.

- [ ] **Step 2: Run the three focused suites and verify the new assertions fail**

- [ ] **Step 3: Implement source and deletion behavior**

Add the optional repeat record ID to `ConfirmedMealScan`. In `SwiftDataMealLogRepository`, derive:

```swift
let isRepeated = confirmedMeal.repeatSourceRecordID != nil
let sourceName = isRepeated ? "Repeated reviewed meal" : "AI meal estimate"
let mealSource = isRepeated ? "reusedMeal" : NutritionImportSourceKind.aiMealScan.rawValue
```

Do not change `MealFoodItem.nutritionSource`. Delete matching repeat records before swipe deletion and before `MealViewModel.saveMeal()` removes same-timestamp/type entries. Include `MealScanRepeatCacheRecord.self` in Delete All Data and `SettingsDataImportService.clearAllTrackedModels()`, but do not add it to backup/export schemas.

- [ ] **Step 4: Run persistence, deletion, and cache suites and confirm PASS**

- [ ] **Step 5: Commit the scoped persistence changes**

### Task 5: Add View-Model Preflight And One-Tap Reuse

**Files:**
- Modify: `PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift`
- Modify: `PCOS/PCOSTests/MealScanViewModelTests.swift`
- Modify: `PCOS/PCOSTests/GeminiMealScanTests.swift`

**Interfaces:**
- Adds phase `.repeatSuggestion`.
- Produces: `prepareSelectedImage(_:)`, `usePreviousMeal()`, and `scanPendingImageAsNew()`.
- Adds `enableRepeatMealSuggestions` and `enableSimilarMealSuggestions` flags. Exact suggestions default on only in verified Release; similarity defaults off in Release.

- [ ] **Step 1: Add failing orchestration tests**

Use injected repeat-cache and scanner spies to prove:

- a matching image sets `.repeatSuggestion` and performs zero remote calls;
- `usePreviousMeal()` restores every editable field, marks the repeat record, and moves to `.review`;
- `scanPendingImageAsNew()` bypasses repeat matching once and calls the scanner exactly once;
- a cache/fingerprint error calls the normal scanner;
- saving creates/updates the repeat record only after repository save succeeds.

- [ ] **Step 2: Run view-model tests and confirm the expected compile/behavior failures**

- [ ] **Step 3: Implement the preflight flow**

Store the pending `UIImage`, normalized image, fingerprint, and suggestion only until the user chooses. `prepareSelectedImage(_:)` normalizes once, fingerprints once, and asks the repeat cache before any App Check token is requested. Add `GeminiRemoteMealScanService.scan(normalizedImage:mealType:)` so a fresh scan uses the exact same normalized bytes/hash instead of recompressing the selected image. If no suggestion exists, call that fresh-scan path. `usePreviousMeal()` applies the snapshot with a fresh result UUID and fresh UUIDs for every `MealFoodItemDraft`, then recalculates the metabolic profile. `scanPendingImageAsNew()` clears the suggestion and calls the existing scanner without repeating the cache lookup.

At save time, construct the versioned snapshot from the final reviewed fields, save the meal first, then persist the repeat record with `confirmedMeal.id`. A repeat-cache save failure logs and still leaves the reviewed meal saved.

- [ ] **Step 4: Run view-model and Gemini suites and confirm PASS**

- [ ] **Step 5: Commit the view-model integration**

### Task 6: Build The Quiet Suggestion UI And Localizations

**Files:**
- Create: `PCOS/PCOS/Features/Meals/MealScan/RepeatMeal/RepeatMealSuggestionView.swift`
- Modify: `PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`
- Modify: `PCOS/PCOS/de.lproj/Localizable.strings`
- Modify: `PCOS/PCOS/fr.lproj/Localizable.strings`
- Modify: `PCOS/PCOS/it.lproj/Localizable.strings`
- Modify: `PCOS/PCOS/ja.lproj/Localizable.strings`
- Modify: `PCOS/PCOS/ko.lproj/Localizable.strings`
- Modify: `PCOS/PCOS/nl.lproj/Localizable.strings`
- Modify: `PCOS/PCOSTests/InterfaceResilienceTests.swift`
- Modify: `PCOS/PCOSTests/LocalizationResourceTests.swift`
- Modify: `PCOS/PCOS/App/CycleBalanceApp.swift`
- Modify: `PCOS/PCOSUITests/PCOSUITests.swift`

**Interfaces:**
- Consumes: `RepeatMealSuggestion`, `usePreviousMeal()`, and `scanPendingImageAsNew()`.
- Produces: a stable Dynamic Type/VoiceOver suggestion surface for botanical and lunar modes.

- [ ] **Step 1: Add failing source-contract and localization tests**

Require the exact English strings `Looks familiar`, `You can adjust anything before saving.`, `Use Previous Meal`, and `Scan as New`; require translations in every shipped locale; reject visible `cache`, `similarity`, and percentage copy in the suggestion view. Add a UI test that launches with a deterministic repeat fixture, taps the mock meal photo, verifies both actions, chooses reuse, and reaches the editable review screen.

- [ ] **Step 2: Run interface and localization tests and verify they fail**

- [ ] **Step 3: Implement the view and routing**

Add `.repeatSuggestion` to the root phase switch. Render meal name, rounded calories, protein/carbohydrate/fat summary, and a relative last-used date. Use one prominent text button for `Use Previous Meal` and one bordered/plain command for `Scan as New`. Keep card radius at the app token value, use existing botanical/lunar surfaces, allow multiline text, and provide one combined VoiceOver summary followed by the two actions.

Translate all four strings naturally for `de`, `fr`, `it`, `ja`, `ko`, and `nl`; do not machine-transliterate the action labels.

Extend the existing `UITestMode` seeding path with `SeedRepeatMealSuggestion`: insert one source `MealEntry` plus an exact-hash repeat record for the deterministic mock photo. This fixture is reachable only from UI-test launch arguments and does not alter normal Debug or Release data.

- [ ] **Step 4: Regenerate, run tests, and capture simulator screenshots in both appearance modes and accessibility text size**

Verify no overlap at iPhone 17 Pro and iPhone 16e simulator sizes. Re-run the UI test with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge` and confirm the summary and actions remain reachable.

- [ ] **Step 5: Commit the UI and localization paths**

### Task 7: Build The 100-Image Evaluation Toolkit

**Files:**
- Create: `tools/meal-repeat-evaluation/.gitignore`
- Create: `tools/meal-repeat-evaluation/README.md`
- Create: `tools/meal-repeat-evaluation/manifest.example.json`
- Create: `tools/meal-repeat-evaluation/extract-feature-distances.swift`
- Create: `tools/meal-repeat-evaluation/calibrate-policy.mjs`
- Create: `tools/meal-repeat-evaluation/test/calibrate-policy.test.mjs`
- Modify: `docs/meal_scan_flash_lite_production_setup.md`

**Interfaces:**
- Consumes: a private manifest of exactly 100 local image paths and meal identity labels.
- Produces: `distance-report.json`, human-readable metrics, and a `MealRepeatSimilarityPolicy` JSON only when precision is at least `0.95` and reviewed high-risk false matches equal `0`.

- [ ] **Step 1: Write failing calibrator tests with synthetic distance reports**

Test a dataset that admits a valid threshold, one whose best threshold falls below 95% precision, and one containing a high-risk negative match. The failing cases must exit nonzero and must not write a policy file.

```js
test("emits the highest-recall policy constrained to 95 percent precision", () => {
  const result = calibrate(syntheticReport);
  assert.equal(result.policy.version, 1);
  assert.ok(result.metrics.precision >= 0.95);
  assert.equal(result.metrics.highRiskFalseMatches, 0);
});
```

- [ ] **Step 2: Run `node --test tools/meal-repeat-evaluation/test/*.test.mjs` and verify RED**

- [ ] **Step 3: Implement the zero-dependency calibrator and Vision extractor**

The Swift extractor must use `VNGenerateImageFeaturePrintRequestRevision2`, strip all output down to IDs/labels/distances/timings, and never copy image bytes. The Node calibrator must perform leave-one-out nearest-neighbor evaluation across candidate distance and margin pairs, choose the highest recall under the precision constraints, and refuse incomplete manifests or unsafe policies. Safe policy output includes `evaluatedImageCount`, `precision`, and `highRiskFalseMatches` so the iOS loader independently enforces the release gate.

`.gitignore` must exclude `dataset/`, `output/`, JPEG/HEIC/PNG files, and generated policy/report JSON while keeping the example manifest and documentation.

- [ ] **Step 4: Run calibrator tests and a five-image local smoke fixture**

Expected: unit tests PASS; smoke extraction emits distances without copying photos. Do not claim the 100-image gate passes until the user's real capture set exists.

- [ ] **Step 5: Write the capture guide**

Specify 20 meal identities, four views per identity, and 20 visually similar negatives. Require the whole plate, 30-45 degree and overhead angles, two lighting conditions, unchanged portions within each identity, weighed/label-backed macro truth, EXIF stripping, and no faces, documents, medication labels, or location-revealing backgrounds.

- [ ] **Step 6: Commit only the toolkit, tests, and runbook update**

### Task 8: Verify Production App Check Reversibly And Prepare Review Materials

**Files:**
- Create: `PCOS/PCOSTests/ProductionMealScanAppCheckProbeTests.swift`
- Modify: `project.yml`
- Create: `cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh`
- Create: `docs/app_store_meal_scan_review_packet_2026-07-11.md`
- Modify: `AppStoreReadinessChecklist.md`
- Modify: `docs/meal_scan_flash_lite_production_setup.md`

**Interfaces:**
- Physical device: `General Kenobi`, CoreDevice ID `0C663BE9-3804-587C-BD8A-A2B4D38F998A`, bundle ID `alex.PCOS`.
- Expected probe result after App Check succeeds: HTTP `403`, `error = "premium_entitlement_required"`, `reason = "entitlement_inactive"` for the deliberate nonexistent RevenueCat customer.
- The probe must make no Gemini or quota call and must restore `MEAL_SCAN_ENABLED=false` plus private Cloud Run IAM in a shell `trap`.

- [ ] **Step 1: Add the opt-in physical-device test and probe scheme**

The test is enabled only when `RUN_PRODUCTION_MEAL_SCAN_INTEGRATION=1`. It obtains a limited-use token from `FirebaseMealScanAppCheckTokenProvider`, builds a valid normalized JPEG request with `revenueCatAppUserId = "cyclebalance-appcheck-probe-no-entitlement"`, prints only the image-hash prefix needed for log correlation, and asserts the entitlement response. Add an XcodeGen Release test scheme whose test environment sets the opt-in value.

- [ ] **Step 2: Add the fail-safe shell orchestrator**

The script must:

1. Require `CONFIRM_TEMPORARY_PUBLIC_PROBE=YES` for a live run; `DRY_RUN=true` never requires confirmation.
2. Verify the project, service, budget mode `normal`, initial `MEAL_SCAN_ENABLED=false`, and absence of `allUsers` IAM.
3. Verify the phone is unlocked, paired, Developer Mode enabled, and its developer disk image can mount. A locked phone is a hard stop before build, backup, or cloud mutation; never request or handle its passcode.
4. If `alex.PCOS` is installed, copy its app-data container to `~/Library/Application Support/CycleBalance/DeviceBackups/<UTC timestamp>` with mode `0700`; abort before installation if CoreDevice backup fails and require the owner to complete an encrypted Finder backup instead.
5. Generate a fresh Xcode project and Release product into temporary directories. Never use the July 3 build-17 IPA. Before installation, assert bundle ID `alex.PCOS`, production App Attest entitlement, and the complete production proxy URL in the fresh app's plist.
6. Register the rollback `trap` before the first cloud mutation.
7. Call the reviewed deploy script with `MEAL_SCAN_ENABLED=true` and `ALLOW_UNAUTHENTICATED=true`, preserving all secret and quota configuration.
8. Install/run the Release probe test on the paired device.
9. Expect the deliberate entitlement rejection and verify logs contain no Gemini estimate event for the probe hash prefix.
10. In `trap`, call the reviewed deploy script with `MEAL_SCAN_ENABLED=false` and `ALLOW_UNAUTHENTICATED=false`, then smoke-test unauthenticated `403` plus authenticated `503 feature_disabled`.

Never print App Check, identity, RevenueCat, or Gemini tokens.

- [ ] **Step 3: Run shell syntax and dry-run checks before cloud mutation**

```sh
bash -n cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh
DRY_RUN=true PROJECT_ID=cyclebalance-prod-20260710 \
  cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh
```

Expected: dry run lists every gate and rollback action without changing cloud or device state.

- [ ] **Step 4: Run the approved physical probe**

```sh
CONFIRM_TEMPORARY_PUBLIC_PROBE=YES \
PROJECT_ID=cyclebalance-prod-20260710 \
DEVICE_ID=0C663BE9-3804-587C-BD8A-A2B4D38F998A \
cloud/meal-scan-proxy/scripts/run-physical-app-check-probe.sh
```

Record only status codes, safe reason strings, revision names, rollback success, and whether the app-data backup completed.

- [ ] **Step 5: Prepare the App Review packet without submitting**

Document the exact review notes, App Privacy deltas, privacy-policy language, screenshot checklist, reviewer test path, quota explanation, user-initiated upload disclosure, no-raw-image-retention statement, and the requirement to increment build above `17`. Keep Cloud Run private and scanner flags off after preparation.

- [ ] **Step 6: Run final verification**

Run:

```sh
git diff --check
node --test tools/meal-repeat-evaluation/test/*.test.mjs
cd cloud/meal-scan-proxy && npm ci && npm test && npm audit --audit-level=high
cd ../budget-controller && npm ci && npm test && npm audit --audit-level=high
cd ../..
xcodegen generate
xcodebuild -project PCOS.xcodeproj -scheme PCOS \
  -destination 'platform=iOS Simulator,id=65704604-59EC-439F-B764-64FD273067BD' test
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Release \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

Expected: all suites pass, both audits report zero vulnerabilities, Release builds with production App Attest, repeat exact matching enabled, similar matching disabled, and Cloud Run remains private/disabled.

- [ ] **Step 7: Commit the probe and review-preparation artifacts only after rollback verification**

## Plan Self-Review Checklist

- Every approved UX string and privacy boundary maps to Tasks 5-6.
- Exact matching, similarity gating, corruption handling, LRU, and deletion map to Tasks 1-4.
- The 100-image/95%-precision gate maps to Task 7 and cannot silently emit an unsafe policy.
- Physical App Check validation proves integrity by reaching the entitlement gate without a model call, then rolls back in Task 8.
- Public App Store submission is intentionally excluded; Task 8 prepares materials and leaves the current production scanner disabled.
