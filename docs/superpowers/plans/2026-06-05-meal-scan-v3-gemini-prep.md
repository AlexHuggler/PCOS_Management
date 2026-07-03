# Meal Scan V3 Gemini Preparation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare CycleBalance Meal Scan V3 to use Gemini as the cheapest generic multimodal AI meal estimator while preserving review-before-save, privacy-forward copy, local nutrient math, structured persistence, and duplicate-call caching.

**Architecture:** Gemini should estimate visible foods, portion ranges, uncertainty, and warnings from a meal photo, then CycleBalance should map those candidates to local nutrition records and calculate final nutrients locally whenever possible. The app should cache scan results by normalized-image hash plus model/schema/prompt version so repeated photos do not trigger repeated API calls. Gemini output is an estimate source, not a medical or exact nutrition authority.

**Tech Stack:** SwiftUI, SwiftData, Swift concurrency, URLSession or a production-safe proxy client, CryptoKit, ImageIO/UIKit image normalization, existing Meal Scan V2 services, Google Gemini API structured outputs, XcodeGen, Swift Testing/XCTest.

---

## Current Decision

Use `gemini-2.5-flash-lite` as the default generic model for V3 cloud meal estimates.

Rationale:
- It is listed by Google as its smallest and most cost-effective model for at-scale usage.
- It supports text/image/video input and structured output.
- It is generic enough for food recognition, portion cues, and uncertainty language without requiring a specialized food-recognition vendor.
- It should be treated as a visual estimation layer only. CycleBalance should continue to calculate and persist nutrition using local records when matches exist.

Escalation rule:
- Use `gemini-2.5-flash-lite` first.
- Only retry with a stronger model, such as `gemini-2.5-flash`, when the user explicitly requests a retry or when a dev-only feature flag is enabled for evaluation.
- Never silently spend more on a stronger model in production.

Official references checked on 2026-06-05:
- Gemini pricing: https://ai.google.dev/gemini-api/docs/pricing
- Gemini image understanding: https://ai.google.dev/gemini-api/docs/image-understanding
- Gemini structured outputs: https://ai.google.dev/gemini-api/docs/structured-output
- Gemini API keys and security: https://ai.google.dev/gemini-api/docs/api-key
- Gemini context caching: https://ai.google.dev/gemini-api/docs/caching

---

## Product Boundaries

- Keep the feature language as "AI meal estimate."
- Do not call it exact, medical-grade, diagnostic, or guaranteed.
- Always allow review/edit before saving.
- Keep local-first behavior as the default app posture.
- Make the Gemini path explicit: the selected meal photo is sent to Gemini only when the user chooses the cloud estimate path.
- Preserve manual fallback and existing mock/local scanner behavior.
- Preserve original AI JSON and final user-confirmed JSON separately.
- Store structured item-level and meal-level nutrition data.
- Do not commit API keys.
- Do not embed production Gemini API keys directly in the shipped iOS app.

Recommended privacy copy:

> Cloud AI meal estimates send the selected meal photo to Gemini for analysis. You can review and edit everything before saving. Nutrition values are estimates and can vary by preparation, ingredients, and portion size. CycleBalance is not a medical device.

Recommended local-mode copy:

> Local meal estimates and nutrition logs stay on your device unless you choose to sync through iCloud.

---

## User Setup Checklist

Do these before asking Codex to implement V3:

1. Create or open a Google AI Studio project.
   - Go to https://aistudio.google.com
   - Open the API keys page.
   - Create a Gemini API key for a dedicated CycleBalance development project.

2. Restrict the key.
   - Restrict the key to the Gemini / Generative Language API.
   - Do not use a broad unrestricted key.
   - Do not paste the key into chat.

3. Add billing controls.
   - In Google Cloud billing, add a budget alert for the project.
   - Start with a low development budget.
   - Keep production usage disabled until the proxy/security decision is made.

4. Decide the security path.
   - Development-only option: Codex can wire a Debug-only direct Gemini client using a local uncommitted secret.
   - Production option: use a minimal server-side proxy so the API key is not extractable from the iOS app.
   - If you want no backend at all, Gemini must remain development-only or internal-test-only. A production iOS app should not ship a raw Gemini API key in the binary.

