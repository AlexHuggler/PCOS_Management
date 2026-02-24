# CycleBalance — Issue Log

> Generated 2026-02-24 from full codebase audit (28 Swift files).
> Ranked: **Critical** (crashes / data loss) → **High** (performance / UX) → **Medium** (tech debt).

---

## Critical — Crashes / Data Loss

### C-1. Duplicate symptom entries on re-save

| | |
|---|---|
| **File** | `SymptomViewModel.swift:51-64`, `SymptomViewModel.swift:111-121` |
| **Root Cause** | `prefillTodaysSymptoms()` loads existing entries into the form; `saveSymptoms()` always inserts **new** `SymptomEntry` records without deleting the old ones. |
| **Impact** | Every time a user opens SymptomLogView, edits anything, and taps Save, the entire set of today's symptoms is duplicated. Repeat opens = exponential duplication. |
| **Reproduction** | Log 3 symptoms → close → reopen SymptomLogView → tap Save without changes → query shows 6 entries. |
| **Fix Strategy** | Before inserting new entries in `saveSymptoms()`, delete today's existing `SymptomEntry` records. Or switch to an upsert pattern keyed on `(date, symptomType)`. |

### C-2. Silent `modelContext.save()` — data may not persist

| | |
|---|---|
| **Files** | `CycleViewModel.swift:67`, `CycleViewModel.swift:88`, `SymptomViewModel.swift:62` |
| **Root Cause** | `try? modelContext.save()` swallows errors. If the save fails (e.g., CloudKit conflict, disk full, schema migration), the user sees the "Saved" feedback overlay but data is lost. |
| **Impact** | Silent data loss. User believes period/symptoms were recorded; they were not. |
| **Fix Strategy** | Replace `try?` with `do/try/catch`. Propagate error state to the view. Show an error alert on failure instead of the checkmark overlay. |

### C-3. Silent `modelContext.fetch()` — empty state masks database errors

| | |
|---|---|
| **Files** | `CycleViewModel.swift:38, 50, 199`, `SymptomViewModel.swift:80, 107` |
| **Root Cause** | `(try? modelContext.fetch(descriptor)) ?? []` returns an empty array on any fetch error. |
| **Impact** | A corrupted store or CloudKit issue causes the app to display "No data" rather than an error, making the problem invisible to both user and developer. |
| **Fix Strategy** | Use `do/try/catch`, log errors via `os.Logger`, surface a user-facing error state. |

---

## High — Performance / UX

### H-1. No error logging infrastructure

| | |
|---|---|
| **Files** | Entire codebase |
| **Root Cause** | No `os.Logger`, no `print()` guards, no crash reporting. Zero observability. |
| **Impact** | Production issues are undiagnosable. CloudKit sync failures, data corruption, and edge-case crashes leave no trace. |
| **Fix Strategy** | Add `import os` and create a shared `Logger` extension. Replace all `try?` with logged `do/catch`. |

### H-2. ViewModel recreated on every `.onAppear`

| | |
|---|---|
| **Files** | `TodayView.swift:44-48`, `CalendarMonthView.swift:46-51`, `CycleLogView.swift:83-85`, `CycleDetailView.swift:26-30` |
| **Root Cause** | Each view creates `CycleViewModel(modelContext:)` inside `.onAppear`. SwiftUI can call `.onAppear` multiple times (e.g., tab switches, sheet dismissals). This triggers redundant `loadData()` fetches. |
| **Impact** | Wasted work on every tab switch. Noticeable on devices with large datasets or slow CloudKit sync. |
| **Fix Strategy** | Guard with `if viewModel == nil { … }` or use a lazy-init pattern. Better: inject a shared ViewModel via `.environment()` or move to `@Query`. |

### H-3. DateFormatter created per render cycle

| | |
|---|---|
| **Files** | `CalendarMonthView.swift:161-165`, `CycleDetailView.swift:157-161` |
| **Root Cause** | `DateFormatter()` is allocated inside computed properties (`monthYearString`, `formatDate`), called on every SwiftUI render. `DateFormatter` is expensive to create. |
| **Impact** | Micro-stutters during calendar month navigation and cycle list rendering. |
| **Fix Strategy** | Move `DateFormatter` instances to `static let` on the type or a shared cache. |

### H-4. Hardcoded font sizes break Dynamic Type

