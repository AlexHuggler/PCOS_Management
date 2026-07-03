# Premium Today Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Today-screen hero ring as the "Silk Comet" (single fading-tail gradient arc with a luminous tip), add subtle/alive motion variants behind a flag, and apply quiet premium polish (cards, streak pill, header emblem, remove redundant prediction card) across all 9 themes.

**Architecture:** A pure, unit-testable `SilkCometRingModel` computes the arc geometry and gradient recipe; `LunarCycleHeroRing` (TodayView.swift) renders it using per-theme colors from a refactored `CycleHeroRingPalette` (AppTheme.swift). Motion is selected by a `RingMotionStyle` flag persisted in UserDefaults, overridable by launch argument, forced off by Reduce Motion.

**Tech Stack:** SwiftUI (iOS 17), Swift 6 strict concurrency, Swift Testing (`@Suite`/`@Test`/`#expect`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-02-premium-today-screen-design.md`

**Ground rules for every task:**
- Repo root: `/Users/alexhuggler/Desktop/AI Work/PCOS/PCOS_Management` (quote the path — it contains spaces). The ROOT `PCOS.xcodeproj` is the real project; run `xcodegen generate` after ANY file add/delete.
- Build: `xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build`
- Unit tests: same command with `test -only-testing:PCOSTests` (append `/SuiteName` for one suite).
- NEVER rename existing accessibility identifiers (`today.hero.container`, `today.lunar.header`, `today.lunar.snapshot`, `today.lunar.insight`, etc.). No SwiftData changes.
- Commit after each task with the shown message; commit ONLY the files listed in that task (the working tree has unrelated pre-existing changes — never `git add -A`).

---

### Task 1: RingMotionStyle flag (TDD)

**Files:**
- Create: `PCOS/PCOS/SharedUI/Styles/RingMotionStyle.swift`
- Modify: `PCOS/PCOS/App/CycleBalanceApp.swift` (inside `applyAppearanceLaunchOverridesIfNeeded`, after the font-option block, ~line 476)
- Test: `PCOS/PCOSTests/RingMotionStyleTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PCOS/PCOSTests/RingMotionStyleTests.swift`:

```swift
import Testing
import Foundation
@testable import PCOS

@Suite("Ring Motion Style")
struct RingMotionStyleTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "RingMotionStyleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Defaults to subtle when nothing is stored")
    func defaultsToSubtle() {
        #expect(RingMotionStyle.stored(defaults: makeDefaults()) == .subtle)
    }

    @Test("Round-trips through UserDefaults")
    func roundTrips() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.alive, defaults: defaults)
        #expect(RingMotionStyle.stored(defaults: defaults) == .alive)
        #expect(defaults.string(forKey: RingMotionStyle.defaultsKey) == "alive")
    }

    @Test("Invalid stored raw value falls back to subtle")
    func invalidRawFallsBack() {
        let defaults = makeDefaults()
        defaults.set("disco", forKey: RingMotionStyle.defaultsKey)
        #expect(RingMotionStyle.stored(defaults: defaults) == .subtle)
    }

    @Test("Reduce Motion forces off regardless of stored value")
    func reduceMotionWins() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.alive, defaults: defaults)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: true) == .off)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: false) == .alive)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run (from repo root):
```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests/RingMotionStyleTests 2>&1 | grep -E "error:|Test run"
```
Expected: compile error "Cannot find 'RingMotionStyle' in scope" (the type does not exist yet). Note: `xcodegen generate` first so the new test file is in the project.

- [ ] **Step 3: Write the implementation**

Create `PCOS/PCOS/SharedUI/Styles/RingMotionStyle.swift`:

