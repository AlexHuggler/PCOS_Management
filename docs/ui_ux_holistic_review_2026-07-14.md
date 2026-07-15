# CycleBalance UI/UX Holistic Review

Date: July 14, 2026

Review target: CycleBalance 1.0.5 release candidate

Scope: onboarding, primary navigation, tracking, nutrition/photo estimate, insights, reports, premium, settings, permissions, accessibility, motion, haptics, and localization

## Executive assessment

CycleBalance already has a warm visual identity, unusually broad PCOS-support coverage, and a strong foundation of reusable SwiftUI components. The largest opportunity is not to add more decoration. It is to make the product feel calmer, more truthful, and more responsive: fewer onboarding decisions, clearer data provenance, one obvious next action per screen, and richer feedback only where it confirms a meaningful user action.

The recommended product direction is **quietly premium clinical warmth**:

- botanical color and soft depth, used with restraint;
- real user data instead of illustrative values that could be mistaken for personal insight;
- progressive disclosure instead of dense cards and front-loaded configuration;
- tactile confirmation for meaningful actions, not every tap;
- motion that explains a state change and fully respects Reduce Motion;
- accessible, interactive visualizations with an equivalent text/table view.

The current RC reconciliation improves the photo-estimate flow, onboarding privacy language, nutrition entry choices, localization, accessibility semantics, and toolkit data handling. It deliberately does not attempt a high-risk redesign immediately before release.

## Experience principles

1. **Truth before delight.** Clearly distinguish measured, imported, estimated, illustrative, and unavailable data.
2. **One primary action.** Every screen should make the next useful step obvious.
3. **Earn each permission.** Ask in context, explain the benefit first, and make deferral safe.
4. **Progressive personalization.** Start with useful defaults; expose deeper themes, goals, and preferences later.
5. **Calm responsiveness.** Use motion and haptics to confirm state changes, completion, and selection.
6. **Private by design.** Sensitive exports, photos, and health connections should communicate scope and retention plainly.
7. **Accessible by construction.** Dynamic Type, VoiceOver, contrast, Reduce Motion, and large hit targets are release criteria.

## Onboarding inventory and recommendations

The current code supports roughly thirteen top-level onboarding moments, with conditional screens and release flags changing the exact path. A user can encounter up to about fifteen visible pages. The 1.0.5 Release configuration keeps the photo-estimate demo disabled.

| Moment | Current friction or risk | Recommended treatment |
| --- | --- | --- |
| Welcome and language | The value proposition competes with setup controls before trust is established. | Lead with one concrete outcome, a clear Continue action, and a secondary language control. Avoid asking for health data here. |
| Theme selection | Nine themes and seven fonts create choice overload; font options do not always demonstrate the final experience strongly enough. | Offer three curated looks with live previews. Move the complete gallery to Settings. Keep a safe, high-contrast default. |
| Name/personal greeting | Personalization is pleasant but can feel mandatory or overly intimate. | Label it optional, explain local/private use, and allow Skip without visual penalty. |
| Goals or questionnaire | Multiple questions can resemble an intake form and delay first value. | Ask no more than three high-signal questions, show why each matters, and defer the rest to contextual setup. |
| Results/profile summary | Long copy and chips can compete with Continue/Skip, especially at large Dynamic Type. | Keep content scrollable, pin actions in the safe area, wrap chips naturally, and state that the summary is based only on answers provided. |
| How CycleBalance helps | Generic feature exposition repeats earlier promises. | Replace with a personalized three-step plan tied to the selected goal. Let each step preview the actual destination. |
| Permissions primer | Bundling camera, notifications, and Health access increases denial and uncertainty. | Separate requests. Ask only when the associated feature is about to be used, with Not now as a first-class path. |
| Health context | Connection language can imply broader or more complete sync than the user approved. | List the exact categories requested and distinguish available, authorized, denied, and not yet requested states. |
| Photo-estimate demo | A camera-like experience can overstate availability while the production feature is release-gated. | Keep hidden while disabled. When enabled, label all nutrition as an estimate, disclose processing/retention before consent, and preserve manual entry. |
| Personalized plan | Plans may feel predetermined when inputs are sparse. | Explain which answers shaped the plan, allow editing, and avoid unsupported medical recommendations. |
| Guided first action | A guided log is valuable but can become another tutorial slide. | Let the user complete a real, reversible action in the production UI and celebrate only after the save succeeds. |
| Social proof or reassurance | Generic claims can feel manufactured and do little to reduce health-data anxiety. | Prefer specific privacy, control, or evidence statements. Use testimonials only when authentic, attributable, and approved. |
| Completion and reminder | Completion can become a dead-end celebration or pressure the user into notifications. | Summarize what is configured, show one next action, and offer reminder timing only after explaining the benefit. |
| Premium offer, when shown | An immediate paywall can interrupt trust formation and obscure what remains usable for free. | Demonstrate a completed value moment first. State the free experience, trial terms, renewal price, restore path, and cancellation terms plainly. |