5. Create a local secrets file only if choosing the development-only direct client.
   - File: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/Config/LocalSecrets.xcconfig`
   - Add one line with the variable name below, then type your local debug key after the equals sign in your uncommitted file:

```xcconfig
GEMINI_API_KEY =
```

   - Confirm `Config/LocalSecrets.xcconfig` is ignored by git before adding the key.
   - Never commit this file.

6. Prepare evaluation meal images.
   - Create a local folder outside committed source, for example:

```text
/Users/alexhuggler/Desktop/AI Work/PCOS/MealScanV3EvaluationImages
```

   - Add 15-30 real-world meal photos:
     - home-cooked meal
     - restaurant meal
     - mixed bowl
     - salad with dressing
     - pasta
     - smoothie
     - packaged food with visible label
     - snack/barcode-style food
     - leftovers/container meal
   - Avoid faces, sensitive surroundings, or identifying information.

7. Decide launch positioning.
   - Recommended: keep Gemini behind a feature flag for TestFlight/internal testing first.
   - Suggested flag names:
     - `mealScan.enableGeminiMealScan`
     - `mealScan.enableGeminiMealScanDebugDirect`
     - `mealScan.enableGeminiFallbackModel`
     - `mealScan.enableMealScanResultCache`

8. Decide whether meal photos may be retained.
   - If photo retention is off, cache only the normalized image hash and response JSON.
   - If photo retention is on, store the local photo path only after the user saves the meal.

---

## Copy-Paste Codex Prompt For V3 Implementation

Use this in the next implementation session after the setup checklist is done:

```text
You are working in the CycleBalance iOS app repo at:
/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management

Implement Meal Scan V3 Gemini integration using the existing Meal Scan V2 architecture. Preserve the dirty worktree. Do not revert unrelated user changes. `project.yml` is the source of truth; regenerate `PCOS.xcodeproj` with XcodeGen if source or resource membership changes.

Goal:
Add a feature-flagged Gemini cloud estimation path for AI meal estimates. Gemini should identify likely foods, portion estimates/ranges, confidence, uncertainty, and hidden-ingredient warnings from a meal photo. CycleBalance must then map those candidates to local nutrition records and calculate/store structured nutrients locally whenever possible. The user must review/edit before saving.

Use:
- Default model: `gemini-2.5-flash-lite`
- Optional fallback model: `gemini-2.5-flash`, disabled unless explicitly enabled
- Structured JSON response schema
- App-level duplicate scan cache
- Existing SwiftData persistence for `MealEntry`, `MealScanFoodItem`, `MealScanNutritionSummary`, `MealScanMetadata`, and `NutritionImportRecord`

Do not:
- Commit API keys
- Ship a production iOS direct API key
- Remove local/mock scan fallback
- Make medical claims
- Auto-save without review
- Trust Gemini nutrition numbers over local database math when a local match exists

Security:
- If using direct Gemini calls, make them Debug-only and require an uncommitted `Config/LocalSecrets.xcconfig`.
- For production, add interfaces that can call a future server-side proxy without exposing the Gemini key in the app.