```swift
import Foundation

/// Motion treatment for the Silk Comet hero ring. `subtle` is the shipped
/// default; `alive` is kept for on-device comparison and is only reachable
/// via the DEBUG settings toggle or the launch argument.
enum RingMotionStyle: String, CaseIterable {
    case subtle
    case alive
    case off

    static let defaultsKey = "appearance.ringMotionStyle"

    static func stored(defaults: UserDefaults = .standard) -> RingMotionStyle {
        guard let raw = defaults.string(forKey: defaultsKey),
              let style = RingMotionStyle(rawValue: raw) else {
            return .subtle
        }
        return style
    }

    static func store(_ style: RingMotionStyle, defaults: UserDefaults = .standard) {
        defaults.set(style.rawValue, forKey: defaultsKey)
    }

    /// Effective style after accessibility: Reduce Motion always wins.
    static func resolved(defaults: UserDefaults = .standard, reduceMotion: Bool) -> RingMotionStyle {
        reduceMotion ? .off : stored(defaults: defaults)
    }
}
```

In `PCOS/PCOS/App/CycleBalanceApp.swift`, inside `applyAppearanceLaunchOverridesIfNeeded(arguments:appearancePreferences:)`, add after the font-option `if` block:

```swift
        if let rawMotionStyle = launchArgumentValue(for: RingMotionStyle.defaultsKey, in: arguments),
           let motionStyle = RingMotionStyle(rawValue: rawMotionStyle) {
            RingMotionStyle.store(motionStyle)
        }
```

- [ ] **Step 4: Regenerate project, run tests to verify they pass**

```bash
xcodegen generate
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests/RingMotionStyleTests 2>&1 | grep -E "Test run|TEST"
```
Expected: `Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add PCOS/PCOS/SharedUI/Styles/RingMotionStyle.swift PCOS/PCOSTests/RingMotionStyleTests.swift PCOS/PCOS/App/CycleBalanceApp.swift
git commit -m "feat: ring motion style flag with launch-arg override"
```

---

### Task 2: SilkCometRingModel — pure ring geometry/recipe (TDD)

**Files:**
- Create: `PCOS/PCOS/Features/Cycle/Models/SilkCometRingModel.swift`
- Test: `PCOS/PCOSTests/SilkCometRingModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PCOS/PCOSTests/SilkCometRingModelTests.swift`:

```swift
import Testing
import Foundation
@testable import PCOS

@Suite("Silk Comet Ring Model")
struct SilkCometRingModelTests {
    @Test("Arc end tracks progress within clamp bounds")
    func arcEndTracksProgress() {
        #expect(SilkCometRingModel(progress: 0.5).arcEnd == 0.5)
        // Overdue cycles never close the ring on themselves (spec: clamp 0.98).
        #expect(SilkCometRingModel(progress: 1.4).arcEnd == SilkCometRingModel.maximumArcEnd)
        // Day 1 still shows a sliver so the tip has somewhere to sit.
        #expect(SilkCometRingModel(progress: 0.0).arcEnd == SilkCometRingModel.minimumArcEnd)
    }

    @Test("Gradient stops scale with the arc so the tail is always at day 1")
    func stopsScaleWithArc() {
        let model = SilkCometRingModel(progress: 0.5)
        #expect(model.stops.count == 5)
        #expect(model.stops.first?.position == 0)
        #expect(model.stops.last?.position == 0.5)
        // Positions ascend strictly.
        let positions = model.stops.map(\.position)
        #expect(positions == positions.sorted())
    }

    @Test("Zero fade: tail opacity is exactly zero, tip is full")
    func zeroFadeRecipe() {
        let model = SilkCometRingModel(progress: 0.6)
        #expect(model.stops.first?.opacity == 0)
        #expect(model.stops.last?.opacity == 1)
    }

    @Test("Tail floor lifts every stop below the floor (High Contrast)")
    func tailFloor() {
        let model = SilkCometRingModel(progress: 0.6, tailFloorOpacity: 0.35)
        #expect(model.stops.allSatisfy { $0.opacity >= 0.35 })
        #expect(model.stops.last?.opacity == 1)
    }

    @Test("Welcome state shows the decorative segment without a tip")
    func welcomeState() {
        let model = SilkCometRingModel(progress: 0, isWelcome: true)
        #expect(model.arcEnd == SilkCometRingModel.welcomeArcEnd)
        #expect(model.showsTip == false)
        #expect(SilkCometRingModel(progress: 0.4).showsTip == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodegen generate
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests/SilkCometRingModelTests 2>&1 | grep -E "error:|Test run"
```
Expected: compile error "Cannot find 'SilkCometRingModel' in scope".

