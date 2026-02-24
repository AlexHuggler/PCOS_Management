# CycleBalance

A privacy-first iOS app for women managing Polycystic Ovary Syndrome (PCOS). Track irregular cycles without shame, monitor insulin resistance, log symptoms, and discover what actually helps with AI-powered insights.

## Requirements

- macOS with Xcode 16+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Setup

```bash
# Install XcodeGen
brew install xcodegen

# Clone and generate project
git clone <repo-url>
cd PCOS_Management
xcodegen generate
open CycleBalance.xcodeproj
```

Build and run with Cmd+R targeting an iOS 17+ simulator.

## Architecture

- **Language:** Swift 6 with strict concurrency
- **UI:** SwiftUI (iOS 17+)
- **Data:** SwiftData for local storage
- **Sync:** CloudKit private database
- **ML:** Core ML for on-device pattern recognition
- **Health:** HealthKit integration

## Project Structure

```
CycleBalance/
├── App/                  # App entry point, navigation, settings
├── Features/
│   ├── Cycle/            # Irregular cycle tracking & prediction
│   ├── Symptoms/         # PCOS symptom logging
│   ├── BloodSugar/       # Glucose & insulin resistance tracking
│   ├── Supplements/      # Supplement efficacy monitoring
│   ├── Meals/            # Meal logging with GI analysis
│   ├── PhotoJournal/     # Hair growth/loss photo tracking
│   ├── Insights/         # AI-powered correlations
│   └── Reports/          # Doctor-exportable PDF reports
├── Core/
│   ├── Data/             # SwiftData models, CloudKit sync
│   ├── HealthKit/        # Health data integration
│   ├── ML/               # Core ML models & inference
│   ├── Notifications/    # Local notification scheduling
│   └── Extensions/       # Swift extensions
├── SharedUI/             # Reusable components, themes, charts
└── Resources/            # Assets, ML models, localization
```

## Medical Disclaimer

CycleBalance is designed to help you track and understand your PCOS symptoms. It is not a medical device and does not provide medical advice, diagnosis, or treatment. Always consult with a qualified healthcare provider about your health concerns.