Core files to inspect first:
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Models/MealScanModels.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Services/MealScanServices.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Services/MealScanProductionScaffolds.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Core/Services/NutritionIntegrationServices.swift`
- `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/project.yml`

Add or prepare:
1. Feature flags:
   - `enableGeminiMealScan`
   - `enableGeminiMealScanDebugDirect`
   - `enableGeminiFallbackModel`
   - `enableMealScanResultCache`

2. Gemini service interfaces:
   - `RemoteMealScanEstimating`
   - `GeminiMealScanClient`
   - `GeminiMealScanProxyClient`
   - `GeminiMealScanRequestBuilder`
   - `GeminiMealScanResponseParser`

3. Structured response DTOs:
   - `GeminiMealEstimateResponse`
   - `GeminiMealEstimateItem`
   - `GeminiMealEstimateNutritionFallback`
   - `GeminiMealEstimateWarning`

4. Cache layer:
   - Exact cache key = SHA256(model ID + schema version + prompt version + normalized JPEG bytes + locale + optional app build)
   - Persistent cache model or repository = stores cache key, model ID, prompt version, schema version, createdAt, lastAccessedAt, response JSON, confidence, and source image hash
   - Do not store raw image bytes in the cache
   - Purge unsaved scan cache entries after 24 hours unless product requests otherwise
   - Preserve saved meal metadata separately through existing `MealScanMetadata`

5. Nutrition mapping:
   - Use Gemini item `canonical_query` to search `NutritionLookupService`.
   - If local match exists, calculate nutrients using `MealNutritionCalculator`.
   - If local match is missing and Gemini provided nutrient fallback, allow it only as low-confidence, editable, clearly labeled estimated data.
   - Add a warning when oil, sauce, dressing, restaurant prep, or mixed dish uncertainty is present.

6. UI/ViewModel behavior:
   - If Gemini scan succeeds, show the normal review screen.
   - If Gemini scan fails, falls back to mock/local/manual path without crashing.
   - If confidence is low, prompt manual review.
   - If cache hit occurs, show a quiet source note such as "Reused a recent estimate for this photo."
   - Keep the language "AI meal estimate."

7. Tests:
   - Structured response decoding
   - Invalid JSON fallback
   - Cache key stability
   - Cache hit avoids API call
   - Cache miss calls API once
   - Local nutrition match overrides Gemini nutrition fallback
   - Gemini fallback nutrition is low confidence
   - Hidden oil/sauce lowers confidence
   - ViewModel routes success, failure, and low-confidence states
   - Persistence stores original Gemini JSON and final user-confirmed JSON

Verification:
- Run focused Meal Scan tests first.
- Run nutrition integration tests.
- Regenerate Xcode project if project membership changes:
  `xcodegen generate`
- Run full test suite:
  `xcodebuild test -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17'`
```

---

## Proposed V3 File Structure

Create these only during implementation:

```text
PCOS/PCOS/Features/Meals/MealScan/Remote/
  RemoteMealScanEstimating.swift
  GeminiMealScanClient.swift
  GeminiMealScanProxyClient.swift
  GeminiMealScanRequestBuilder.swift
  GeminiMealScanResponseParser.swift
  GeminiMealScanSchemas.swift
  MealScanImageNormalizer.swift
  MealScanResultCache.swift
  MealScanResultCacheRecord.swift

PCOS/PCOSTests/
  GeminiMealScanResponseParserTests.swift
  GeminiMealScanRequestBuilderTests.swift
  MealScanResultCacheTests.swift
  GeminiMealNutritionMappingTests.swift