- [ ] **Step 3: Write the implementation**

Create `PCOS/PCOS/Features/Cycle/Models/SilkCometRingModel.swift`:

```swift
import Foundation

/// Pure geometry and gradient recipe for the Silk Comet hero ring: a single
/// arc whose gradient fades in from nothing at the tail (cycle day 1) and
/// gathers full color at the leading tip (today). Positions are fractions of
/// the full circle; colors are indices into the theme's silk palette.
struct SilkCometRingModel: Equatable {
    struct Stop: Equatable {
        let position: Double
        let opacity: Double
        let colorIndex: Int
    }

    let arcEnd: Double
    let stops: [Stop]
    let showsTip: Bool

    static let minimumArcEnd = 0.02
    static let maximumArcEnd = 0.98
    static let welcomeArcEnd = 0.25

    /// The silk recipe, relative to arc length (fraction, opacity, colorIndex).
    private static let relativeStops: [(Double, Double, Int)] = [
        (0.00, 0.00, 0),
        (0.17, 0.14, 0),
        (0.36, 0.45, 1),
        (0.62, 0.85, 2),
        (1.00, 1.00, 3),
    ]

    init(progress: Double, isWelcome: Bool = false, tailFloorOpacity: Double = 0) {
        let end = isWelcome
            ? Self.welcomeArcEnd
            : min(max(progress, Self.minimumArcEnd), Self.maximumArcEnd)

        arcEnd = end
        showsTip = !isWelcome
        stops = Self.relativeStops.map { fraction, opacity, colorIndex in
            Stop(
                position: fraction * end,
                opacity: max(opacity, tailFloorOpacity),
                colorIndex: colorIndex
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 5: Commit**

```bash
git add PCOS/PCOS/Features/Cycle/Models/SilkCometRingModel.swift PCOS/PCOSTests/SilkCometRingModelTests.swift
git commit -m "feat: silk comet ring model with progress-scaled gradient stops"
```

---

### Task 3: CycleHeroRingPalette refactor + Silk Comet ring view

These change together: the palette refactor breaks the old ring's compile, and the new ring is its only consumer.

**Files:**
- Modify: `PCOS/PCOS/SharedUI/Styles/AppTheme.swift` — `CycleHeroRingPalette` struct (lines 4–14) and `cycleHeroRingPalette` (lines ~141–269)
- Modify: `PCOS/PCOS/Features/Cycle/Views/TodayView.swift` — `LunarCycleHeroRing` (lines ~1863–1974) and its call site (~line 370)

- [ ] **Step 1: Replace the palette struct in AppTheme.swift**

Replace the `CycleHeroRingPalette` struct (top of file, lines 4–14) with:

```swift
struct CycleHeroRingPalette {
    let trackGradient: AngularGradient
    /// Four silk colors, tail → tip.
    let silkColors: [Color]
    let tipCoreColor: Color
    let tipGlowColor: Color
    let innerShadowColor: Color
    let usesGlowBlend: Bool
    /// 0 for the standard zero-fade tail; lifted for High Contrast legibility.
    let tailFloorOpacity: Double
    /// High Contrast uses a solid marker dot instead of a bloom.
    let showsTipBloom: Bool
}
```

- [ ] **Step 2: Rewrite the three `cycleHeroRingPalette` branches in AppTheme.swift**

Replace the whole `static var cycleHeroRingPalette: CycleHeroRingPalette { ... }` (lines ~141–269) with:

```swift
    static var cycleHeroRingPalette: CycleHeroRingPalette {
        if isLunarCalm {
            return CycleHeroRingPalette(
                trackGradient: lunarCalmCycleTrackGradient,
                silkColors: [
                    lunarCalmTealRGB.color,
                    lunarCalmLavenderRGB.color,
                    lunarCalmCoralRGB.color,
                    lunarCalmPeachRGB.color,
                ],
                tipCoreColor: ThemeRGB(hex: 0xFFF6E8).color,
                tipGlowColor: lunarCalmPeachRGB.color,
                innerShadowColor: lunarCalmBackgroundRGB.color.opacity(0.46),
                usesGlowBlend: true,
                tailFloorOpacity: 0,
                showsTipBloom: true
            )
        }

        if appearance.themeOption.isHighContrast {
            return CycleHeroRingPalette(
                trackGradient: AngularGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.55),
                    ],
                    center: .center,
                    startAngle: .degrees(180),
                    endAngle: .degrees(540)
                ),
                silkColors: [
                    palette.accent.color,
                    palette.accent.color,
                    palette.accent.color,
                    palette.accent.color,
                ],
                tipCoreColor: palette.coral.color,
                tipGlowColor: palette.coral.color,
                innerShadowColor: Color.black.opacity(0.24),
                usesGlowBlend: false,
                tailFloorOpacity: 0.35,
                showsTipBloom: false
            )
        }

        return CycleHeroRingPalette(
            trackGradient: AngularGradient(
                colors: [
                    cardBorder.opacity(0.5),
                    premiumEditorSurface.opacity(0.28),
                    cardBorder.opacity(0.34),
                    premiumEditorRaisedSurface.opacity(0.42),
                    cardBorder.opacity(0.5),
                ],
                center: .center,
                startAngle: .degrees(180),
                endAngle: .degrees(540)
            ),
            silkColors: [
                palette.sage.color,
                premiumEditorAccentColor,
                premiumEditorSecondaryAccentColor,
                softGoldAccent,
            ],
            tipCoreColor: Color.white,
            tipGlowColor: premiumEditorSecondaryAccentColor,
            innerShadowColor: cardBorder.opacity(0.28),
            usesGlowBlend: true,
            tailFloorOpacity: 0,
            showsTipBloom: true
        )
    }
