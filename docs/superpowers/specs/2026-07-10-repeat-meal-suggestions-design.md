# CycleBalance Repeat Meal Suggestions Design

**Status:** Approved in conversation on July 10, 2026

## Scope

This design covers the repeat-meal cache and its user experience. The labeled meal-photo evaluation set, physical-device App Check validation, and App Store privacy/review rollout remain separate follow-on workstreams. The cache design supplies the repeated-photo data and quality gates those workstreams need.

## Goals

- Make reusing a previously confirmed meal feel routine and low stakes.
- Avoid an AI request and quota charge when the user chooses a prior reviewed meal.
- Prefer user-confirmed nutrition over an earlier raw model response.
- Recognize the identical image immediately and support conservative similar-photo suggestions after evaluation.
- Preserve CycleBalance's local-first privacy model and editable review-before-save flow.

## Non-Goals

- Do not automatically save or silently accept nutrition.
- Do not share repeat-meal records across users or devices.
- Do not send image fingerprints to Cloud Run, Gemini, RevenueCat, or analytics.
- Do not use cross-user or global meal-result caching.
- Do not enable similarity matching in Release before it meets the evaluation precision gate.

## User Experience

After a user selects or captures a meal photo, CycleBalance checks the local repeat-meal cache before starting a remote estimate. A qualifying match presents a compact, non-blocking suggestion in the existing scan flow:

> **Looks familiar**
>
> Chicken rice bowl - 540 cal - last logged Tuesday
>
> You can adjust anything before saving.

The actions are:

- **Use Previous Meal**: opens the normal editable nutrition draft using the last user-confirmed values. It makes no model call and consumes no scan quota.
- **Scan as New**: dismisses the suggestion for the current photo and continues through the existing exact-result cache and remote estimate flow.

An exact image match uses the same quiet suggestion. A conservative visual match uses the same interaction so the app never implies certainty. The UI does not expose similarity scores, cache terminology, warnings, or extra confirmation dialogs. If no match qualifies, scanning continues normally without showing a placeholder or delay message.

The suggestion must support Dynamic Type, VoiceOver, every shipped localization, and both botanical and lunar appearances. Buttons use the app's established command hierarchy rather than custom iconography.

## Architecture

### Existing Cache

The existing `MealScanResultCache` remains an invisible 24-hour transport cache keyed by model, schema, prompt, normalized image hash, locale, and app build. It may reuse a raw provider response for the identical normalized image, but it is not the source of truth for repeat-meal suggestions.

The Cloud Run cache remains per anonymous RevenueCat user and exact image hash. It stores structured output and hashes, never raw images. No cross-user cache is introduced.

### Confirmed Repeat Cache

A new `MealScanRepeatCache` stores up to the 100 most recently used, user-confirmed meals in SwiftData. Each `MealScanRepeatCacheRecord` contains:

- `id`
- `sourceMealID`
- `sourceImageHash`
- a securely archived local Vision feature-print observation
- the explicit Vision request revision used to create the feature print
- a versioned `RepeatMealDraftSnapshot` JSON payload containing the final user-confirmed meal name, type, items, portions, nutrition, confidence, warnings, hidden-ingredient choice, and source metadata
- the snapshot schema version
- meal name, meal type, calories, protein, carbohydrates, and fat for suggestion display
- creation, last-used, and last-matched timestamps
- reuse count

The versioned draft snapshot is the canonical reuse payload. It is created from the final reviewed state at save time and decodes directly into the existing editable draft. Display fields are denormalized only to render the suggestion without repeatedly decoding JSON.

Saving the same exact image updates its existing record instead of creating a duplicate. Saving a genuinely different viewpoint may create another record for the same meal, improving future similarity coverage. When the cache exceeds 100 records, it removes least-recently-used records after a successful save. Deleting a source meal removes its repeat record. Delete All Data removes every repeat record. Corrupt or incompatible records are removed when encountered.

### Image Fingerprinting

`MealImageFingerprinting` is an injectable boundary with a Vision implementation and deterministic test doubles.

The production implementation performs:

1. The existing normalized-image SHA-256 calculation for exact matching.
2. `VNGenerateImageFeaturePrintRequest` revision 2 for visual similarity.
3. Secure archiving of `VNFeaturePrintObservation`, which conforms to `NSSecureCoding`.

Feature prints remain on device and are not reversible into the source photo. If Vision cannot create or compare a feature print, CycleBalance skips similarity matching and continues with the normal scan. Fingerprint failure is never a user-facing scan failure.

### Match Policy

Exact SHA-256 matches are eligible immediately.

Similar-photo matching uses a versioned `MealRepeatSimilarityPolicy` containing an approved maximum distance and minimum nearest-neighbor margin. A candidate is suggested only when both conditions pass. The policy is produced from the labeled evaluation set by choosing the highest-recall configuration that maintains at least 95% suggestion precision. Ambiguous nearest neighbors are suppressed.

