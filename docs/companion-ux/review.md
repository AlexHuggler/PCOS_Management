# CycleBalance companion experience

Implemented September 5–6, 2026, from the approved review and plan. Target: adults managing PCOS day to day who want useful records with minimal effort. Fertility and weight remain optional. The intended audience includes newly diagnosed people learning which symptoms matter, experienced trackers reducing daily effort, and people preparing for care appointments. These are product hypotheses rather than measured customer segments; no app analytics or user interviews were available.

## Research behind the priorities

PCOS affects an estimated 10–13% of reproductive-aged women and can affect physical, emotional and social well-being beyond reproductive concerns. That breadth supports a flexible everyday companion instead of a default fertility workflow. [WHO fact sheet, January 2026](https://www.who.int/news-room/fact-sheets/detail/polycystic-ovary-syndrome).

The international guideline recommends considering individual priorities, shared decisions, psychological well-being and weight stigma. This informed optional questions, editable focus areas, symptom-neutral language, hidden weight/nutrition numbers by default, and explicit note selection for appointment reports. These are design inferences, not evidence that this app improves health outcomes. [2023 international guideline](https://pmc.ncbi.nlm.nih.gov/articles/PMC10477934/).

Apple Health requires permission by data type and deliberately does not disclose whether read access was denied. An empty result therefore cannot be called a denial or a deletion. The app now describes received records, dates and sources, and makes Health optional. Other apps contribute only the supported records they make available through Apple Health; direct vendor integrations remain future work. [Apple authorization documentation](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Terminology to review in a future editorial pass: Monash's current guideline page reports the name PMOS from May 12, 2026; WHO's January fact sheet uses PCOS. This implementation retains the user's established PCOS positioning and CycleBalance branding. [Monash guideline hub](https://www.monash.edu/medicine/mchri/pcos/guideline).

## Most useful everyday use cases

| Situation | Low-friction experience | Why it matters |
| --- | --- | --- |
| Newly diagnosed or unsure what to track | Explore immediately; try one optional symptom or mood; pin useful fields later | The app can become useful before someone knows their long-term goals. |
| Living with irregular cycles and changing symptoms | Edit a dated check-in, record an explicit symptom-free day, browse full history | Missing entries remain distinguishable from symptom-free days, and a regular cycle is not assumed. |
| Already using Apple Watch or other health apps | Select Apple Health categories; review dated values and sources; retain manual overrides | Reuses supported data that those apps share with Health, without duplicating daily entry. |
| Preparing for a care visit | Choose a date range, concerns and individual private notes for a report | Makes an appointment summary relevant while keeping disclosure deliberate. |
| Maintaining a habit with limited time or energy | Favorite actions, familiar controls, adjustable detail and optional reminders | People can decide which parts of the app deserve daily attention. |

The primary segment is adults seeking everyday symptom understanding and organization. Newly diagnosed, experienced trackers and appointment preparation are behavioral segments; research here does not establish an age, income or geography distribution for paying customers. Validate those assumptions through interviews with current users before narrowing acquisition messaging.

## Implemented

- Optional four-stage onboarding with Back, resume, language choice and immediate Explore Today. Appearance is editable later.
- Persistent native Today, Calendar, Track, Insights and Settings tabs. Calm, Lunar Calm and Botanical Journal presets share workflows; System/Light/Dark is independent. Existing palettes/fonts remain available.
- One date-based check-in for optional mood, energy, symptoms, pain, stress, water and private notes. Missing values remain missing; explicit symptom-free days are recorded. Saving another date preserves today's data and unchanged imported symptom identifiers/notes.
- Personalization for three favorite actions, visible card order, pinned symptoms, Simple/Detailed information, weight/water units and optional weight, nutrition and fertility context.
- A compact Today view, dated Health context, consistent premium labels, and continuation of the selected logger after purchase or restore. A canceled paywall clears the deferred action.
- AI meal scanner hidden by default, with guarded capture/analysis view-model entry points and deferred scanner-only Firebase startup. Manual meals, barcode/photo paths, existing scanned records and backup data remain.
- Apple Health anchored additions and deletions, historical backfill, source UUIDs, overlap-safe sleep, real cycle relationships and manual-value ownership. Failed commits retain prior cursor state. Delete All stops and disables import; backups preserve portable ownership and reset device-specific anchors.
- Actual dated Insights plots and evidence coverage, including reviewed symptom-free days. Recomputed observations replace stale ones. Daily lifestyle evidence uses 90 days; supplement comparisons/readiness use 365 days.
- Full personal cycle history free, with a chronological Calendar list. Other premium boundaries remain.
- Daily check-in reminders omit completed days and route to the appropriate logger. Cold-start notification routes survive onboarding.
- Backward-compatible backup v6 includes check-in fields and customization. CSV escaping preserves commas, quotes and line breaks. Appointment reports include only selected private notes, whole selected dates and relevant Health sources.
- Six non-English language updates (including check-in field labels): German, French, Italian, Japanese, Korean and Dutch.

## Validation

- Debug build: passed.
- Release simulator build: passed (final arm64; arm64 and x86_64 also passed before the final toolbar/localization-only adjustments).
- Full unit suite: **749 tests across 89 suites passed**.
- Independent reviews covered Health reconciliation, check-in preservation, routing, Today freshness, report privacy/date boundaries and source attribution. Actionable findings were fixed; meaningful regression tests cover the data changes.
- Compact iPhone SE (3rd generation), iOS 26.2: all four companion UI tests passed, covering Explore Today, unchanged check-in save state, largest accessibility text, three presets, native tabs, personalization, Calendar List, scanner absence and all seven supported languages.
- Onboarding UI: seven-language welcome/choices/Back/Explore matrix, four-stage flow, retained choices and legacy optional-Health resume passed on iPhone 17 Pro.
- Final compact-screen rerun: all three presets, personalization and Calendar List passed after the toolbar contrast correction.
- Final iPhone 17 Pro run: **749 unit tests and five UI tests passed**, including all companion flows, three presets, seven check-in languages, and the largest accessibility text in both check-in and onboarding. Dark navigation and primary-button contrast, plus localized check-in labels, were checked visually.

The original checkout was preserved while implementation ran in an isolated worktree; only the implementation delta from the captured working baseline is applied back. No deployment, publishing or push is part of this change.

## Remaining validation and later work

Real-device Health authorization, background delivery, source-specific import behavior and entitlement provisioning need device validation; simulator reconciliation tests cannot certify those system behaviors. Human usability sessions should measure first useful action and repeat check-in time; 90 seconds and 20 seconds are targets, not measured outcomes. Translation review by native speakers and VoiceOver user testing remain useful release checks.

Widgets, Shortcuts/App Intents, Watch experiences, direct vendor APIs, rich CSV mapping and website updates are intentionally deferred. Validate demand for these with users after the core experience.

## Screenshots

Captured from the running app on iOS 26.2 with empty test data:

- [Calm Today](screenshots/today-calm.png)
- [Lunar Calm Today](screenshots/today-lunarcalm.png)
- [Botanical Journal Today](screenshots/today-botanicaljournal.png)
- [Daily check-in](screenshots/check-in-en.png)
- [Japanese check-in](screenshots/check-in-ja.png)
- [Largest accessibility text](screenshots/check-in-large-type.png)