```

Then grep for now-orphaned members: `grep -n "lunarCalmCycleGradient\|lunarCalmCycleGlowGradient" PCOS/PCOS -r`. If `lunarCalmCycleGlowGradient` and `lunarCalmCycleGradient` have no remaining references, delete their definitions in AppTheme.swift (~lines 99–139). Keep `lunarCalmCycleTrackGradient` (used above).

- [ ] **Step 3: Rewrite `LunarCycleHeroRing` in TodayView.swift**

Replace the entire `private struct LunarCycleHeroRing: View { ... }` (lines ~1863–1974) with:

```swift
private struct LunarCycleHeroRing: View {
    let progress: Double
    var isWelcome: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepDone = false
    @State private var bloomBreathing = false
    @State private var aliveShimmer = false

    /// Arc starts at 12 o'clock. Circle paths start at 3 o'clock, so offset -90°.
    private let rotationDegrees = -90.0

    private var motionStyle: RingMotionStyle {
        RingMotionStyle.resolved(reduceMotion: reduceMotion)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringPalette = AppTheme.cycleHeroRingPalette
            let model = SilkCometRingModel(
                progress: progress,
                isWelcome: isWelcome,
                tailFloorOpacity: ringPalette.tailFloorOpacity
            )
            let lineWidth = max(size * 0.05, 13)
            let trackWidth = max(size * 0.012, 2.5)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = (size - lineWidth) / 2
            let visibleEnd = sweepDone ? model.arcEnd : 0.001
            let tipPoint = point(on: center, radius: radius, trim: model.arcEnd)

            ZStack {
                Circle()
                    .stroke(ringPalette.trackGradient, style: StrokeStyle(lineWidth: trackWidth))
                    .padding((lineWidth - trackWidth) / 2)
                    .opacity(0.8)

                Circle()
                    .trim(from: 0, to: visibleEnd)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: gradientStops(model: model, ringPalette: ringPalette)),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotationDegrees + (aliveShimmer ? 4 : 0)))
                    .shadow(color: ringPalette.tipGlowColor.opacity(0.18), radius: 13, y: 3)

                if model.showsTip {
                    tip(ringPalette: ringPalette, size: size)
                        .position(tipPoint)
                        .opacity(sweepDone ? 1 : 0)
                }
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .onAppear { startMotion() }
    }

    private func gradientStops(model: SilkCometRingModel, ringPalette: CycleHeroRingPalette) -> [Gradient.Stop] {
        model.stops.map { stop in
            Gradient.Stop(
                color: ringPalette.silkColors[min(stop.colorIndex, ringPalette.silkColors.count - 1)]
                    .opacity(stop.opacity),
                location: stop.position
            )
        }
    }

    @ViewBuilder
    private func tip(ringPalette: CycleHeroRingPalette, size: CGFloat) -> some View {
        let coreDiameter = max(size * 0.034, 9)
        let bloomDiameter = max(size * 0.16, 40)

        ZStack {
            if ringPalette.showsTipBloom {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ringPalette.tipGlowColor.opacity(0.55),
                                ringPalette.tipGlowColor.opacity(0.16),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: bloomDiameter / 2
                        )
                    )
                    .frame(width: bloomDiameter, height: bloomDiameter)
                    .scaleEffect(bloomBreathing ? 1.12 : 1)
                    .modifier(GlowBlendModifier(enabled: ringPalette.usesGlowBlend))
            }

            Circle()
                .fill(ringPalette.tipCoreColor)
                .frame(width: coreDiameter, height: coreDiameter)
                .shadow(color: ringPalette.tipGlowColor.opacity(0.7), radius: 5)
        }
    }

    private func startMotion() {
        switch motionStyle {
        case .off:
            sweepDone = true
        case .subtle:
            sweepDone = false
            withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
            withAnimation(.easeInOut(duration: 0.75).repeatCount(4, autoreverses: true).delay(1.1)) {
                bloomBreathing = true
            }
            // Settle back to rest after the two breaths.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4.2))
                withAnimation(.easeOut(duration: 0.4)) { bloomBreathing = false }
            }
        case .alive:
            sweepDone = false
            withAnimation(.easeOut(duration: 1.1)) { sweepDone = true }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true).delay(1.1)) {
                bloomBreathing = true
            }
            withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                aliveShimmer = true
            }
        }
    }

    private func point(on center: CGPoint, radius: CGFloat, trim: Double) -> CGPoint {
        let angle = (trim * 360 + rotationDegrees) * .pi / 180
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct GlowBlendModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.blendMode(.plusLighter)
        } else {
            content
        }
    }
}
```

- [ ] **Step 4: Update the call site for the welcome state**

At TodayView.swift ~line 370, change:

```swift
                    LunarCycleHeroRing(progress: cycleHeroRingProgress)
