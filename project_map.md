# CycleBalance — Project Architecture Map

> Generated 2026-02-24. 28 Swift files, 0 external dependencies.

---

## 1. Architectural Overview

| Aspect | Choice |
|---|---|
| **UI Framework** | SwiftUI (pure — no UIKit imports) |
| **Architecture Pattern** | MVVM with `@Observable` (Swift 5.9 macro) |
| **Persistence** | SwiftData (`@Model`, `ModelContainer`, `ModelContext`) |
| **Networking** | None implemented yet |
| **Dependency Management** | None — zero third-party packages |
| **Concurrency Model** | Swift 6 Structured Concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) |
| **Deployment Target** | iOS 17.0 |
| **Swift Version** | 6.0 |
| **CloudKit** | Configured in entitlements + ModelConfiguration (private database) |
| **HealthKit** | Entitlement declared, not yet imported/used |

---

## 2. Entry Point

```
@main CycleBalanceApp               (CycleBalance/App/CycleBalanceApp.swift)
  │
  ├─ ModelContainer(schema: 9 models, cloudKitDatabase: .private)
  │
  └─ ContentView                    (CycleBalance/App/ContentView.swift)
       └─ TabView (5 tabs, bound to AppState.selectedTab)
```

---

## 3. Module Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────┐
│  APP LAYER                                                          │
│                                                                     │
│  CycleBalanceApp ──→ ModelContainer(9 models) ──→ ContentView       │
│                                                    │                │
│  AppState (@Observable)  ◄── @Environment ──── SettingsView         │
│  ├ selectedTab: AppTab                                              │
│  └ isPremium: Bool                                                  │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  FEATURE LAYER (Tab-based)                                          │
│                                                                     │
│  Tab 1: TODAY ─────────────────────────────────────────────────     │
│  ┌─────────────────┐     ┌──────────────────┐                      │
│  │   TodayView     │────▶│ CycleViewModel   │                      │
│  │   @Query Symptom │     │ @Observable      │                      │
│  │   QuickAction×2  │     │ @MainActor       │                      │
│  │   SymptomChip    │     │                  │                      │
│  │   FlowLayout     │     │ ► loadData()     │                      │
│  └────────┬─────────┘     │ ► logPeriodDay() │                      │
│           │sheet          │ ► predictions    │                      │
│           ▼               └────────┬─────────┘                      │
│  CycleLogView                      │                                │
│  SymptomLogView                    ▼                                │
│                          CyclePredictionEngine (Sendable struct)     │
│                          ├ Prediction                               │
│                          └ CycleStatistics                          │
│                                                                     │
│  Tab 2: CALENDAR ──────────────────────────────────────────────     │
│  ┌──────────────────┐     ┌──────────────────┐                      │
│  │CalendarMonthView │────▶│ CycleViewModel   │                      │
│  │ CalendarDayCell   │     │ (new instance)   │                      │
│  └──────────────────┘     └──────────────────┘                      │
│                                                                     │
│  Tab 3: TRACK ─────────────────────────────────────────────────     │
│  ┌──────────────────┐                                               │
│  │ TrackingHubView  │──▶ CycleLogView ──▶ CycleViewModel           │
│  │                  │──▶ SymptomLogView ──▶ SymptomViewModel        │
│  └──────────────────┘                                               │
│                                                                     │
│  Tab 4: INSIGHTS ──────────────────────────────────────────────     │
│  ┌──────────────────┐                                               │
│  │  InsightsView    │  @Query Insight (no ViewModel)                │
│  │  InsightCard     │                                               │
│  └──────────────────┘                                               │
│                                                                     │
│  Tab 5: SETTINGS ──────────────────────────────────────────────     │
│  ┌──────────────────┐                                               │
│  │  SettingsView    │  @Environment(AppState.self)                  │
│  └──────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  SHARED UI LAYER                                                    │
│                                                                     │
│  AppTheme            ── Design tokens (colors, severity, flow)      │
│  FlowIntensityPicker ── Horizontal 5-option flow selector           │
│  SeverityPicker      ── 5-dot compact picker + text label           │
│  SeveritySlider      ── Larger picker with per-dot labels           │
│  SavedFeedbackOverlay── Checkmark toast after save                  │
└─────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│  DATA LAYER (SwiftData @Model)                                      │
│                                                                     │
│  ┌────────────┐     ┌──────────────┐     ┌───────────────┐         │
│  │   Cycle    │◄───▶│  CycleEntry  │◄───▶│ SymptomEntry  │         │
│  │            │ 1:N │              │ 1:N │               │         │
│  │ startDate  │     │ date         │     │ date          │         │
│  │ endDate?   │     │ flowIntensity│     │ symptomType   │         │
│  │ lengthDays?│     │ isPeriodDay  │     │ severity      │         │
│  │ isPredicted│     │ cyclePhase?  │     │ notes?        │         │
│  └────────────┘     │ notes?       │     └───────────────┘         │
│                     └──────────────┘                                │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐  ┌────────────────┐        │
│  │BloodSugarReading │  │SupplementLog │  │   MealEntry    │        │
│  │ glucoseValue     │  │ supplementName│  │ mealType       │        │
│  │ readingType      │  │ dosageMg?    │  │ glycemicImpact │        │
│  │ fromHealthKit    │  │ taken: Bool  │  │ photoData? 📦  │        │
│  └──────────────────┘  └──────────────┘  └────────────────┘        │
│                                                                     │
│  ┌──────────────────┐  ┌──────────────┐                             │
│  │ HairPhotoEntry   │  │  DailyLog    │   📦 = @externalStorage    │
│  │ photoType        │  │ weight?      │                             │
│  │ photoData 📦     │  │ sleepHours?  │  ┌──────────────┐          │
│  │ analysisResult?  │  │ stressLevel? │  │   Insight    │          │
│  └──────────────────┘  │ energyLevel? │  │ insightType  │          │
│                        └──────────────┘  │ confidence   │          │
│                                          │ actionable   │          │
│                                          └──────────────┘          │
│                                                                     │
│  ENUMS (10 types, all Codable + CaseIterable + Identifiable):       │
│  FlowIntensity · CyclePhase · SymptomCategory · SymptomType         │
│  GlucoseReadingType · MealType · GlycemicImpact                    │
│  HairPhotoType · InsightType · AppTab                               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. View ↔ ViewModel ↔ Model Dependency Matrix

