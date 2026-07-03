# CycleBalance App Store Optimization Review

Date: 2026-06-22

## Executive recommendation

Keep the public app name as `CycleBalance` for the next pass. It is short, distinctive, and already paired with a strong localized subtitle that carries the core search intent. Do not stuff keywords into the title until App Analytics shows that the app is losing too much brandless PCOS search traffic.

The highest-value first pass is:

1. Reconcile privacy and claim language across App Store metadata, website legal, and App Privacy labels.
2. Remove keyword duplication between subtitle and keyword fields.
3. Localize keyword strategy by actual search language, not word-for-word translation.
4. Use custom product pages for distinct user intents: irregular cycles, metabolic/meal logging, appointment reports, and privacy-first tracking.
5. Run product page optimization on the default listing after the legal/privacy labels are clean.

## Current public listing observations

- Public name: `CycleBalance`.
- Current English subtitle: `PCOS Cycle & Symptom Tracker`.
- Current English keywords in App Store Connect: `PCOS,period tracker,irregular cycle,symptoms,blood sugar,meal log,supplements,ovulation,hormones` with 4 characters remaining.
- Public description and several localized descriptions still use privacy absolutes such as `100% private`, `no cloud uploads`, or equivalent phrasing. That should be softened to match the actual build and policy language: local-first health logs, optional Apple/RevenueCat/barcode services, no third-party ad SDKs.
- Public App Privacy labels still appear broader than the current reviewed behavior, including health/user content/identifier data linked to the user. That is a trust and conversion issue as much as a compliance issue.
- Some locales appear to lag the newest version metadata/screenshots in public App Store pages. English/French/German/Japanese show 1.0.2 language, while Italian/Dutch/Korean public pages still show 1.0.1 wording in the sampled web pages.

## Title and subtitle strategy

### Do not change the default title yet

`CycleBalance` should stay as the default app name for now. Apple says app names should be simple, memorable, distinctive, and up to 30 characters. Adding keywords to the title could help search, but it also risks making the brand feel generic and duplicates work already done by the subtitle.

Only consider a future title test such as `CycleBalance PCOS` if App Analytics shows poor performance for brandless searches after the next metadata cleanup.

### Subtitle

The subtitle is already doing useful ASO work. It should carry the highest-intent phrase for each locale.

| Locale | Current / recommended subtitle | Notes |
| --- | --- | --- |
| en-US | `PCOS Cycle & Symptom Tracker` | Keep. It is clear, under 30 chars, and covers core intent. |
| fr-FR | `Suivi SOPK, Cycles & Symptômes` | Keep or tighten to `SOPK cycles & symptômes`; current is good and natural enough. |
| de-DE | `PCOS Zyklus- & Symptom-Tracker` | Keep. Strong direct match for German search behavior. |
| it-IT | `Tracker PCOS: Ciclo e Sintomi` | Keep. Good coverage; avoid adding medical treatment terms. |
| nl-NL | `PCOS Cyclus & Symptoom Tracker` | Consider `PCOS cyclus & symptomen` for a more natural noun phrase. |
| ja-JP | `PCOS 周期＆症状トラッカー` | Keep. It is compact and clear. |
| ko-KR | `PCOS 주기 및 증상 트래커` | Keep or tighten to `PCOS 주기·증상 트래커`. |

## Keyword field recommendations

Apple recommends avoiding duplicate words already present in the app name, subtitle, or category. The current English keyword field repeats `PCOS`, `cycle`, `symptoms`, and `tracker` concepts that the subtitle already carries, so the keyword field should shift toward adjacent high-intent terms.

### English candidate

`irregular period,blood sugar,meal log,supplements,ovulation,hormones,HealthKit,PDF,glucose,acne`

Length: 95 characters.

Rationale: preserves high-intent terms for irregular periods, glucose/blood sugar, meal logging, supplement tracking, ovulation clues, reports, and PCOS-adjacent symptoms without duplicating subtitle terms.

### Locale keyword candidates

These are first-pass candidates for human review by a native speaker or search-data pass. They are intentionally conservative and avoid competitor names, diagnosis/treatment claims, and unsupported medical promises.

| Locale | Candidate keywords |
| --- | --- |
| fr-FR | `règles irrégulières,glycémie,repas,compléments,ovulation,hormones,rapport,acné` |
| de-DE | `unregelmäßige periode,blutzucker,mahlzeit,nahrungsergänzung,ovulation,hormone,bericht,akne` |
| it-IT | `ciclo irregolare,glicemia,pasti,integratori,ovulazione,ormoni,report,acne,ovaio policistico` |
| nl-NL | `onregelmatige menstruatie,bloedsuiker,maaltijd,supplementen,ovulatie,hormonen,rapport,acne` |
| ja-JP | `生理不順,血糖値,食事記録,サプリ,排卵,ホルモン,レポート,にきび,多嚢胞性卵巣症候群` |
| ko-KR | `불규칙 생리,혈당,식사 기록,영양제,배란,호르몬,리포트,여드름,다낭성난소증후군` |

## Description and promotional text

### Fix before optimizing

Remove or soften these phrases across every locale:

- `100% private`
- `no cloud uploads`
- any wording that implies nothing ever leaves the device

Recommended claim frame:

`Local-first PCOS tracking. Your health logs stay on your device by default, with optional Apple Health, purchases, and barcode lookup services only when you choose those flows.`

### English promotional text candidate

`PCOS tracking for irregular cycles. Log symptoms, glucose, meals, supplements, and reports with local-first health records you can review.`

This is less punchy than the current text, but it is safer and closer to the actual build.

## Localized reviewer and persona names

The app should not invent localized reviewer names or present sample names as App Store reviews. Real App Store reviewer names/usernames are controlled by Apple and should not be localized.

For screenshots, demo data, onboarding examples, and custom product page creative, use localized sample profile names instead:

| Locale | Sample name | Use |
| --- | --- | --- |
| en-US | Maya | Demo profile or screenshot data only |
| fr-FR | Camille | Demo profile or screenshot data only |
| de-DE | Lena | Demo profile or screenshot data only |
| it-IT | Giulia | Demo profile or screenshot data only |
| nl-NL | Noor | Demo profile or screenshot data only |
| ja-JP | はるか | Demo profile or screenshot data only |
| ko-KR | 지민 | Demo profile or screenshot data only |

Do not label these as reviewers unless they come from actual, approved App Store reviews.

## Custom product page strategy

Custom product pages are a strong fit for CycleBalance because the app has several distinct high-intent audiences. Apple allows additional App Store product page versions with unique URLs, localized screenshots/promotional text/app previews, page-specific keywords, and App Analytics measurement.

### Recommended pages

1. `Irregular Cycle Tracker`
   - Avatar: newly diagnosed or frustrated with 28-day-cycle assumptions.
   - Lead feature: irregular-cycle logging, honest confidence ranges, cycle history.
   - Screenshot story: Today, Calendar, cycle detail, symptom context.
   - Keyword intent: irregular period, PCOS cycle, cycle tracker, symptom tracker.

2. `Meals + Glucose Context`
   - Avatar: users trying to connect meals, glucose, energy, cravings, and symptoms.
   - Lead feature: meal logs, barcode lookup, glucose entries, review-before-save.
   - Screenshot story: meal log, barcode review, glucose chart, insight card.
   - Caveat: avoid nutrition accuracy, diagnosis, weight-loss, allergy, or diet-plan claims.

3. `Doctor Visit Reports`
   - Avatar: users preparing for OB/GYN, endocrinology, or primary-care visits.
   - Lead feature: exportable reports and organized longitudinal context.
   - Screenshot story: Insights, report export, tracked categories, care-team note.
   - Caveat: do not imply clinical interpretation or provider replacement.

4. `Privacy-First PCOS Tracker`
   - Avatar: users wary of account-based health apps or ad tracking.
   - Lead feature: local-first logs, optional HealthKit, no third-party ad SDKs.
   - Screenshot story: settings/privacy screen, HealthKit permissions, export/delete controls.
   - Caveat: use `local-first` instead of `100% private`.

5. `Hair, Skin, and Symptom Patterns`
   - Avatar: users tracking acne, hair changes, fatigue, mood, pain, and cycle context.
   - Lead feature: photo journal plus symptom logging.
   - Screenshot story: symptom check-in, photo journal, trend view.
   - Caveat: avoid before/after transformation claims.

### Which to build first

Start with two custom product pages:

1. `Irregular Cycle Tracker`, because it maps to the core differentiator.
2. `Meals + Glucose Context`, because it captures the metabolic/meal angle that many generic period trackers do not own.

Then add `Doctor Visit Reports` once report screenshots are polished.

## Product page optimization

After privacy labels and copy are reconciled, run one product page optimization test on the default page:

- Treatment A: irregular-cycle-first screenshots.
- Treatment B: meal/glucose/context screenshots.
- Treatment C: report/export screenshots.

Keep the title/subtitle stable during the screenshot test so the result is interpretable.

## Follow-up checklist

- Update App Privacy answers to match the current build and RevenueCat/barcode behavior.
- Remove `100% private` and no-cloud absolutes from all App Store localizations.
- Re-check every localized public page after the new metadata propagates.
- Add localized screenshots or screenshots inherited intentionally from English, rather than accidental stale assets.
- Create two custom product pages first: irregular cycles and meal/glucose context.
- Use Apple Ads campaign links and custom product page URLs for attribution experiments.
- Revisit title change only after at least 2 to 4 weeks of App Analytics search data.

## Source notes

- Apple product page guidance: app names and subtitles are each up to 30 characters; descriptions should be accurate and not keyword-stuffed; keywords are limited to 100 characters and should avoid duplicate words, irrelevant terms, competitor names, and trademark misuse.
- Apple search guidance: search relevance uses title, subtitle, keywords, and primary category; screenshots and ratings also affect search result conversion.
- Apple localization guidance: localized metadata and localized keywords make the app searchable in territories where that localization applies.
- Apple custom product page guidance: custom pages can vary screenshots, promotional text, app previews, localizations, keywords, and deep links; they can be measured in App Analytics.