Until an approved policy artifact is bundled:

- exact-image suggestions are enabled in Release;
- Vision feature-print generation and storage are implemented;
- similar-photo suggestions remain disabled in Release;
- tests use an injected deterministic policy.

This makes a missed suggestion acceptable and a wrong suggestion deliberately rare.

## Data Flow

1. The user supplies a photo.
2. The existing image normalizer creates normalized JPEG data and its SHA-256 hash.
3. `MealScanRepeatCache` checks exact matches, then eligible similar matches.
4. A match moves `MealScanViewModel` to a repeat-suggestion phase without calling App Check, RevenueCat, the proxy, or Gemini.
5. **Use Previous Meal** decodes the versioned snapshot into the unified editable draft, marks the source as `reusedMeal`, updates cache usage metadata, and moves to review.
6. **Scan as New** bypasses repeat matching once for that selected photo and continues through the normal scanner.
7. Saving a reviewed photo-based meal inserts or updates its repeat record using the final confirmed values and current fingerprint.

Reusing a meal never saves automatically. The user can change the meal name, items, portions, hidden ingredients, and nutrients before saving.

## Failure Handling

- Fingerprint generation failure: continue with a normal scan.
- Corrupt feature-print archive: delete the record and continue.
- Incompatible Vision observation: ignore and delete the record.
- Corrupt or unsupported draft snapshot: delete the record and continue.
- Missing source meal: delete the orphaned record and continue.
- Similarity-policy unavailable: exact matching remains available; similarity is skipped.
- Remote scanner unavailable after **Scan as New**: preserve the existing manual fallback behavior.

Cache maintenance failures are logged without image data or nutrition contents and do not prevent manual or remote meal entry.

## Privacy And Security

- Raw photos follow the existing photo-retention flag and are not required by the repeat cache.
- The cache stores only an exact hash, a local Vision feature print, reviewed meal data, and maintenance metadata.
- No cache identifiers or feature prints leave the device.
- The existing server cache remains user-scoped and exact-match only.
- App Check, RevenueCat, quota, and budget gates remain unchanged for fresh remote scans.
- The repeat cache participates in meal deletion, Delete All Data, and privacy-source tests. Internal hashes and feature prints are not exported; the saved meal itself continues through the existing meal-data export path.

## Feature Flags

- `mealScan.enableRepeatMealSuggestions`: enabled in Release after implementation verification; controls exact reviewed-meal suggestions.
- `mealScan.enableSimilarMealSuggestions`: disabled in Release until the labeled evaluation policy reaches the precision gate.

The existing `mealScan.enableMealScanResultCache` continues to control the raw exact-response transport cache independently.

## Testing

### Unit And Service Tests

- Exact hashes return the reviewed meal and do not invoke the remote estimator.
- Different hashes do not exact-match.
- Similar candidates require both distance and nearest-neighbor margin thresholds.
- Ambiguous or incompatible feature prints produce no suggestion.
- **Scan as New** bypasses the suggestion once and invokes the existing scanner.
- **Use Previous Meal** populates an editable draft from the versioned final confirmed snapshot.
- Saving user edits updates the canonical repeat payload.
- Least-recently-used eviction preserves the newest 100 records.
- Meal deletion and Delete All Data remove repeat records.
- Corrupt records fail open to normal scanning.

### UI And Accessibility Tests

- The suggestion uses the approved copy and two clear actions.
- No similarity percentage or alarming warning language appears.
- Dynamic Type does not clip the meal name, macros, or actions.
- VoiceOver announces the meal summary and both choices in order.
- The user always reaches the standard review screen before save.

### Evaluation Gate

The repeated-photo dataset will contain 100 normalized images: 20 meal identities with four views each, plus 20 visually similar negative examples. Production similarity matching requires:

- at least 95% suggestion precision;
- zero known high-risk cross-meal matches in the reviewed negative set;
- match latency below 200 milliseconds on the connected iPhone 15 Pro;
- no remote request or quota consumption when reuse is selected.

## Rollout

1. Ship and verify exact reviewed-meal suggestions with similarity disabled.
2. Build the repeated-photo evaluation set and calibrate the policy.
3. Run the approved physical-device App Check and cache tests.
4. Enable similarity in an internal build after the precision gate passes.
5. Update privacy and App Review materials, increment the build number above 17, and submit the production-enabled binary only after final owner approval.

## Acceptance Criteria

- Reusing an exact previously confirmed meal takes one tap and opens an editable draft.
- Reuse makes no App Check, RevenueCat, proxy, or Gemini request and consumes no quota.
- Fresh scanning remains one tap away through **Scan as New**.
- User-confirmed values, not raw AI output, are reused.
- All repeat data remains local and is deleted with its source meal or Delete All Data.
- Release similarity matching cannot turn on without an approved evaluation policy.
