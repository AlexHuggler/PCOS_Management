# Premium Today Screen — Design Spec

**Date:** 2026-07-02
**Scope:** CycleBalance Today (home) screen visual/UX refinement across all 9 themes.
**Decisions made with user:** direction = "Balanced" (quiet refined cards, ring as the one luminous focal point); ring style = **Silk Comet, single tail, zero fade** (chosen over dual-tail + star variant after visual comparison); motion default = **"more alive"** (chosen 2026-07-03 after comparing on-device recordings of both variants; subtle and off remain selectable via the debug toggle / launch argument).

## 1. Silk Comet hero ring

Replaces the current two-arc composition (decorative upper arc + progress lower arc + detached sparkle) with **one continuous element**:

- **Track:** full-circle hairline (~2.5pt) using the existing per-theme track tones, quieter than today (≤10% opacity variation around the circle).
- **Arc:** single progress arc, ~13pt stroke, drawn with `Circle().trim(from: 0, to: progress)` and an `AngularGradient` whose stops are **scaled to the trimmed range** so the visual recipe is progress-relative:
  - Position 0 (tail): theme silk color 1 at **0% opacity** (zero fade — confirmed).
  - ~17%: silk color 1 at ~14% opacity.
  - ~36%: silk color 2 at ~45% opacity.
  - ~62%: silk color 3 at ~85% opacity.
  - 100% (tip): silk color 4 at full opacity.
  - Stops are computed as fractions of `progress` so the tail always starts at cycle day 1 and the brightest point is always "today". Round line caps; the tail cap is invisible because opacity is 0 there.
- **Tip (comet head):** at angle `progress × 360° − 90°`: a bright core (~10pt circle, near-white toward theme peach/gold) over a soft radial bloom (~44pt diameter, theme glow color, blur/soft-light per theme's `usesGlowBlend`). Replaces the current detached sparkle. Guarantees "today" reads clearly even on day 1–3 when the arc itself is nearly invisible.
- **Per-theme colors:** refactor `CycleHeroRingPalette` (AppTheme.swift) to carry `trackGradient`, `silkColors: [Color]` (4 stops), `tipCoreColor`, `tipGlowColor`, `innerShadowColor`, `usesGlowBlend`. Each existing branch (Lunar Calm / High Contrast / generic palette-derived) maps its current colors into the new fields — Lunar keeps teal→lavender→coral→peach; generic themes derive from `palette` tokens as today.
- **High Contrast accessibility exception:** tail starts at ~35% opacity (not zero) and the tip is a solid marker dot without bloom — legibility over drama.
- **Welcome state (no cycle yet):** hairline track plus a static, gentle 25% decorative silk segment; no tip glow.
- **Overdue/long cycles:** progress clamps at 0.98 — the arc never fully closes on itself and the comet head rests just short of the start point, avoiding a seam where the bright tip meets the invisible tail.

## 2. Motion

- **Subtle (default):** on appear, arc sweeps 0 → progress over ~1.1s ease-out (once per appearance); tip bloom breathes gently twice (~3s total) then rests. No looping motion.
- **"More alive" (comparison variant, kept per user request):** continuous slow shimmer — gradient hue/phase drifts ±4° over ~6s and the bloom pulses 0.9→1.0 — implemented alongside subtle, selected by a style flag.
- **Switching:** `UserDefaults` key `appearance.ringMotionStyle` (`subtle` | `alive` | `off`), default `subtle`; settable via launch argument (for demo videos) and a DEBUG-only Settings row. Not exposed to end users until the user picks the winner.
- **Reduce Motion:** forces `off` — arc renders at final progress with no sweep, bloom static.

## 3. Card system polish (quiet premium)

One consistent recipe across Today's cards (snapshot, insight, positive actions, health context, summaries):

- Unified corner radius (`largeCardCornerRadius`) and internal padding (20pt), 16pt vertical rhythm between cards.
- Hairline gradient border (existing `premiumEditorBorder`/gradient tokens) applied consistently at 0.5–0.8pt.
- Two-layer shadow token in AppTheme: tight contact shadow (y:1, r:2, low opacity) + wide ambient (y:10, r:24, very low opacity), replacing single-shadow uses on the immersive cards.
- Snapshot icon badges: soft duotone circles (theme accent at ~14% fill, icon at full accent) with a faint top inner highlight.
- Section headers align to the "Today's snapshot" style everywhere.

## 4. Noise reduction

- **Remove the bottom "Period Estimate" card** (`predictionSection`) from the immersive layout — its content (countdown, midpoint, confidence) now lives in the ring center and the ⓘ "About this estimate" sheet. Non-immersive fallback keeps it.
- **Streak badge** becomes a quiet capsule pill (flame + count, hairline border, no loud fill) placed under the ring.
- No other sections move; all accessibility identifiers preserved.

## 5. Header polish

Greeting block unchanged in content; the moon emblem gets a hairline gradient ring (theme accent gradient at ~60% opacity) and a softer, wider glow so it reads as a crafted mark.

## 6. Implementation map

| Area | File |
|---|---|
| `CycleHeroRingPalette` refactor + shadow tokens | `PCOS/PCOS/SharedUI/Styles/AppTheme.swift` |
| `LunarCycleHeroRing` rewrite (Silk Comet + motion), streak pill, remove immersive `predictionSection`, emblem ring | `PCOS/PCOS/Features/Cycle/Views/TodayView.swift` |
| `ringMotionStyle` flag + launch-arg plumbing | `PCOS/PCOS/SharedUI/Styles/RingMotionStyle.swift` (self-contained; amended from AppearancePreferences during implementation), `PCOS/PCOS/App/CycleBalanceApp.swift` |
| DEBUG Settings toggle | `PCOS/PCOS/App/SettingsView.swift` |

Constraints: no SwiftData changes; no accessibility identifier renames; Swift 6 strict concurrency; all 9 themes via token branches only.

## 7. Verification

- Debug + Release builds; full `PCOSTests` (598) and affected UI tests (`testTodayHeroResolvesToSingleCurrentCycleCardWithoutOverlap`, Lunar Calm suite) stay green.
- 9-theme simulator screenshot sweep (existing launch-arg loop), including day-2 (near-empty arc) and day-late states.
- Two screen recordings (subtle vs. alive) via `simctl io recordVideo` presented to the user in the visual companion for the final motion decision.