| View | ViewModel | Models Touched | Data Access |
|---|---|---|---|
| TodayView | CycleViewModel (created in onAppear) | Cycle, CycleEntry | `@Query` for SymptomEntry |
| CalendarMonthView | CycleViewModel (created in onAppear) | Cycle, CycleEntry | ViewModel fetch |
| CycleLogView | CycleViewModel (created in onAppear) | CycleEntry, Cycle | ViewModel insert+save |
| CycleDetailView | CycleViewModel (created in onAppear) | Cycle, CycleEntry | ViewModel compute |
| SymptomLogView | SymptomViewModel (created in onAppear) | SymptomEntry | ViewModel insert+save |
| InsightsView | — (no ViewModel) | Insight | `@Query` directly |
| SettingsView | — (no ViewModel) | — | `@Environment(AppState.self)` |
| ContentView | — | — | `@State AppState` |

---

## 5. File Inventory (28 files)

### App Layer (4)
| File | Type | Responsibility |
|---|---|---|
| `App/CycleBalanceApp.swift` | `@main App` | Entry point, ModelContainer setup |
| `App/AppState.swift` | `@Observable` | Tab selection, premium state |
| `App/ContentView.swift` | `View` | Tab navigation + TrackingHubView |
| `App/SettingsView.swift` | `View` | Settings, delete confirmation |

### Core/Data (10)
| File | Type | Responsibility |
|---|---|---|
| `Core/Data/SwiftData/Enums.swift` | Enums | 10 enum types (72 cases total) |
| `Core/Data/SwiftData/Cycle.swift` | `@Model` | Cycle period tracking |
| `Core/Data/SwiftData/CycleEntry.swift` | `@Model` | Individual period day entry |
| `Core/Data/SwiftData/SymptomEntry.swift` | `@Model` | Individual symptom record |
| `Core/Data/SwiftData/BloodSugarReading.swift` | `@Model` | Glucose readings |
| `Core/Data/SwiftData/SupplementLog.swift` | `@Model` | Supplement tracking |
| `Core/Data/SwiftData/MealEntry.swift` | `@Model` | Meal logging with photos |
| `Core/Data/SwiftData/HairPhotoEntry.swift` | `@Model` | Hair progress photos |
| `Core/Data/SwiftData/DailyLog.swift` | `@Model` | Daily wellness metrics |
| `Core/Data/SwiftData/Insight.swift` | `@Model` | Generated health insights |

### Features/Cycle (5)
| File | Type | Responsibility |
|---|---|---|
| `Features/Cycle/ViewModels/CycleViewModel.swift` | `@Observable` | Cycle data + prediction logic |
| `Features/Cycle/Models/CyclePredictionEngine.swift` | `Sendable struct` | Weighted-average prediction |
| `Features/Cycle/Views/TodayView.swift` | `View` | Dashboard + quick actions |
| `Features/Cycle/Views/CalendarMonthView.swift` | `View` | Month grid display |
| `Features/Cycle/Views/CycleLogView.swift` | `View` | Period logging form |
| `Features/Cycle/Views/CycleDetailView.swift` | `View` | Cycle statistics |

### Features/Symptoms (3)
| File | Type | Responsibility |
|---|---|---|
| `Features/Symptoms/ViewModels/SymptomViewModel.swift` | `@Observable` | Symptom selection + save |
| `Features/Symptoms/Views/SymptomLogView.swift` | `View` | Symptom grid + categories |
| `Features/Symptoms/Views/SymptomGridItem.swift` | `View` | Individual symptom tile |

### Features/Insights (1)
| File | Type | Responsibility |
|---|---|---|
| `Features/Insights/Views/InsightsView.swift` | `View` | Insights list + cards |

### SharedUI (4)
| File | Type | Responsibility |
|---|---|---|
| `SharedUI/Styles/AppTheme.swift` | `enum` | Design tokens + colors |
| `SharedUI/Components/FlowIntensityPicker.swift` | `View` | Flow intensity selector |
| `SharedUI/Components/SeverityPicker.swift` | `View` | Severity dot picker + slider |
| `SharedUI/Components/SavedFeedbackOverlay.swift` | `View` | Save confirmation toast |

---

## 6. Key Observations

1. **No external dependencies** — Pure Apple stack (SwiftUI + SwiftData + planned HealthKit/CloudKit).
2. **9 models defined, 3 actively used** — CycleEntry/Cycle/SymptomEntry have full UI. BloodSugarReading, SupplementLog, MealEntry, HairPhotoEntry, DailyLog, and Insight are modeled but lack dedicated ViewModels/Views.
3. **ViewModel creation pattern** — Each view creates a fresh ViewModel in `.onAppear`, not shared across tabs. This means navigating away and back creates a new instance each time.
4. **Prediction engine is pure** — `CyclePredictionEngine` is a `Sendable` struct with no side effects; safe to call from any context.
5. **CloudKit configured but untested** — The `ModelConfiguration` sets `cloudKitDatabase: .private(...)` but there is no sync status UI or conflict resolution logic.
6. **HealthKit declared but unused** — Entitlement and Info.plist keys exist but no `import HealthKit` or `HKHealthStore` usage anywhere.