## Recommended six-moment onboarding

1. **Welcome and language** — one outcome, one Continue action.
2. **Light personalization** — optional name plus three live theme previews.
3. **Choose a focus** — up to three compact goal questions.
4. **See your starting plan** — an honest, interactive preview based on the answers just given.
5. **Complete one useful action** — optionally connect Health or create a quick log; defer camera and notifications until their feature context.
6. **Start Today** — summarize setup, show the first next step, and optionally choose a reminder time.

Progress should communicate meaningful stages rather than slide count. Back should use at least a 44-by-44-point target, preserve state, and never overlap content. Continue and Skip should remain reachable at accessibility text sizes.

## Product-wide surface review

### Today and navigation

- Reduce the number of equally weighted cards. Prioritize one dynamic next-best action, current cycle context, and the most relevant recent trend.
- Preserve a predictable tab structure and avoid changing destinations based on premium state without explanation.
- Use lightweight skeletons for short loads and explicit empty states for missing data; never substitute synthetic personal-looking values.
- Let users customize or collapse lower-priority modules after the core hierarchy is stable.

### Calendar and cycle

- Increase tappable day targets and make selected, logged, predicted, and today states visually distinct without relying on color alone.
- When predictions are unavailable or low-confidence, explain why and what data would improve them.
- Use a bottom sheet or detail region for day information so a tap always produces visible feedback.
- Ensure pregnancy completion language matches the actual outcome selected instead of assuming postpartum state.

### Tracking, symptoms, mood, supplements, and vitals

- Consolidate related entry methods under clear action rows, as the reconciled nutrition flow now does.
- Persist slider and mood selections predictably, with a visible saved state and an undo opportunity.
- Treat temperature unit changes as conversions, never reinterpretations of the stored number.
- Define adherence denominators from the user’s prescribed schedule; do not treat days without a schedule as missed doses.
- Use success haptics only after persistence succeeds and error haptics only for actionable failures.

### Nutrition and photo estimates

- Keep Enter manually, Scan barcode, and Photo estimate as explicit peers; do not make the least reliable method the visual default.
- Label captured nutrition as an estimate everywhere it appears, including history and details.
- Localize the source label at display time while retaining a stable semantic source in storage.
- Let users edit detected foods before saving, retain the original photo only under the stated policy, and expose a clear retake path.
- Do not imply density, volume, or portion accuracy that the underlying model cannot support.

### Insights and visualizations

- Show only trends supported by real data. Empty and insufficient-data states should explain the threshold for an insight.
- Add scrub-to-inspect charts with a visible focus marker, date/value callout, and selection haptic when the selected sample changes.
- Provide period toggles that animate spatially and preserve context rather than redrawing abruptly.
- Pair every chart with a VoiceOver summary and an accessible data table or list.
- Mark predictions and estimates with a consistent visual treatment and confidence explanation.
- Avoid medical-causality language unless the product has evidence and regulatory support for the claim.

### Reports and sharing

- Default sensitive categories off unless they are essential to the report the user explicitly chose.
- Preview exactly what will be exported, who it is intended for, and the date range before creating a file.
- Provide clear redaction controls and explain where generated files are stored.
- Replace clinician-voice or FSA/HSA claims with factual capability language unless formally substantiated.

### Premium and purchase

- Make plan cards fully selectable with clear selected semantics, not merely decorative borders.
- Keep price, period, trial length, renewal terms, Restore Purchases, and legal links readable without scrolling traps.
- Explain locked value in context and preserve the user’s work when they dismiss the offer.
- Avoid surprise gates after data entry. Show the boundary before the user invests effort.

### Settings, Health, notifications, and privacy

- Reflect the operating system’s real permission state rather than treating an in-app toggle as proof of authorization.
- Replace a single Health “Connected” label with category-level authorized/denied/unavailable status.
- Make destructive actions visually distinct, require confirmation, and state scope and reversibility.
- Keep privacy, data export, deletion, subscription management, and support easy to locate.

## Premium interaction system

### Haptics