```
to:
```swift
                    LunarCycleHeroRing(
                        progress: cycleHeroRingProgress,
                        isWelcome: !heroState.isCurrentCycle
                    )
```

`TodayHeroState` (top of TodayView.swift) needs the helper — add inside the `TodayHeroState` enum, next to `renderIdentity`:

```swift
        var isCurrentCycle: Bool {
            if case .currentCycle = self { return true }
            return false
        }
```

Also simplify `cycleHeroRingProgress` (~line 388): the `0.12` welcome fallback is now handled by the model, so change `return 0.12` to `return 0`.

- [ ] **Step 5: Build and run unit tests**

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests 2>&1 | grep -E "Test run|TEST"
```
Expected: BUILD SUCCEEDED; all tests pass.

- [ ] **Step 6: Visual smoke check (lunar + one light + high contrast + welcome)**

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/PCOS.app
for t in lunarCalm sage highContrast; do
  xcrun simctl terminate booted alex.PCOS 2>/dev/null
  xcrun simctl launch booted alex.PCOS UITestMode -uiTest.demoScenario symptomManagement -appearance.themeOption $t -appearance.ringMotionStyle off
  sleep 4; xcrun simctl io booted screenshot /tmp/silk-$t.png
done
# Welcome state (no cycle data):
xcrun simctl terminate booted alex.PCOS 2>/dev/null
xcrun simctl launch booted alex.PCOS UITestMode -onboarding.hasCompletedOnboarding YES -appearance.themeOption lunarCalm -appearance.ringMotionStyle off
sleep 4; xcrun simctl io booted screenshot /tmp/silk-welcome.png
```
Read each PNG. Checklist: single continuous arc fading in from nothing; bright tip with bloom at "today"; hairline full-circle track; HC shows solid dot marker and ≥35%-opacity tail; welcome shows 25% decorative segment with no tip.

- [ ] **Step 7: Commit**

```bash
git add PCOS/PCOS/SharedUI/Styles/AppTheme.swift PCOS/PCOS/Features/Cycle/Views/TodayView.swift
git commit -m "feat: silk comet hero ring with subtle/alive motion variants"
```

---

### Task 4: DEBUG settings toggle for ring motion

**Files:**
- Modify: `PCOS/PCOS/App/SettingsView.swift` (DEBUG-only tools section — find it with `grep -n "#if DEBUG" PCOS/PCOS/App/SettingsView.swift`; add inside the existing debug Section alongside the demo-data rows, ~lines 600–700)

- [ ] **Step 1: Add the picker row**

Inside the existing DEBUG tools `Section`, add:

```swift
                Picker(
                    "Ring Motion (debug)",
                    selection: Binding(
                        get: { RingMotionStyle.stored() },
                        set: { RingMotionStyle.store($0) }
                    )
                ) {
                    ForEach(RingMotionStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                .accessibilityIdentifier("settings.debug.ring_motion")
```

(Debug-only UI: plain strings are fine — no L10n needed, matching the surrounding debug rows.)

- [ ] **Step 2: Build**

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PCOS/PCOS/App/SettingsView.swift
git commit -m "feat: debug settings toggle for ring motion style"
```

---

### Task 5: Noise reduction — remove immersive prediction card, quiet streak pill

**Files:**
- Modify: `PCOS/PCOS/Features/Cycle/Views/TodayView.swift` — `predictionSection` (~line 1612) and `streakBadge` (~line 777)

- [ ] **Step 1: Gate the plain prediction card out of the immersive layout**

In `predictionSection`, the postpartum "Cycle Recovery" branch MUST stay (it is not duplicated in the ring). Change only the last branch's condition from:

```swift
            } else if let predictionText = viewModel?.predictionPrimaryText {
```
to:
```swift
            } else if !AppTheme.usesImmersiveHomeShell, let predictionText = viewModel?.predictionPrimaryText {
```

- [ ] **Step 2: Restyle the streak badge as a quiet capsule pill**

Replace the body of `private var streakBadge: some View` (keep the `if streakDays > 1` guard and the exact `L10n.inflected` text — only the chrome changes):

```swift
    @ViewBuilder
    private var streakBadge: some View {
        if streakDays > 1 {
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "flame.fill")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(AppTheme.softGoldAccent)
                Text(
                    L10n.inflected(
                        LocalizedStringResource(
                            "^[\(streakDays) day](inflect: true) logging streak",
                            comment: "Badge showing the user's current logging streak in days."
                        )
                    )
                )
                    .appFont(.caption, weight: .medium)
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, AppTheme.spacing12)
            .padding(.vertical, AppTheme.spacing8)
            .background(Capsule().fill(AppTheme.premiumEditorRaisedSurface.opacity(0.6)))
            .overlay(Capsule().stroke(AppTheme.premiumEditorBorder.opacity(0.5), lineWidth: 0.8))
            .frame(maxWidth: .infinity)
        }
    }
```

- [ ] **Step 3: Build + targeted UI test**

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSUITests/PCOSUITests/testTodayHeroResolvesToSingleCurrentCycleCardWithoutOverlap 2>&1 | grep -E "Test Case|TEST"
```
Expected: BUILD SUCCEEDED; test passes. If any UI test greps for "Period Estimate" on Today, check with `grep -rn "Period Estimate\|prediction" PCOS/PCOSUITests/` first and report before changing test expectations.

- [ ] **Step 4: Commit**

```bash
git add PCOS/PCOS/Features/Cycle/Views/TodayView.swift
git commit -m "feat: quiet streak pill and remove redundant prediction card in immersive layout"
```

---

### Task 6: Quiet premium card chrome + duotone badges + header emblem

**Files:**
- Modify: `PCOS/PCOS/SharedUI/Styles/AppTheme.swift` (add `PremiumCardDecoration` near the existing `CardStyle` modifier, ~line 787)
- Modify: `PCOS/PCOS/Features/Cycle/Views/TodayView.swift` (`lunarTodaySnapshotCard` ~line 640, `LunarTodaySnapshotItemView` ~line 1833, `lunarTodayHeader` emblem ~line 417)
- Modify: `PCOS/PCOS/Core/Views/AhaMomentCard.swift` (`ImmersiveInsightCard` chrome)

- [ ] **Step 1: Add the shared card decoration to AppTheme.swift**

Add after the `CardStyle` ViewModifier:

```swift
/// Quiet premium chrome for immersive Today cards: raised surface, hairline
/// border, and a two-layer shadow (tight contact + wide ambient).
struct PremiumCardDecoration: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.largeCardCornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.premiumEditorBorder.opacity(0.62), lineWidth: 0.8)
            )
            .shadow(color: AppTheme.cardShadowColor.opacity(0.5), radius: 2, y: 1)
            .shadow(color: AppTheme.cardShadowColor.opacity(0.35), radius: 24, y: 10)
    }
}