```

Keep existing files as the integration points:

```text
PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift
PCOS/PCOS/Features/Meals/MealScan/Services/MealScanServices.swift
PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift
PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift
```

---

## Gemini Structured Output Contract

Use a strict JSON schema. Keep output short to control cost.

Required top-level fields:

```json
{
  "meal_name": "string",
  "overall_confidence": "low | medium | high | unknown",
  "needs_manual_review": true,
  "is_restaurant_or_takeout_likely": false,
  "hidden_ingredient_risk": "none | low | medium | high | unknown",
  "hidden_ingredient_prompts": ["oil", "butter", "dressing", "sauce"],
  "items": [],
  "warnings": [],
  "model_notes": "short string"
}
```

Required item fields:

```json
{
  "display_name": "string",
  "canonical_query": "string",
  "estimated_grams": 120.0,
  "estimated_grams_min": 90.0,
  "estimated_grams_max": 160.0,
  "serving_description": "about 1 cup cooked",
  "confidence": "low | medium | high | unknown",
  "portion_method": "visual_estimate | label_visible | serving_heuristic | manual_needed",
  "is_mixed_dish": false,
  "visible_cues": ["string"],
  "warnings": ["string"],
  "nutrition_fallback": {
    "calories_kcal": 0,
    "protein_grams": 0,
    "carbs_grams": 0,
    "fat_grams": 0,
    "fiber_grams": 0,
    "sugar_grams": 0,
    "sodium_mg": 0
  }
}
```

Prompt rules:
- Ask Gemini to identify visible ingredients and portion ranges, not to make medical claims.
- Ask it to return `manual_needed` when food is obscured, mixed, or uncertain.
- Ask it to flag hidden oil, sauces, dressing, and restaurant/takeout uncertainty.
- Ask it to prefer common canonical names that can map to USDA-style local records.
- Ask it to keep nutrient fallback values optional and lower confidence than local lookup.

---

## Caching Design

Use app-level caching as the primary duplicate-call prevention.

Cache key:

```text
SHA256(
  modelID + "|" +
  promptVersion + "|" +
  schemaVersion + "|" +
  localeIdentifier + "|" +
  normalizedJPEGBytes
)
```

Image normalization:
- Fix orientation.
- Strip metadata.
- Resize to a cost-conscious max dimension, initially 768-1024 px.
- Encode deterministic JPEG quality, initially 0.72-0.80.
- Hash the normalized bytes, not the original photo.

Cache behavior:
- Exact cache hit returns cached structured response without calling Gemini.
- Exact cache miss calls Gemini once, stores the raw structured response, then maps to local nutrition.
- Optional perceptual duplicate detection may be added later, but should not auto-reuse unless confidence is high and the user is still reviewing.
- Cache entries for unsaved scans should be purged after 24 hours.
- Saved meals keep original/final JSON in existing metadata, independent of transient scan cache.
- Do not store raw photos in the cache.

Gemini context caching:
- Do not rely on Gemini context caching for duplicate meal photos.
- Context caching helps repeated long prompt prefixes, documents, or media, not full response dedupe.
- Keep the prompt prefix stable so Gemini's implicit caching has a chance to help, but implement local cache first.

---

## Nutrition Mapping Rules

Priority order:

1. Local exact food ID match from aliases/templates.
2. Local search match by Gemini `canonical_query`.
3. USDA SQLite/local database match when bundled.
4. Fixture nutrition match.
5. Gemini nutrient fallback, only when no local match exists.
6. Manual user input.

Rules:
- Local nutrition math wins over Gemini nutrition fallback.
- Gemini fallback must be stored as low confidence and editable.
- Net carbs = max(carbs - fiber, 0).
- Preserve hidden ingredient prompts.
- If hidden oil/sauce is selected, add the existing oil/dressing adjustment through the current hidden ingredient flow.
- Save final user-confirmed values into existing Meal Scan SwiftData records.

---

## Test Plan

Focused tests:

- `GeminiMealScanResponseParserTests`
  - valid response decodes
  - missing optional nutrition fallback decodes
  - invalid confidence becomes unknown
  - malformed JSON returns a recoverable scan error

- `MealScanResultCacheTests`
  - same normalized image creates same key
  - changed prompt version creates different key
  - cache hit avoids remote call
  - cache miss calls remote once
  - expired unsaved entry is ignored

- `GeminiMealNutritionMappingTests`
  - local fixture match calculates nutrients locally
  - local match overrides Gemini fallback numbers
  - unmatched item uses Gemini fallback as low confidence
  - hidden oil/sauce warning lowers confidence

- `MealScanViewModelTests`
  - Gemini success routes to review
  - Gemini failure routes to manual fallback
  - low-confidence response prompts review
  - editing grams recalculates totals
  - saving preserves original Gemini JSON and final confirmed JSON

Verification commands:

```bash
cd "/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management"
xcodegen generate
xcodebuild test -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PCOSTests/GeminiMealScanResponseParserTests
xcodebuild test -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PCOSTests/MealScanResultCacheTests
xcodebuild test -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PCOSTests/GeminiMealNutritionMappingTests
xcodebuild test -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Implementation Phases For A Future Session

### Task 1: Feature Flags And Config Guardrails

**Files:**
- Modify: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/MealScanFeatureFlags.swift`
- Modify: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/project.yml`
- Create or update tests for flag defaults.

- [ ] Add Gemini flags, default off in Release.
- [ ] Add Debug-only config reading for local development.
- [ ] Verify Release builds cannot use direct API key path unless a proxy path exists.

### Task 2: Structured DTOs And Parser

**Files:**
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanSchemas.swift`
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanResponseParser.swift`
- Test: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOSTests/GeminiMealScanResponseParserTests.swift`

- [ ] Write parser tests first.
- [ ] Decode strict schema.
- [ ] Convert unknown enum strings to `.unknown`.
- [ ] Return typed recoverable errors.

### Task 3: Request Builder And Image Normalizer

**Files:**
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/MealScanImageNormalizer.swift`
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRequestBuilder.swift`
- Test: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOSTests/GeminiMealScanRequestBuilderTests.swift`