Centralize feedback so the same semantic event feels the same everywhere:

| Event | Feedback |
| --- | --- |
| Select tab, chip, date, or chart sample | Light selection feedback only when the value changes |
| Save a log, complete onboarding, connect successfully | Success notification after confirmed completion |
| Validation failure or unavailable action | Warning feedback paired with a visible explanation |
| Irrecoverable operation failure | Error feedback paired with recovery guidance |
| Destructive confirmation | Firm impact on confirmation, never on merely opening the dialog |

Do not vibrate for scrolling, passive animation, loading, or repeated taps that do not change state. Respect system haptic and accessibility settings.

### Motion

- Use 180–260 ms transitions for selection and navigation continuity; reserve longer motion for a meaningful completion.
- Animate layout changes with matched context rather than decorative bouncing.
- Use a gentle count or draw animation for newly revealed results only when the values are real.
- Under Reduce Motion, replace translation, scale, parallax, and repeated shimmer with fades or static states.
- Stop celebratory or ambient animation automatically and never make it necessary to understand the screen.

### Visual language

- Keep botanical warmth but reduce simultaneous gradients, glows, borders, and shadows.
- Use one elevated-card recipe, one radius scale, and a restrained semantic color system.
- Increase contrast for secondary text and ensure state is not communicated by color alone.
- Use typography to establish hierarchy before adding containers.
- Prefer real in-product diagrams and data previews over generic device wireframes.

## Accessibility and localization release criteria

- All interactive targets are at least 44 by 44 points and reachable at AX3 Dynamic Type.
- Primary actions remain visible or safely scrollable on the smallest supported phone.
- Custom rows have explicit VoiceOver labels/hints and hide decorative symbols.
- Selected controls expose the selected accessibility trait.
- Charts expose summaries and equivalent values without requiring drag gestures.
- Contrast is checked in light/dark mode and common color-vision conditions.
- Reduce Motion produces a complete, calm alternative.
- Every shipping locale has automated missing-key and duplicate-key validation; untranslated fallback is reviewed in context.
- Copy uses sentence case consistently and avoids clinical promises the product cannot prove.

## Prioritized roadmap

### P0 — Trust and correctness

- Remove or clearly label synthetic personal-looking insight fallbacks.
- Audit all derived health metrics, prediction confidence, temperature conversion, supplement adherence, and pregnancy-end copy.
- Make notification and Health status reflect operating-system authorization.
- Complete the photo-estimate security, benchmark, privacy-policy, and signed-release gates before enabling it in production.

### P1 — Friction and accessibility

- Rebuild onboarding around the six moments above and contextual permission requests.
- Finish smallest-device, AX3, VoiceOver, contrast, and Reduce Motion coverage across onboarding and premium.
- Simplify Today hierarchy and consolidate duplicate tracking entry points.
- Make charts inspectable, accessible, and explicit about real versus estimated data.
- Make premium boundaries and terms clear before users invest effort.

### P2 — Premium delight

- Introduce the centralized haptic taxonomy and motion tokens.
- Standardize card elevation, radii, typography, semantic colors, loading, empty, and error states.
- Add restrained interactive chart feedback, completion moments, and contextual education.
- Complete localized live previews for themes and fonts, with the full gallery in Settings.

## Success measures

- Onboarding completion rate and median time to Today.
- Drop-off by onboarding moment and permission acceptance after contextual prompts.
- First useful action completion within the first session.
- Seven-day return rate for users who complete a real log versus those who do not.
- Premium-offer view-to-trial conversion and dismissal rate, separated by offer context.
- Failed save rate, permission-state mismatch rate, and report abandonment.
- Accessibility defect count from automated and manual VoiceOver/Dynamic Type passes.
- Percentage of insights backed by sufficient real data and percentage carrying an estimate/prediction label when required.

## What was reconciled into 1.0.5 RC

- Truthful conditional onboarding privacy/camera copy and demo behavior.
- Scroll-safe onboarding results with bottom-safe actions and wrapping chips.
- Consolidated Add nutrition choices with explicit VoiceOver semantics.
- Photo estimate terminology, editable detected foods, consent/fallback behavior, and stable UI-test seams.
- Cache-expiry cleanup and safer local toolkit output handling.
- Six-locale string reconciliation and expanded unit/interface/UI coverage.

The deeper onboarding redesign, data-integrity audit, chart system, centralized haptics, and full visual-system refinement remain follow-up work. They should ship in measured tranches after 1.0.5 rather than increasing the release candidate’s risk surface.
