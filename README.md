# CycleBalance

A privacy-first iOS app for women managing Polycystic Ovary Syndrome (PCOS). Track irregular cycles, monitor insulin resistance, log symptoms, and generate on-device insights.

## Requirements

- macOS with Xcode 16+
- iOS 17.0+ deployment target
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Source of Truth

- `project.yml` is the build definition.
- `PCOS.xcodeproj` is generated from XcodeGen and should not be manually edited.
- Do not use `PCOS/PCOS.xcodeproj` (stale nested project); only use the root `PCOS.xcodeproj`.
- Active target/scheme: `PCOS`.
- `CycleBalance/` and `PCOS/PCOS/` (plus test trees) are kept in parity. Run `./scripts/check_tree_parity.sh`.
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

## Device QA Note

- If the UI appears vertically "squished" on a physical iPhone, first verify Reachability is not active.
- Disable Reachability in `Settings > Accessibility > Touch > Reachability` (or swipe up/tap the top area to dismiss it) before treating the layout as an app regression.

## Project Structure

```
PCOS_Management/
├── project.yml                     # XcodeGen source of truth
├── PCOS/PCOS/                      # Active app source tree
├── PCOS/PCOSTests/                 # Active unit tests
├── PCOS/PCOSUITests/               # Active UI tests
├── CycleBalance/                   # Canonical mirror tree (parity-checked)
├── CycleBalanceTests/              # Canonical mirror tests (parity-checked)
├── scripts/check_tree_parity.sh    # Drift guard
├── scripts/open_pcos_xcode.sh      # One-command Xcode setup/open
├── ISSUE_LOG.md                    # Product backlog / issue tracking
└── project_map.md                  # Architecture map
```

## Medical Disclaimer

CycleBalance is designed to help users track and understand PCOS symptoms. It is not a medical device and does not provide medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider about health concerns.