| | |
|---|---|
| **Files** | `TodayView.swift:58` (`.system(size: 56)`), `CycleDetailView.swift:39` (`.system(size: 48)`), `SeverityPicker.swift:36` (`.system(size: 9)`), `SavedFeedbackOverlay.swift:11` (`.system(size: 48)`) |
| **Root Cause** | Fixed-point font sizes ignore the user's Dynamic Type setting. |
| **Impact** | Users with accessibility text sizes see unchanged hero numbers — breaks Apple's HIG and accessibility guidelines. |
| **Fix Strategy** | Use `@ScaledMetric` for dynamic sizing, or use semantic text styles (`.largeTitle`, `.title`) with font design overrides. |

### H-5. CycleViewModel is a God Object

| | |
|---|---|
| **File** | `CycleViewModel.swift` (207 lines, 15+ methods) |
| **Root Cause** | Single class handles: data loading, period logging, cycle management, prediction orchestration, form state, and calendar query helpers. |
| **Impact** | Hard to test, hard to reason about, single points of failure. Changes to logging affect prediction. |
| **Fix Strategy** | Extract `CycleLogService` (insert/save), `CycleQueryService` (fetch/filter), and keep ViewModel as thin orchestrator. |

### H-6. CalendarMonthView assumes Sunday-start week

| | |
|---|---|
| **File** | `CalendarMonthView.swift:12, 167-174` |
| **Root Cause** | `daysOfWeek = ["Sun", "Mon", …]` is hardcoded and `firstWeekdayOffset` uses `calendar.component(.weekday, …) - 1` which assumes weekday 1 = Sunday. Locales with Monday-start weeks (most of Europe) will misalign. |
| **Impact** | Wrong day-of-week alignment for non-US locale users. |
| **Fix Strategy** | Use `calendar.firstWeekday` and `calendar.shortWeekdaySymbols` to generate the header dynamically. |

### H-7. `@Query` predicate captures stale `Date()`

| | |
|---|---|
| **File** | `TodayView.swift:10-17` |
| **Root Cause** | `#Predicate { entry.date >= Date().addingTimeInterval(-86400) }` — the `Date()` is captured when the `@Query` property wrapper initializes. If the view stays alive (e.g., app in foreground across midnight), the predicate never updates. |
| **Impact** | "Today's Symptoms" section shows stale data after midnight until user force-restarts or navigates away and back. |
| **Fix Strategy** | Move the query into the ViewModel with an explicit refresh trigger, or use `.onAppear` to reset the date. |

### H-8. No accessibility labels on CalendarDayCell

| | |
|---|---|
| **File** | `CalendarMonthView.swift:206-239` |
| **Root Cause** | `CalendarDayCell` shows only a number and a colored circle. No `.accessibilityLabel`, no `.accessibilityHint`. VoiceOver users hear only the day number. |
| **Impact** | VoiceOver users cannot determine: whether a day has period data, what the flow intensity was, or that today is highlighted. Calendar is effectively unusable for blind users. |
| **Fix Strategy** | Add `.accessibilityLabel("February 24, heavy flow")` composed from the entry data. |

---

## Medium — Tech Debt

### M-1. `SymptomEntry.symptomType` stored as `String`, not `SymptomType` enum

| | |
|---|---|
| **File** | `SymptomEntry.swift:9` |
| **Root Cause** | `var symptomType: String` stores the raw value. Every consumer must call `SymptomType(rawValue: entry.symptomType)` and handle `nil`. |
| **Impact** | Boilerplate, fragile — if a `SymptomType` raw value changes, existing data becomes orphaned. The convenience init papers over this but doesn't fix it. |
| **Fix Strategy** | Store `SymptomType` directly (SwiftData supports `Codable` enums). Add a lightweight migration. |

### M-2. `Insight.body` property name shadows SwiftUI convention

| | |
|---|---|
| **File** | `Insight.swift:10` |
| **Root Cause** | Property named `body` on a class. While it compiles (no protocol conformance conflict), it creates cognitive overhead since `body` is the canonical SwiftUI View entry point. |
| **Impact** | Developer confusion, especially in code review or when an AI assistant reads the code. |
| **Fix Strategy** | Rename to `content` or `description`. Requires schema migration. |

### M-3. Six SwiftData models with no UI

