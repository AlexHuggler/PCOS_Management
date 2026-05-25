# CycleBalance

A privacy-first iOS app for women managing Polycystic Ovary Syndrome (PCOS). Track irregular cycles, monitor insulin resistance, log symptoms, and generate local-first insights.

## Requirements

- macOS with Xcode 16+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Source of Truth

- `project.yml` is the build definition.
- `PCOS.xcodeproj` is generated from XcodeGen and should not be manually edited.
- Do not use `PCOS/PCOS.xcodeproj` (stale nested project); only use the root `PCOS.xcodeproj`.
- Active source roots: `PCOS/PCOS`, `PCOS/PCOSTests`, and `PCOS/PCOSUITests`.
- Active schemes: `PCOS` for RevenueCat QA and `PCOS Local StoreKit` for local StoreKit QA.
- Backlog source of truth: `ISSUE_LOG.md`.

## Setup

```bash
brew install xcodegen

git clone <repo-url>
cd PCOS_Management
./scripts/open_pcos_xcode.sh
```

Alternative:

```bash
make open-xcode
```

## Build and Test

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug build
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test
```

Run those commands sequentially if you are scripting them; `xcodebuild` will lock the build database if two jobs share the same DerivedData directory.

## Premium QA Runbook

- RevenueCat paywall and demo import QA steps are documented in `RevenueCat_QA_Runbook.md`.
- Use the default `PCOS` scheme when validating premium purchase flows.
- The shared `PCOS` scheme launches with `-billing.backendMode revenuecat` by default and does not use `PCOS.storekit`.
- Use the shared `PCOS Local StoreKit` scheme for local StoreKit validation; it launches with `-billing.backendMode local_storekit` and `PCOS/PCOS/StoreKit/PCOS.storekit`.
- If you see an `[Environment: Xcode]` purchase prompt on the shared `PCOS` scheme, you are not on the supported RevenueCat QA path.

## Device QA Note

- If the UI appears vertically "squished" on a physical iPhone, first verify Reachability is not active.
- Disable Reachability in `Settings > Accessibility > Touch > Reachability` (or swipe up/tap the top area to dismiss it) before treating the layout as an app regression.

## Personal Team Device Run

- Enable iOS Developer Mode on your device before first launch from Xcode.
- Debug builds now default to local-only SwiftData on physical devices.
- To opt into CloudKit in Debug on device (paid-team QA), pass either:
  - Launch argument: `-debug.persistence.cloudkit`
  - Environment variable: `DEBUG_PERSISTENCE_CLOUDKIT=true`
- Submission release builds should remain local-only for health data; keep CloudKit opt-in limited to debug QA and do not ship CloudKit-backed health storage to App Review.

## Project Structure

```
PCOS_Management/
├── project.yml                     # XcodeGen source of truth
├── PCOS/PCOS/                      # Active app source tree
├── PCOS/PCOSTests/                 # Active unit tests
├── PCOS/PCOSUITests/               # Active UI tests
├── scripts/open_pcos_xcode.sh      # One-command Xcode setup/open
├── ISSUE_LOG.md                    # Product backlog / issue tracking
└── project_map.md                  # Architecture map
```

## Medical Disclaimer

CycleBalance is designed to help users track and understand PCOS symptoms. It is not a medical device and does not provide medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider about health concerns.