- [ ] Normalize image orientation, metadata, size, and JPEG quality.
- [ ] Build a minimal structured-output request.
- [ ] Keep prompt text short and stable.
- [ ] Include prompt/schema/model versions in request metadata.

### Task 4: Cache Layer

**Files:**
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/MealScanResultCache.swift`
- Create if SwiftData-backed: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/MealScanResultCacheRecord.swift`
- Test: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOSTests/MealScanResultCacheTests.swift`

- [ ] Implement hash key from normalized image bytes and versions.
- [ ] Store response JSON, timestamps, confidence, and metadata only.
- [ ] Purge unsaved/expired entries.
- [ ] Verify cache hit skips API call.

### Task 5: Gemini Client And Proxy Interface

**Files:**
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/RemoteMealScanEstimating.swift`
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanClient.swift`
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanProxyClient.swift`

- [ ] Implement protocol-first client.
- [ ] Keep direct Gemini client Debug-only.
- [ ] Keep proxy client as the production-safe interface.
- [ ] Add timeout, retry, and friendly failure mapping.

### Task 6: Nutrition Mapping Into Existing Meal Scan Drafts

**Files:**
- Create: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealNutritionMapper.swift`
- Modify: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Services/MealScanServices.swift`
- Test: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOSTests/GeminiMealNutritionMappingTests.swift`

- [ ] Map Gemini items to `MealFoodItemDraft`.
- [ ] Search local nutrition by canonical query.
- [ ] Calculate nutrients locally when matched.
- [ ] Use Gemini fallback only as low-confidence editable data.
- [ ] Preserve warnings and hidden ingredient risk.

### Task 7: Pipeline Wiring And ViewModel Behavior

**Files:**
- Modify: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Services/MealScanServices.swift`
- Modify: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift`
- Modify if needed: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`

- [ ] Route to Gemini only when enabled and user consents to cloud scan.
- [ ] Use cache before remote call.
- [ ] Fall back to local/mock/manual on failure.
- [ ] Show cache source note when applicable.
- [ ] Keep all review/edit/save behavior unchanged.

### Task 8: Persistence And Export Compatibility

**Files:**
- Modify if needed: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Repositories/SwiftDataMealLogRepository.swift`
- Modify if adding cache model to schema: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/App/CycleBalanceApp.swift`
- Modify if adding cache export/deletion behavior: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/App/SettingsDataDeletionService.swift`

- [ ] Store original Gemini JSON as original prediction JSON.
- [ ] Store final confirmed JSON after edits.
- [ ] Keep existing meal rollup fields populated.
- [ ] Ensure cache data is local and deletable.

### Task 9: Privacy Copy And Safety Checks

**Files:**
- Modify if needed: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift`
- Modify if needed: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management/PCOS/PCOS/App/SettingsView.swift`

- [ ] Show local-vs-cloud copy clearly.
- [ ] Do not imply exact calorie scan.
- [ ] Include not-a-medical-device disclaimer.
- [ ] Require review before save.

### Task 10: Full Verification

**Files:**
- No source changes unless tests reveal a bug.

- [ ] Run focused tests.
- [ ] Run full test suite.
- [ ] Run `git diff --check`.
- [ ] Report exact files changed and tests run.

---

## Open Product Decisions Before Production

1. Is Gemini allowed in public TestFlight, or only internal builds first?
2. Will production use a proxy, or should Gemini remain Debug/internal-only?
3. Should the app keep a cloud scan history cache for saved meals indefinitely, or only preserve original/final JSON as part of saved meal metadata?
4. Should stronger-model retry ever be exposed to users, or only to internal QA?
5. Should users be able to disable cloud AI meal estimates separately from local AI meal estimates?

Recommended answers:
- Internal/TestFlight first.
- Use a proxy before public production.
- Cache transient unsaved scans for 24 hours; saved meals keep metadata.
- Stronger-model retry internal-only at first.
- Yes, expose a separate cloud AI toggle.