extension View {
    func premiumCardDecoration(cornerRadius: CGFloat = AppTheme.largeCardCornerRadius) -> some View {
        modifier(PremiumCardDecoration(cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 2: Apply it to the snapshot card and insight card**

In TodayView.swift `lunarTodaySnapshotCard`: change `.padding(AppTheme.spacing16)` to `.padding(AppTheme.spacing20)` and replace its `.background(RoundedRectangle...)` + `.overlay(RoundedRectangle...)` pair with `.premiumCardDecoration()`.

In AhaMomentCard.swift `ImmersiveInsightCard`: same replacement — `.padding(AppTheme.spacing16)` → `.padding(AppTheme.spacing20)`, and its `.background(...)`/`.overlay(...)` pair → `.premiumCardDecoration()`. (Verify `AppTheme.spacing20` exists — it does, in the spacing tokens.)

- [ ] **Step 3: Duotone snapshot badges**

In `LunarTodaySnapshotItemView`, replace the badge `ZStack` with:

```swift
            ZStack {
                Circle()
                    .fill(item.color.opacity(0.14))
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                Image(systemName: item.systemImage)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(item.color)
            }
            .frame(width: 42, height: 42)
```

- [ ] **Step 4: Header emblem hairline ring**

In `lunarTodayHeader`, replace the emblem `ZStack { ... }.frame(width: 40, height: 40).shadow(...)` chain with:

```swift
            ZStack {
                Circle()
                    .fill(AppTheme.premiumEditorAccentGradient)
                Image(systemName: "moon.stars.fill")
                    .appFont(.headline)
                    .foregroundStyle(AppTheme.premiumEditorCTAForeground)
            }
            .frame(width: 40, height: 40)
            .overlay(
                Circle()
                    .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 1)
                    .padding(-3.5)
                    .opacity(0.7)
            )
            .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.32), radius: 18, y: 6)
            .accessibilityHidden(true)
```

- [ ] **Step 5: Build, run full unit tests**

```bash
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests 2>&1 | grep -E "Test run|TEST"
```
Expected: BUILD SUCCEEDED; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add PCOS/PCOS/SharedUI/Styles/AppTheme.swift PCOS/PCOS/Features/Cycle/Views/TodayView.swift PCOS/PCOS/Core/Views/AhaMomentCard.swift
git commit -m "feat: quiet premium card chrome, duotone badges, header emblem ring"
```

---

### Task 7: Full verification sweep + motion recordings

**Files:** none modified (verification only; screenshots/videos to `/tmp`).

- [ ] **Step 1: Full builds and test suites**

```bash
xcodegen generate
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSTests 2>&1 | grep -E "Test run|TEST"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -configuration Release CODE_SIGNING_ALLOWED=NO -derivedDataPath build-release build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project PCOS.xcodeproj -scheme PCOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build test -only-testing:PCOSUITests/PCOSUITests 2>&1 | grep -E "Test Case.*(passed|failed)|TEST" | tail -30
```
Expected: both builds succeed; 607 unit tests pass (598 + 4 RingMotionStyle + 5 SilkCometRingModel); UI suite passes. IMPORTANT: do not launch the app manually or write simulator defaults while UI tests run (theme contamination breaks theme-agnostic tests).

- [ ] **Step 2: Nine-theme screenshot sweep (motion off for crisp stills)**

```bash
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/PCOS.app
for t in lunarCalm botanicalJournal sage sunrise ocean botanicalMist blushMoonrise fruitGrove highContrast; do
  xcrun simctl terminate booted alex.PCOS 2>/dev/null
  xcrun simctl launch booted alex.PCOS UITestMode -uiTest.demoScenario symptomManagement -appearance.themeOption $t -appearance.ringMotionStyle off
  sleep 4; xcrun simctl io booted screenshot /tmp/premium-$t.png
done
```
Read every PNG. Checklist per theme: silk arc fades from nothing → bright tip; track hairline visible but quiet; cards show unified chrome; streak pill quiet; no "Period Estimate" card at the bottom; emblem ring visible.

- [ ] **Step 3: Record subtle vs alive motion videos**

```bash
for style in subtle alive; do
  xcrun simctl terminate booted alex.PCOS 2>/dev/null
  xcrun simctl launch booted alex.PCOS UITestMode -uiTest.demoScenario symptomManagement -appearance.themeOption lunarCalm -appearance.ringMotionStyle $style
  xcrun simctl io booted recordVideo --codec h264 --force /tmp/ring-$style.mp4 &
  REC=$!; sleep 9; kill -INT $REC; wait $REC
done
```
Convert for the visual companion (mp4 → looping web-friendly): `ffmpeg -i /tmp/ring-$style.mp4 -vf "scale=380:-2,fps=24" -t 8 /tmp/ring-$style.gif` (or copy the mp4s into the companion content dir and reference with `<video>` tags). Present both to the user for the final motion decision.

- [ ] **Step 4: Report**

Summarize results to the user with the screenshot findings and the two videos in the visual companion; the user picks the shipped motion style (subtle stays default unless they choose otherwise).

---

## Self-Review (done at plan-writing time)

- **Spec coverage:** §1 ring → Tasks 2–3; §2 motion → Tasks 1, 3, 4, 7.3; §3 cards → Task 6; §4 noise → Task 5; §5 header → Task 6.4; §6 map → matches; §7 verification → Task 7. Overdue clamp → Task 2 test; HC exception → Tasks 2–3; welcome state → Tasks 2–3; Reduce Motion → Tasks 1, 3.
- **Placeholders:** none — every code step shows the code.
- **Type consistency:** `CycleHeroRingPalette` fields (`silkColors`, `tipCoreColor`, `tipGlowColor`, `tailFloorOpacity`, `showsTipBloom`, `usesGlowBlend`, `trackGradient`, `innerShadowColor`) match between Task 3 Steps 1–3; `SilkCometRingModel(progress:isWelcome:tailFloorOpacity:)` matches Tasks 2–3; `RingMotionStyle.stored/store/resolved` matches Tasks 1, 3, 4.