| | |
|---|---|
| **Files** | `BloodSugarReading.swift`, `SupplementLog.swift`, `MealEntry.swift`, `HairPhotoEntry.swift`, `DailyLog.swift`, `Insight.swift` (partial — has `InsightsView` but no write path) |
| **Root Cause** | Models defined in the schema and registered in the `ModelContainer`, but no corresponding ViewModels or data-entry Views exist. |
| **Impact** | CloudKit sync is set up for these tables with no way to populate them. Schema surface area with no benefit. If CloudKit encounters issues with empty tables, debugging is harder. |
| **Fix Strategy** | Either build the remaining features or remove unused models from the schema until needed. |

### M-4. No `Hashable` conformance on `@Model` classes used in `ForEach`

| | |
|---|---|
| **Files** | `CycleDetailView.swift:131` (`ForEach(…, id: \.id)`), `InsightsView.swift:31` (`ForEach(insights, id: \.id)`) |
| **Root Cause** | `ForEach` uses `id: \.id` instead of relying on `Identifiable`. SwiftData `@Model` classes don't auto-conform to `Hashable`. |
| **Impact** | Works correctly but is fragile — if `id` property changes or is removed, the `ForEach` breaks at compile time with an unhelpful error. |
| **Fix Strategy** | Add explicit `Identifiable` conformance or use `ForEach(items)` without `id:` since `@Model` classes are already reference types with stable identity. |

### M-5. Hardcoded padding/spacing values inconsistent across views

| | |
|---|---|
| **Files** | Throughout — padding varies: 4, 6, 8, 10, 12, 14, 16, 20, 24, 32 |
| **Root Cause** | No spacing scale in `AppTheme`. Each view picks its own magic numbers. |
| **Impact** | Inconsistent visual rhythm. Makes design system maintenance harder. |
| **Fix Strategy** | Define spacing constants in `AppTheme` (e.g., `.spacing4`, `.spacing8`, `.spacing16`). |

### M-6. `FlowIntensity.none` case is confusing in period logging context

| | |
|---|---|
| **File** | `Enums.swift:6` |
| **Root Cause** | `FlowIntensity` has a `.none` case. In `CycleLogView`, selecting "None" while logging a period day is contradictory. |
| **Impact** | User can log "period day with no flow" — semantically odd. |
| **Fix Strategy** | Either remove `.none` from the `FlowIntensityPicker` during period logging, or rename to `.noFlow` and hide it contextually. |

### M-7. HealthKit entitlement declared but unused

| | |
|---|---|
| **Files** | `CycleBalance.entitlements`, `project.yml` (Info.plist keys) |
| **Root Cause** | HealthKit access entitlement and usage description strings are configured, but no `import HealthKit` or `HKHealthStore` exists in any Swift file. |
| **Impact** | Apple may reject the app during review for claiming HealthKit access without using it. |
| **Fix Strategy** | Remove entitlement and Info.plist keys until HealthKit integration is implemented. |

### M-8. `CyclePredictionEngine` does not handle edge case of all same-length cycles

| | |
|---|---|
| **File** | `CyclePredictionEngine.swift:115-118` |
| **Root Cause** | `calculateVariance()` returns 0 when `values.count == 1`. But it also returns 0 when all values are identical (variance of `[28, 28, 28]` = 0). This makes `standardDeviation = 0` and `windowHalf = minimumWindowDays / 2.0 = 2.5`, which is fine. However, `confidence = 1.0` when all cycles are identical — which may be overconfident for PCOS users with limited data. |
| **Impact** | Low — the minimum 5-day window prevents false precision. But confidence reporting could mislead. |
| **Fix Strategy** | Cap confidence at `0.9` or add a "recency" factor that decays confidence when the most recent cycle was long ago. |

---

## Summary

| Severity | Count | Key Theme |
|---|---|---|
| **Critical** | 3 | Silent data loss, duplicate entries |
| **High** | 8 | No logging, perf waste, accessibility, locale |
| **Medium** | 8 | Type safety, dead code, naming, edge cases |
| **Total** | **19** | |

### Recommended Fix Order

1. **C-1** (duplicate entries) — Active bug causing data corruption
2. **C-2 + C-3** (silent try?) — Enable `do/catch` + **H-1** (add Logger)
3. **H-8** (calendar accessibility) — Blocks accessibility compliance
4. **H-4** (Dynamic Type) — Blocks accessibility compliance
5. **H-6** (locale calendar) — Breaks for non-US users
6. **H-2** (ViewModel recreation) — Performance
7. **H-3** (DateFormatter caching) — Performance
8. **H-5** (God Object) — Maintainability
9. **M-1** (SymptomType as String) — Type safety
10. **M-7** (HealthKit entitlement) — App Store review risk
