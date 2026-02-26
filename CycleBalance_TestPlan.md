# CycleBalance — Pre-App Store Submission Manual Test Plan

> **App:** CycleBalance v1.0.0 (PCOS period & symptom tracker)
> **Platform:** iOS 17.0+ · SwiftUI · SwiftData · CloudKit
> **Date:** 2026-02-25
> **Prepared by:** QA Engineering / App Store Review Readiness

---

## Table of Contents

1. [Test Environment Requirements](#1-test-environment-requirements)
2. [Onboarding Flow (TC-001 – TC-014)](#2-onboarding-flow)
3. [Today Dashboard (TC-015 – TC-030)](#3-today-dashboard)
4. [Calendar View (TC-031 – TC-043)](#4-calendar-view)
5. [Period Logging (TC-044 – TC-058)](#5-period-logging)
6. [Symptom Logging (TC-059 – TC-078)](#6-symptom-logging)
7. [Insights View (TC-079 – TC-083)](#7-insights-view)
8. [Cycle Detail View (TC-084 – TC-090)](#8-cycle-detail-view)
9. [Settings & Data Management (TC-091 – TC-098)](#9-settings--data-management)
10. [iOS & Apple Review Specifics (TC-099 – TC-122)](#10-ios--apple-review-specifics)
11. [Appendix: Known Issues Cross-Reference](#appendix-known-issues-cross-reference)

---

## 1. Test Environment Requirements

| Requirement | Detail |
|---|---|
| Device | iPhone running iOS 17.0+ (physical device required for CloudKit, permissions, and performance tests) |
| Simulator | Xcode 16+ iOS Simulator for layout and functional tests |
| iCloud Account | Signed in to iCloud with CloudKit enabled |
| Network | Wi-Fi and Cellular available; ability to toggle Airplane Mode |
| Accessibility | Settings → Accessibility → Display & Text Size → Larger Text available |
| Appearance | Ability to toggle Dark Mode via Settings → Display & Brightness |
| Locale | Ability to switch device locale (US English + UK English minimum) |
| Clean Install | Ability to delete & reinstall the app for fresh-install tests |
| VoiceOver | Settings → Accessibility → VoiceOver available |

---

## 2. Onboarding Flow

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-001 | Happy Path | Complete full 4-step onboarding flow | Fresh install, app not previously launched | 1. Launch app<br>2. Swipe through 3 WelcomePager pages<br>3. Tap "Get Started"<br>4. Select a primary goal (e.g., "Track my periods")<br>5. Tap Continue<br>6. Select PCOS experience level<br>7. Tap Continue<br>8. Complete the GuidedAction step<br>9. Wait on CompletionView | All 4 steps complete in order. CompletionView auto-advances after ~1.8s. User lands on Today Dashboard. Onboarding does not re-appear on subsequent launches. |
| TC-002 | Happy Path | Skip from WelcomePager | Fresh install | 1. Launch app<br>2. Tap "Skip" on the WelcomePager | User bypasses remaining welcome pages and proceeds to the Questionnaire step. No crash. |
| TC-003 | Happy Path | Skip from Questionnaire | Onboarding at questionnaire step | 1. Tap "Skip" without selecting any answers | Questionnaire is marked complete. User proceeds to GuidedAction. Profile has nil goal and nil experience. |
| TC-004 | Happy Path | WelcomePager page navigation and button text | Fresh install | 1. Launch app<br>2. Observe "Next" button on page 1<br>3. Tap Next to page 2<br>4. Tap Next to page 3<br>5. Observe button text changes | Button reads "Next" on pages 1-2, changes to "Get Started" on page 3. Page indicator dots update. Swipe gestures also work for navigation. |
| TC-005 | Happy Path | Goal "Understand my symptoms" opens SymptomLogView in GuidedAction | Onboarding at questionnaire step | 1. Select "Understand my symptoms" as primary goal<br>2. Tap Continue<br>3. Select any experience level<br>4. Tap Continue<br>5. Observe GuidedAction content | GuidedAction step presents the Symptom Logging sheet. The guided prompt references symptom tracking. |
| TC-006 | Happy Path | Goal "Track my periods" opens CycleLogView in GuidedAction | Onboarding at questionnaire step | 1. Select "Track my periods" as primary goal<br>2. Tap Continue<br>3. Select any experience level<br>4. Tap Continue<br>5. Observe GuidedAction content | GuidedAction step presents the Period Logging sheet. The guided prompt references period tracking. |
| TC-007 | Happy Path | CompletionView auto-advance after 1.8 seconds | Onboarding at completion step | 1. Arrive at CompletionView<br>2. Do not tap anything<br>3. Wait ~2 seconds | View auto-advances to the main app (Today Dashboard) after approximately 1.8 seconds without user interaction. |
| TC-008 | Edge Case | Manual Continue on CompletionView cancels auto-advance | Onboarding at completion step | 1. Arrive at CompletionView<br>2. Immediately tap the "Continue" button before 1.8s | User is taken to Today Dashboard immediately. No duplicate navigation occurs from the timer firing later. |
| TC-009 | Negative | Continue button disabled without questionnaire selection | Onboarding at questionnaire Q1 | 1. Observe the Continue button without selecting a goal<br>2. Tap the Continue button | Continue button is visually disabled (gray). Tapping it has no effect. User cannot advance until a selection is made. |
| TC-010 | Edge Case | Q1 → Q2 is one-way — no back navigation | Onboarding at questionnaire Q2 | 1. Select a goal on Q1<br>2. Tap Continue to advance to Q2<br>3. Attempt to swipe back or find a back button | No back button or swipe-back gesture is available. User cannot return to Q1. Progress dots show 2/2 filled. |
| TC-011 | Happy Path | Skip GuidedAction step | Onboarding at GuidedAction step | 1. Observe the GuidedAction view<br>2. Tap "Skip" or dismiss the presented sheet without completing it | GuidedAction step is marked complete. User advances to CompletionView. No data is logged. |
| TC-012 | Happy Path | GuidedAction sheet dismiss marks step complete | Onboarding at GuidedAction step | 1. Open the presented sheet (CycleLog or SymptomLog)<br>2. Log data and save, or dismiss the sheet<br>3. Observe navigation | After sheet dismissal, onboarding advances to CompletionView regardless of whether data was saved. |
| TC-013 | Edge Case | Force-quit mid-onboarding and relaunch | Onboarding in progress at questionnaire step | 1. Begin onboarding, reach Q2<br>2. Force-quit the app (swipe up from app switcher)<br>3. Relaunch the app | Onboarding restarts from the WelcomePager (phase is @State, not persisted). Previous questionnaire selections are lost. No crash on relaunch. |
| TC-014 | Happy Path | WelcomePager swipe gestures (forward, backward, bounce at edges) | Fresh install, at WelcomePager | 1. Swipe left to advance to page 2<br>2. Swipe right to return to page 1<br>3. Swipe right again on page 1 (edge)<br>4. Swipe left to page 3<br>5. Swipe left again on page 3 (edge) | Forward/backward swiping works. Swiping past the first or last page bounces and does not crash. Page indicator dots update correctly. |

---

## 3. Today Dashboard

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-015 | Happy Path | Welcome state for new user with no data | Onboarding complete, no data logged | 1. Navigate to Today tab<br>2. Observe welcome message | Personalized welcome text is displayed based on the user's primary goal. No cycle day count. Quick action buttons are visible and functional. |
| TC-016 | Happy Path | Cycle day count display after logging period | At least one period entry logged (active cycle exists) | 1. Navigate to Today tab<br>2. Observe the cycle status card | Card displays "Day X of your cycle" where X is the correct number of days since the most recent cycle start. Large hero number is prominent. |
| TC-017 | Happy Path | Quick period log (Light / Medium / Heavy) | Active cycle exists, Today tab visible | 1. Tap "Light" in the quick period log row<br>2. Observe the UI change | The "Light" button shows a selected state (coral background). An undo banner appears at the bottom. A CycleEntry is created for today with flow = .light. |
| TC-018 | Happy Path | Quick period log undo within 4-second window | Quick period log just tapped (undo banner visible) | 1. Tap an intensity button (e.g., Medium)<br>2. Within 4 seconds, tap "Undo" on the banner | The period entry for today is deleted. The intensity button returns to its unselected state. The undo banner disappears. |
| TC-019 | Edge Case | Quick log auto-reset after 4 seconds | Quick period log just tapped | 1. Tap "Heavy" in the quick log row<br>2. Wait 4+ seconds without tapping Undo | The undo banner disappears automatically. The entry persists. The button remains in its logged state for today. |
| TC-020 | Edge Case | Quick log then open full CycleLogView for same day | Quick period log used for today | 1. Quick-log "Light" for today<br>2. Tap "Log Period" to open full CycleLogView<br>3. Change flow to "Heavy" and save | The entry for today is updated (or a second entry is created — verify behavior). No crash. The calendar reflects the most recent flow intensity for today. |
| TC-021 | Happy Path | "Log Period" quick action opens CycleLogView sheet | Today tab visible | 1. Tap the "Log Period" quick action button | CycleLogView opens as a modal sheet with today's date pre-selected. All fields (date, flow intensity, notes) are editable. |
| TC-022 | Happy Path | "Log Symptoms" quick action opens SymptomLogView sheet | Today tab visible | 1. Tap the "Log Symptoms" quick action button | SymptomLogView opens as a modal sheet. Category filter and symptom grid are displayed. |
| TC-023 | Happy Path | Today's symptoms display as severity-colored chips | Symptoms logged for today (e.g., Bloating=3, Fatigue=5) | 1. Navigate to Today tab<br>2. Observe the symptoms section | Symptoms appear as FlowLayout chips. Colors match severity: 1=green, 2=sage, 3=orange, 4=coral, 5=red. Chip text shows symptom name. |
| TC-024 | Happy Path | Prediction card appears with sufficient cycle history | At least 2 completed cycles | 1. Navigate to Today tab<br>2. Scroll to the prediction section | A prediction card displays the estimated next period date range and confidence level. |
| TC-025 | Negative | No prediction card with insufficient data | Fewer than 2 completed cycles | 1. Navigate to Today tab<br>2. Look for prediction section | No prediction card is shown. No error message. The section is either hidden or shows "Need more data" messaging. |
| TC-026 | Happy Path | Streak badge appears at >1 day streak | User has logged data on 2 consecutive days | 1. Navigate to Today tab<br>2. Observe the streak badge | A streak badge displays "2-day streak" (or the correct count). Badge is visible near the top of the dashboard. |
| TC-027 | Edge Case | Streak bounce animation at 7+ days | User has logged data on 7 consecutive days | 1. Navigate to Today tab<br>2. Observe the streak badge animation | The streak badge displays the count (7+) and plays a bounce `.symbolEffect` animation. |
| TC-028 | Happy Path | Post-onboarding hint for calendar tab | Onboarding just completed, first visit to Today tab | 1. Complete onboarding<br>2. Land on Today tab<br>3. Observe the contextual hint | A tooltip/hint pointing toward the Calendar tab appears. Tapping it or the indicated area dismisses the hint. |
| TC-029 | Happy Path | Second hint (log symptoms) shows after first dismissed | First post-onboarding hint was dismissed | 1. Dismiss the calendar hint<br>2. Observe the second hint | A second contextual hint appears, guiding the user to log symptoms. It can be dismissed by tapping. |
| TC-030 | Known Issue | Stale data after midnight — Today's symptoms show yesterday's data (H-7) | Symptoms logged before midnight, app left open | 1. Log symptoms at 11:55 PM<br>2. Leave the app in foreground<br>3. After midnight, check Today tab without navigating away | KNOWN ISSUE H-7: The @Query predicate captures `Date()` at init time. Today's symptom section may still show yesterday's data. Navigating away and back, or relaunching, should refresh. |

---

## 4. Calendar View

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-031 | Happy Path | Calendar displays current month with weekday headers | App has data spanning current month | 1. Navigate to Calendar tab<br>2. Observe the month header and weekday row | Current month and year displayed in the header. Weekday abbreviations (Sun–Sat for US locale) shown. Days are laid out in a 7-column grid aligned to correct weekdays. |
| TC-032 | Happy Path | Navigate previous and next months | Calendar tab visible | 1. Tap the left chevron to go to previous month<br>2. Observe month header updates<br>3. Tap the right chevron twice to go to next month and one more | Month header changes correctly. Grid redraws with the appropriate days. Navigation is smooth with no flickering. |
| TC-033 | Happy Path | Period days color-coded by flow intensity | Period entries with varying intensities across multiple days | 1. Navigate to Calendar tab<br>2. Observe days with period data | Days with logged periods show color-coded filled circles: Heavy = dark coral, Medium = medium coral, Light = light coral, Spotting = pink. Non-period days show no fill. |
| TC-034 | Happy Path | Predicted days shown with dotted coral circles | At least 2 completed cycles, prediction engine active | 1. Navigate to Calendar tab<br>2. Navigate to a future month within the prediction window | Predicted period days display with dotted/dashed coral circle outlines (not filled). They are visually distinct from actual logged days. |
| TC-035 | Happy Path | Tap past day opens CycleLogView with pre-filled date | Calendar showing a past month with data | 1. Tap on a past day in the calendar grid | CycleLogView opens as a sheet. The DatePicker is pre-set to the tapped day's date. If an entry exists for that day, the flow intensity is pre-filled. |
| TC-036 | Negative | Tap future day does nothing | Calendar showing future dates | 1. Navigate to a future month<br>2. Tap on a future date | No sheet opens. No crash. Future days may appear grayed out or non-interactive. |
| TC-037 | Happy Path | Cycle info section with current day, prediction, and avg length | Active cycle with history | 1. Scroll below the calendar grid<br>2. Observe the cycle info section | Section displays current cycle day, predicted next period, and average cycle length. A "Cycle Details" link/button is present. |
| TC-038 | Happy Path | "Cycle Details" navigates to CycleDetailView | Cycle info section visible | 1. Tap "Cycle Details" NavigationLink | CycleDetailView opens with statistics, prediction, and recent cycles list. Back navigation returns to the Calendar. |
| TC-039 | Edge Case | Calendar with empty month — no data, no crash | Navigate to a month with zero entries | 1. Navigate to a past or future month with no logged data<br>2. Observe the grid | Calendar grid renders correctly with all days shown. No crash, no error. Days appear as plain numbers without any color coding. |
| TC-040 | Known Issue | Non-US locale weekday alignment (H-6) | Device locale set to UK English (Monday-start week) | 1. Change device locale to en-GB<br>2. Open Calendar tab<br>3. Compare weekday headers with actual day positions | KNOWN ISSUE H-6: Weekday headers are hardcoded as ["Sun", "Mon", ...] and offset assumes Sunday-start. UK locale users will see days misaligned. Verify the extent of misalignment. |
| TC-041 | Happy Path | Toolbar "+" button opens CycleLogView for today | Calendar tab visible | 1. Tap the "+" button in the toolbar/navigation bar | CycleLogView opens as a sheet with today's date pre-selected. |
| TC-042 | Happy Path | Pull-to-refresh reloads calendar data | Calendar tab visible, recent data change | 1. Log a period entry from another path (e.g., Today tab)<br>2. Return to Calendar tab<br>3. Pull down to refresh | Calendar grid updates to reflect the newly logged entry with appropriate color coding. |
| TC-043 | Edge Case | Navigate 24+ months forward and backward | Calendar tab visible | 1. Tap the next-month chevron 24+ times<br>2. Observe performance<br>3. Tap the previous-month chevron 24+ times back | Navigation remains responsive. No memory warnings, no crash, no accumulated lag. Month headers are accurate throughout. |

---

## 5. Period Logging

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-044 | Happy Path | Log period with default settings | CycleLogView open, no pre-existing entry for today | 1. Open CycleLogView (date = today)<br>2. Select "Medium" flow intensity<br>3. Tap "Log Period Day" | SavedFeedbackOverlay (checkmark) appears for ~0.8s. Sheet auto-dismisses. A CycleEntry is persisted with today's date, medium flow, and empty notes. Calendar shows medium color for today. |
| TC-045 | Happy Path | Log period with all fields populated | CycleLogView open | 1. Select a past date using the DatePicker<br>2. Select "Heavy" flow<br>3. Enter notes: "Severe cramps, took ibuprofen"<br>4. Tap "Log Period Day" | Entry persisted with the selected past date, heavy flow, and notes text. Checkmark overlay appears. Sheet dismisses. |
| TC-046 | Happy Path | Flow intensity picker remembers last selection | A previous period entry was logged with "Light" flow | 1. Open CycleLogView for a new date<br>2. Observe the default flow intensity | The FlowIntensityPicker defaults to the last used intensity (Light) via UserDefaults. |
| TC-047 | Negative | Date picker prevents future dates | CycleLogView open | 1. Attempt to scroll the DatePicker to a future date<br>2. Observe the picker constraints | DatePicker enforces a maximum date of today. Future dates are grayed out or not selectable. |
| TC-048 | Happy Path | "I skipped a period" with confirmation alert | Active cycle exists, CycleLogView open | 1. Tap "I skipped a period" button<br>2. Observe the confirmation alert<br>3. Tap "Skip Period" (destructive action) | Confirmation alert appears with warning text. Upon confirming, the current cycle is closed. A new cycle is started. The sheet dismisses. |
| TC-049 | Negative | Cancel "skip period" alert | "I skipped a period" alert visible | 1. Tap "I skipped a period"<br>2. On the alert, tap "Cancel" | Alert dismisses. No cycle changes. CycleLogView remains open with all fields intact. |
| TC-050 | Edge Case | Unsaved changes detection with notes text | CycleLogView open with no initial changes | 1. Type text in the notes field<br>2. Attempt to dismiss the sheet by tapping Cancel | A confirmation alert appears: "You have unsaved changes. Are you sure you want to discard?" User must choose to discard or keep editing. |
| TC-051 | Happy Path | Discard unsaved changes | Unsaved changes alert visible | 1. After unsaved changes alert appears<br>2. Tap "Discard" | Sheet dismisses. No data is saved. No entry created. |
| TC-052 | Happy Path | Keep editing after cancel attempt | Unsaved changes alert visible | 1. After unsaved changes alert appears<br>2. Tap "Keep Editing" | Alert dismisses. CycleLogView remains open with all entered data intact (date, flow, notes). |
| TC-053 | Edge Case | Interactive dismiss disabled with unsaved changes | CycleLogView with notes entered | 1. Enter text in the notes field<br>2. Attempt to swipe the sheet down to dismiss | Interactive dismiss gesture is blocked. Sheet snaps back to presented position. User must use Cancel button to trigger the unsaved changes flow. |
| TC-054 | Happy Path | Interactive dismiss allowed without changes | CycleLogView with no modifications | 1. Open CycleLogView<br>2. Make no changes<br>3. Swipe the sheet down | Sheet dismisses immediately. No confirmation alert. No data is saved. |
| TC-055 | Edge Case | Cycle boundary — new cycle starts after >10 day gap | Last period entry was 15 days ago | 1. Open CycleLogView for today<br>2. Select any flow intensity<br>3. Tap "Log Period Day"<br>4. Check cycle data | A new Cycle record is created (gap exceeded cycle boundary threshold). The previous cycle is marked as completed. The new entry belongs to the new cycle. |
| TC-056 | Edge Case | Entry within same cycle (≤10 day gap) | Last period entry was 3 days ago | 1. Open CycleLogView for today<br>2. Log a period entry<br>3. Check cycle data | The new entry is added to the existing active cycle. No new Cycle record is created. Cycle day count updates accordingly. |
| TC-057 | Happy Path | CycleLogView initialDate from calendar tap | Calendar view visible with a past date | 1. Tap a specific past date on the calendar (e.g., Feb 10)<br>2. Observe CycleLogView DatePicker | CycleLogView opens with the DatePicker pre-set to February 10. The user can modify it but defaults to the tapped date. |
| TC-058 | Edge Case | Skip period with no existing cycle (no crash) | No cycles or entries exist (fresh user) | 1. Open CycleLogView<br>2. Tap "I skipped a period"<br>3. Confirm the skip | No crash occurs. Behavior is graceful — either the skip is a no-op with a user message, or it handles the nil-cycle state without error. |

---

## 6. Symptom Logging

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-059 | Happy Path | Tap-to-cycle severity (0→1→2→3→4→5→0) with color changes | SymptomLogView open, no pre-existing symptoms today | 1. Tap "Bloating" once (severity 1)<br>2. Tap again (severity 2)<br>3. Continue tapping through 3, 4, 5<br>4. Tap once more (back to 0) | Each tap increments severity by 1 and cycles 5→0. Colors change per level: 1=green, 2=sage, 3=orange, 4=coral, 5=red, 0=gray/unselected. Severity number overlay updates on each tap. |
| TC-060 | Happy Path | Log multiple symptoms and save | SymptomLogView open | 1. Tap "Bloating" to severity 2<br>2. Tap "Fatigue" to severity 3<br>3. Tap "Headache" to severity 1<br>4. Observe save button state (shows "3 selected")<br>5. Tap Save | Save button is enabled. Checkmark overlay appears on save. Sheet auto-dismisses. Three SymptomEntry records persisted with correct severity values. |
| TC-061 | Negative | Save button disabled with no selections | SymptomLogView open, nothing selected | 1. Open SymptomLogView<br>2. Observe Save button state<br>3. Attempt to tap Save | Save button is visually disabled (grayed). Tapping has no effect. Placeholder text "Tap a symptom to get started" is visible. |
| TC-062 | Happy Path | Category filter shows correct symptom counts per category | SymptomLogView open | 1. Tap "Physical" — count symptoms<br>2. Tap "Mood" — count<br>3. Tap "Pain" — count<br>4. Tap "Digestive" — count<br>5. Tap "Metabolic" — count<br>6. Tap "Hair" — count<br>7. Tap "Skin" — count | Physical=5, Mood=4, Pain=3, Digestive=3, Metabolic=3, Hair=3, Skin=3 symptoms shown. Only symptoms of the selected category are visible. |
| TC-063 | Happy Path | "All" category shows all 23 symptoms | SymptomLogView with a category filter active | 1. Tap any specific category<br>2. Confirm fewer than 23 shown<br>3. Tap "All" | Grid displays exactly 23 symptom items. No duplicates, no omissions. 2-column layout accommodates all items. |
| TC-064 | Happy Path | Category filter persists via UserDefaults | SymptomLogView open | 1. Select "Mood" category<br>2. Dismiss the sheet<br>3. Force-quit the app<br>4. Relaunch and open SymptomLogView | "Mood" category is pre-selected on reopen. Only the 4 Mood symptoms are shown. |
| TC-065 | Happy Path | "Same as yesterday" prominent card when yesterday has data | Yesterday: Bloating=3, Fatigue=2 logged. Today: no entries | 1. Open SymptomLogView<br>2. Observe "Same as yesterday" card | A prominent card appears near the top. Tapping it populates Bloating=3 and Fatigue=2 from yesterday. Save button becomes enabled with correct count. |
| TC-066 | Edge Case | "Same as yesterday" hidden/compact after selecting symptoms | Yesterday has data, user starts selecting today | 1. Open SymptomLogView<br>2. Tap "Headache" to severity 1<br>3. Observe "Same as yesterday" card | Card either hides or collapses to a compact state. The manually selected symptom (Headache=1) is unaffected. |
| TC-067 | Negative | "Same as yesterday" not available when no yesterday data | No symptoms logged yesterday | 1. Open SymptomLogView<br>2. Look for "Same as yesterday" card | Card is either hidden or displayed in a disabled/non-interactive state. Tapping it (if visible) has no effect. |
| TC-068 | Happy Path | "Frequent this cycle" suggestions — top 5, tap sets severity 2 | 6+ distinct symptoms logged in last 30 days at varying frequencies | 1. Open SymptomLogView<br>2. Locate "Frequent this cycle" section<br>3. Tap one suggestion | Exactly 5 suggestions shown, ordered by frequency (most frequent first). Tapping a suggestion sets that symptom to severity 2. |
| TC-069 | Happy Path | "Clear all" resets all selections | Multiple symptoms selected at various severities | 1. Select 5+ symptoms at various severities<br>2. Tap "Clear all"<br>3. Observe grid and save button | All symptoms reset to severity 0 (gray). Save button returns to disabled state. Selection counter resets to 0. |
| TC-070 | Happy Path | Long-press context menu with 5 severity levels + Clear | SymptomLogView open | 1. Long-press on "Bloating" grid item<br>2. Observe context menu options<br>3. Select severity 4 | Context menu shows 6 options: Mild (1), Light (2), Moderate (3), Significant (4), Severe (5), Clear. Selecting 4 immediately sets Bloating to severity 4 (orange color) without cycling through. |
| TC-071 | Happy Path | Context menu "Clear" resets to severity 0 | Bloating currently at severity 3 | 1. Long-press "Bloating"<br>2. Tap "Clear" | Bloating resets to severity 0 (gray/unselected). Other symptom selections are unaffected. Selection counter decrements by 1. |
| TC-072 | Edge Case | Unsaved changes detection in SymptomLogView | SymptomLogView open, no prior entries today | 1. Tap "Fatigue" to severity 2<br>2. Attempt to dismiss sheet (swipe down or Cancel) | System detects unsaved changes. Confirmation alert appears warning changes will be lost. Sheet does not immediately dismiss. |
| TC-073 | Edge Case | No unsaved-changes warning when re-opening with pre-filled data unchanged | Today's symptoms already saved: Bloating=3, Fatigue=2 | 1. Open SymptomLogView (symptoms pre-fill)<br>2. Make no changes<br>3. Dismiss the sheet | Sheet dismisses immediately without confirmation. System correctly recognizes state matches initial pre-fill. |
| TC-074 | Happy Path | Pre-fill today's existing symptoms on reopen | Symptoms saved today: Bloating=3, Fatigue=2, Headache=1 | 1. Open SymptomLogView<br>2. Observe grid state | All three symptoms pre-filled at correct severities and colors. Other symptoms at 0. Save button reflects current selection count. |
| TC-075 | Known Issue | Duplicate symptom entries on re-save (C-1) | Symptoms saved today | 1. Open SymptomLogView (symptoms pre-fill)<br>2. Tap Save without changes<br>3. Check data store for today's SymptomEntry count | KNOWN ISSUE C-1: After second save, duplicate records are created. SymptomEntry count for today doubles each re-save. Root cause: `saveSymptoms()` inserts new records without deleting existing ones. |
| TC-076 | Edge Case | Save all 23 symptoms at max severity 5 | SymptomLogView with "All" category selected | 1. Set all 23 symptoms to severity 5<br>2. Tap Save<br>3. Measure time to save feedback | All 23 entries persisted. Save completes within 2 seconds. No crash, hang, or memory warning. Checkmark overlay appears normally. |
| TC-077 | Edge Case | Rapid severity cycling — 20+ taps in quick succession | SymptomLogView open | 1. Rapidly tap a single symptom 24 times<br>2. Observe final severity | Severity cycles correctly (24 mod 6 = 0, so back to unselected). No skipped levels, no crash, no UI freeze. Color transitions animate smoothly. |
| TC-078 | Edge Case | Interactive dismiss disabled with unsaved symptom changes | Symptoms selected but not saved | 1. Select 3+ symptoms<br>2. Swipe sheet down to dismiss | Swipe-to-dismiss is blocked. Sheet snaps back. User must use explicit Cancel/Save buttons. |

---

## 7. Insights View

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-079 | Negative | Empty state with fewer than 2 completed cycles | 0 or 1 completed cycles | 1. Navigate to Insights tab<br>2. Observe the displayed view | ContentUnavailableView with chart icon (pulse animation), "No Insights Yet" title, subtitle explaining more data needed. Two action buttons: "Log Period" and "Log Symptoms". |
| TC-080 | Happy Path | Insight cards display all metadata | 3+ completed cycles with generated insights | 1. Navigate to Insights tab<br>2. Observe the first insight card | Card shows: type-specific icon, bold title, content body text, data points count (e.g., "Based on 45 data points"), confidence percentage, and a lightbulb badge on actionable insights. |
| TC-081 | Happy Path | Empty state action buttons open correct sheets | Insights empty state visible | 1. Tap "Log Period" action button<br>2. Verify CycleLogView opens<br>3. Dismiss and tap "Log Symptoms"<br>4. Verify SymptomLogView opens | Both buttons open their respective sheets as modals. Sheets are fully functional. Dismissing returns to Insights. |
| TC-082 | Happy Path | Insights sorted by generatedDate descending | Multiple insights with different dates | 1. Navigate to Insights tab<br>2. Check order of cards | Most recently generated insight appears first. Each subsequent card has an equal or earlier generatedDate. |
| TC-083 | Happy Path | All 6 insight types render correctly | Insights of all types exist | 1. Scroll through all insight cards<br>2. Identify one of each type | All 6 types render: cyclePattern (calendar icon), symptomCorrelation (link icon), supplementEfficacy (pill icon), dietImpact (food icon), sleepActivity (moon icon), seasonalPattern (leaf icon). No rendering errors or missing layouts. |

---

## 8. Cycle Detail View

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-084 | Happy Path | Current cycle day and prediction with confidence ProgressView | Active cycle, 2+ completed prior cycles | 1. Navigate to Cycle Detail (via Calendar → Cycle Details)<br>2. Observe day count and prediction card | Correct cycle day displayed (e.g., "Day 14"). Prediction card shows estimated next period date range. ProgressView displays confidence as filled bar with percentage label. |
| TC-085 | Happy Path | Statistics: average cycle length, range, total cycles | 4 completed cycles: 28, 30, 32, 26 days | 1. View Statistics card in Cycle Detail<br>2. Verify values | Average = 29 days, Range = 26–32 days, Total cycles = 4. All correctly calculated and clearly labeled. |
| TC-086 | Happy Path | Recent cycles list — last 6 in reverse chronological order | 8+ completed cycles | 1. Scroll to Recent Cycles in Cycle Detail<br>2. Count entries and verify order | Exactly 6 cycles displayed (not 8+). Newest first. Each shows start date, end date, and length in days. |
| TC-087 | Negative | No active cycle state | No active cycle (all cycles completed, no new period started) | 1. Navigate to Cycle Detail | "No Active Cycle" label displayed with prompt text. No day count or prediction card. Historical statistics may still show if completed cycles exist. |
| TC-088 | Edge Case | Single completed cycle — avg = range = that length | Exactly 1 completed cycle of 29 days | 1. View Statistics card | Average = 29, Range = 29–29. Total cycles = 1. If prediction exists, confidence is low (insufficient data). |
| TC-089 | Edge Case | Highly irregular PCOS cycles — wide range, low confidence | 5 cycles: 21, 45, 30, 60, 35 days | 1. View Statistics and prediction | Range = 21–60 days. Average ≈ 38 days. Prediction window is wide. Confidence well below 50%. Accurately reflects PCOS irregularity. |
| TC-090 | Happy Path | Pull-to-refresh on Cycle Detail | Cycle Detail view visible | 1. Pull down to refresh<br>2. Observe spinner and data reload | Refresh indicator appears. Data reloads from store. All values update. No crash or layout issue. |

---

## 9. Settings & Data Management

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-091 | Happy Path | Settings view shows all sections and disclaimer | App is running | 1. Navigate to Settings tab<br>2. Scroll through all sections | Sections visible: Account (subscription status), Data (Export, Delete), Health (HealthKit, CloudKit labels), About (version, Privacy Policy, Terms, Replay Tour). Medical disclaimer footer at the bottom. |
| TC-092 | Happy Path | Export Data generates CSV with correct format | Period, symptom, and cycle data exist | 1. Tap "Export Data"<br>2. Inspect the CSV content | CSV contains header: `Type,Date,Detail,Value,Notes`. Period rows have Type="Period", flow detail, value. Symptom rows have Type="Symptom", name, severity. Dates are consistently formatted. Commas in notes are properly escaped. |
| TC-093 | Happy Path | Share Export via iOS share sheet | Export Data triggered | 1. Tap "Export Data"<br>2. Tap the ShareLink/share button | iOS system share sheet appears with the CSV file. File has .csv extension and correct content. Share destinations (AirDrop, Mail, Files, etc.) are available. |
| TC-094 | Edge Case | Export with no data — header-only CSV | Fresh install, no logged data | 1. Navigate to Settings<br>2. Tap "Export Data" | CSV contains only the header row. No data rows. No crash or error. File is valid CSV. |
| TC-095 | Happy Path | Delete All Data with confirmation | Data exists in all entity types | 1. Tap "Delete All Data"<br>2. Observe confirmation alert<br>3. Tap destructive "Delete" button<br>4. Check all tabs | Confirmation alert shows warning. Destructive button is red. After confirming: all CycleEntry, Cycle, SymptomEntry, and Insight records deleted. Dashboard shows empty state. Calendar shows no colored days. Insights shows empty state. |
| TC-096 | Negative | Cancel Delete All Data preserves data | Delete confirmation alert visible | 1. Tap "Delete All Data"<br>2. Tap "Cancel" on the alert | Alert dismisses. All data remains intact and unchanged. Navigating to Dashboard confirms data is still present. |
| TC-097 | Happy Path | Replay Welcome Tour resets onboarding but preserves data | Onboarding completed, data logged | 1. Tap "Replay Welcome Tour"<br>2. Observe onboarding flow restarts<br>3. Complete or skip onboarding<br>4. Check Dashboard for existing data | Onboarding flow replays from WelcomePager. After completing, all previously logged data (periods, symptoms, cycles) remains intact. No data is deleted. |
| TC-098 | Happy Path | HealthKit and CloudKit labels are static stubs | Settings visible | 1. Tap "HealthKit Access" label<br>2. Tap "CloudKit Sync" label | Both are non-interactive static labels. No navigation, no sheets, no alerts. No crash. They indicate future functionality. |

---

## 10. iOS & Apple Review Specifics

### 10.1 Network & CloudKit

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-099 | iOS Specific | Full offline functionality in Airplane Mode | Device with Airplane Mode toggle available | 1. Enable Airplane Mode<br>2. Launch app (or bring to foreground)<br>3. Navigate all 5 tabs<br>4. Log a period entry<br>5. Log symptoms<br>6. Export data | App launches and functions fully. All local data operations succeed. No network error alerts or blocking dialogs appear. All tabs render correctly. Per Apple Review Guideline 2.1, the app must not present errors for offline use. |
| TC-100 | iOS Specific | Toggle Airplane Mode while app is in foreground | App running with data | 1. Start with Wi-Fi enabled<br>2. Log a period entry<br>3. Enable Airplane Mode while on Today tab<br>4. Log a symptom entry<br>5. Disable Airplane Mode<br>6. Wait 30 seconds for CloudKit sync | Both entries persist locally regardless of network state. After reconnecting, CloudKit sync resumes without user intervention. No crash or data loss. |
| TC-101 | iOS Specific | Wi-Fi to Cellular transition during use | Device with both Wi-Fi and Cellular enabled | 1. Connect to Wi-Fi<br>2. Open app and navigate to Calendar<br>3. Disable Wi-Fi (falls back to Cellular)<br>4. Log a period entry<br>5. Navigate between tabs | No disruption to app functionality. Entry is saved. No error dialogs. CloudKit sync adapts to cellular connection transparently. |
| TC-102 | iOS Specific | CloudKit sync recovery after iCloud toggle | iCloud account signed in | 1. Go to iOS Settings → Apple ID → iCloud<br>2. Disable iCloud for CycleBalance<br>3. Return to app, log data<br>4. Re-enable iCloud for CycleBalance<br>5. Wait for sync | App functions without iCloud. After re-enabling, data syncs. No data loss, no duplicate entries from sync conflicts, no crash. |
| TC-103 | iOS Specific | iCloud signed-out — app works with sync disabled | Device with no iCloud account (or signed out) | 1. Sign out of iCloud in iOS Settings<br>2. Launch CycleBalance<br>3. Complete onboarding<br>4. Log period and symptom data<br>5. Navigate all tabs | App launches and functions fully without iCloud. All data persists locally via SwiftData. No CloudKit error alerts. No crash or degraded experience. |
| TC-104 | iOS Specific | No blocking network error dialogs anywhere | Various network states tested | 1. Cycle through: Airplane Mode, Wi-Fi only, Cellular only, no connectivity<br>2. Navigate every screen in each state | No UIAlertController or modal error dialogs appear related to network connectivity at any point. The app degrades gracefully. |

### 10.2 Permission Handling

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-105 | iOS Specific | No permission prompts on first launch | Fresh install | 1. Delete and reinstall the app<br>2. Launch the app<br>3. Complete onboarding<br>4. Navigate all 5 tabs | Zero permission prompts appear during normal app usage. Camera, Photo Library, and HealthKit permissions are not triggered since those features are not yet implemented. Per Apple Guideline 5.1.1, apps must not request permissions for unused functionality. |
| TC-106 | iOS Specific | Camera permission not triggered during normal usage | App installed and running | 1. Navigate to every screen<br>2. Tap every interactive element<br>3. Monitor for camera permission dialog | No camera permission dialog appears at any point. NSCameraUsageDescription is declared but no code path triggers AVFoundation or UIImagePickerController. |
| TC-107 | iOS Specific | Photo Library permission not triggered during normal usage | App installed and running | 1. Navigate to every screen and interaction<br>2. Monitor for photo library permission dialog | No photo library permission dialog appears. NSPhotoLibraryUsageDescription is declared but no code path triggers PHPhotoLibrary. |
| TC-108 | iOS Specific | HealthKit entitlement present but unused — no phantom prompts (M-7) | App installed, HealthKit entitlement in entitlements file | 1. Launch app<br>2. Navigate all screens including Settings → HealthKit Access<br>3. Monitor for HealthKit authorization prompt | KNOWN ISSUE M-7: HealthKit entitlement is declared but unused. Verify no HealthKit authorization prompt appears. If Apple Review flags this, the entitlement must be removed before submission. |
| TC-109 | iOS Specific | Permission rationale strings present in Info.plist | Access to build settings or Info.plist | 1. Check Info.plist for NSCameraUsageDescription<br>2. Check for NSPhotoLibraryUsageDescription<br>3. Verify strings are user-friendly and accurate | Both usage description strings are present, non-empty, and clearly explain why the app may need access (e.g., "To capture hair progress photos"). Strings comply with Apple's requirement for meaningful usage descriptions. |
| TC-110 | iOS Specific | Reset all permissions and relaunch — no immediate prompts | Device Settings → CycleBalance | 1. Go to iOS Settings → CycleBalance<br>2. Reset all permissions (or delete and reinstall)<br>3. Relaunch the app<br>4. Complete onboarding and navigate all tabs | No permission prompts appear on relaunch. All functionality works without requiring any permissions. |

### 10.3 State Restoration

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-111 | iOS Specific | Minimize mid-data-entry, reopen — state preserved | SymptomLogView open with 3 symptoms selected | 1. Select 3 symptoms at various severities<br>2. Press Home button (or swipe up) to minimize<br>3. Wait 10 seconds<br>4. Reopen the app | SymptomLogView is still presented. All 3 symptom selections are preserved at their exact severity levels. No data loss. Sheet did not dismiss during background. |
| TC-112 | iOS Specific | Lock screen during CycleLogView, unlock — form intact | CycleLogView open with notes entered | 1. Open CycleLogView<br>2. Enter notes text and select a flow intensity<br>3. Press the lock button to lock the screen<br>4. Unlock the device | CycleLogView is still open. Notes text is preserved character-for-character. Flow intensity selection is preserved. DatePicker value unchanged. |
| TC-113 | iOS Specific | Force-quit and relaunch — persisted data intact | Data logged (periods, symptoms), onboarding complete | 1. Log a period and symptoms<br>2. Force-quit the app (swipe up from app switcher)<br>3. Relaunch the app | App launches to Today Dashboard (not onboarding). All previously saved period and symptom data is present. Dashboard shows correct cycle day, today's symptoms, and streak. |
| TC-114 | iOS Specific | Extended background (>10 min) and return | App running, data visible | 1. Minimize the app<br>2. Wait 15+ minutes (use other apps to increase memory pressure)<br>3. Reopen CycleBalance | App is responsive immediately. If the process was terminated by the OS, it relaunches cleanly to the last active tab. All persisted data is intact. No blank screens or stale views. |

### 10.4 UI Adaptability

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-115 | iOS Specific | Largest accessibility text size (AX5) on all screens | iOS Settings → Accessibility → Larger Text → maximum slider | 1. Set accessibility text size to AX5 (maximum)<br>2. Launch CycleBalance<br>3. Navigate all 5 tabs<br>4. Open CycleLogView and SymptomLogView<br>5. Check Cycle Detail and Settings | KNOWN ISSUE H-4: Hardcoded `.system(size: 56)`, `.system(size: 48)`, `.system(size: 9)` do not respond to Dynamic Type. Verify which elements fail to scale. All semantic text styles (.title, .body, .caption) should scale. No text should be clipped or overlap. Scroll views should accommodate enlarged content. |
| TC-116 | iOS Specific | Dark Mode on all screens | iOS Settings → Display & Brightness → Dark | 1. Enable Dark Mode<br>2. Navigate all 5 tabs<br>3. Open all sheets (CycleLogView, SymptomLogView)<br>4. Open Cycle Detail, Settings | All backgrounds use dark adaptive colors (warmNeutral = #1E1B19). Flow intensity colors remain distinguishable. Text is readable (white/light on dark). No white flashes between screens. Cards, buttons, and chips adapt correctly. No hardcoded light-only colors. |
| TC-117 | iOS Specific | Light Mode on all screens | iOS Settings → Display & Brightness → Light | 1. Enable Light Mode<br>2. Navigate all 5 tabs and all sheets | All backgrounds use light adaptive colors (warmNeutral = #F8F6F2). Text contrast meets WCAG AA minimum (4.5:1 for body text). All UI elements visible and distinguishable. |
| TC-118 | iOS Specific | VoiceOver navigation through entire app | iOS Settings → Accessibility → VoiceOver → On | 1. Enable VoiceOver<br>2. Swipe through all elements on Today tab<br>3. Navigate to Calendar tab and swipe through days<br>4. Open CycleLogView and navigate all fields<br>5. Open SymptomLogView and navigate the grid<br>6. Check Insights and Settings tabs | All interactive elements have meaningful VoiceOver labels. Buttons announce their purpose. Symptom grid items announce symptom name and current severity. KNOWN ISSUE H-8: CalendarDayCell lacks accessibility labels — VoiceOver users only hear the day number, not flow data or "today" status. All other elements should be navigable. |

### 10.5 In-App Purchases

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-119 | iOS Specific | Premium/Free status display accuracy | App running, no StoreKit integration active | 1. Navigate to Settings<br>2. Observe Account/subscription section | Status displays "Free" (isPremium flag is always false). No "Upgrade" or "Purchase" buttons. No pricing information. No StoreKit prompts. |
| TC-120 | iOS Specific | No dead-end purchase UI or locked features | Navigate entire app | 1. Visit every screen<br>2. Look for any "Premium", "Locked", "Upgrade", or paywall UI<br>3. Tap any premium-related UI if found | No features are gated behind a paywall. No purchase buttons that lead to broken flows. No "Coming Soon" purchase screens. Per Apple Guideline 3.1.1, all purchase flows must be functional or absent. |

### 10.6 Apple Guidelines Compliance

| Test ID | Category | Test Description | Prerequisites | Steps to Execute | Expected Result |
|---------|----------|-----------------|---------------|------------------|-----------------|
| TC-121 | iOS Specific | No placeholder content — Privacy Policy, Terms, disclaimer | App running | 1. Navigate to Settings<br>2. Tap Privacy Policy link<br>3. Tap Terms of Service link<br>4. Verify medical disclaimer text | Privacy Policy and Terms of Service links either open functional web pages or display in-app content. No "lorem ipsum", "TODO", or "coming soon" placeholder text anywhere. Medical disclaimer is present and complete. Per Apple Guideline 2.3.1, no placeholder content allowed. |
| TC-122 | iOS Specific | App launch under 3 seconds, no crashes across all flows | Physical device, cold start | 1. Force-quit the app<br>2. Measure time from app icon tap to Today Dashboard rendered<br>3. Perform a full walkthrough: onboarding, all tabs, all sheets, all data operations<br>4. Monitor for crashes via Xcode console | App reaches the main screen within 3 seconds on a physical device. Zero crashes during the complete walkthrough. No unhandled exceptions in the console. Per Apple Guideline 2.1, the app must not crash. |

---

## Appendix: Known Issues Cross-Reference

The following known issues from `ISSUE_LOG.md` are covered by specific test cases:

| Issue ID | Severity | Description | Test Case(s) |
|----------|----------|-------------|-------------|
| C-1 | Critical | Duplicate symptom entries on re-save | TC-075 |
| C-2 | Critical | Silent `modelContext.save()` — data may not persist | TC-044, TC-060 (verify data actually persists) |
| C-3 | Critical | Silent `modelContext.fetch()` — empty state masks errors | TC-079, TC-087 (verify empty state is genuine) |
| H-1 | High | No error logging infrastructure | Not directly testable via manual testing |
| H-2 | High | ViewModel recreated on every `.onAppear` | TC-043 (performance during rapid navigation) |
| H-3 | High | DateFormatter created per render cycle | TC-043 (calendar navigation smoothness) |
| H-4 | High | Hardcoded font sizes break Dynamic Type | TC-115 |
| H-5 | High | CycleViewModel is a God Object | Not directly testable via manual testing |
| H-6 | High | CalendarMonthView assumes Sunday-start week | TC-040 |
| H-7 | High | @Query predicate captures stale Date() | TC-030 |
| H-8 | High | No accessibility labels on CalendarDayCell | TC-118 |
| M-1 | Medium | SymptomEntry.symptomType stored as String | TC-059, TC-074 (verify types resolve correctly) |
| M-2 | Medium | Insight.body property name shadows SwiftUI | TC-080 (verify insights render) |
| M-3 | Medium | Six SwiftData models with no UI | TC-099 (verify no errors from empty CloudKit tables) |
| M-4 | Medium | No Hashable on @Model classes in ForEach | TC-086 (verify ForEach renders correctly) |
| M-5 | Medium | Hardcoded padding/spacing inconsistent | TC-115, TC-116, TC-117 (visual inspection) |
| M-6 | Medium | FlowIntensity.none confusing in period context | TC-044 (verify picker options) |
| M-7 | Medium | HealthKit entitlement declared but unused | TC-108 |
| M-8 | Medium | CyclePredictionEngine edge case: identical cycles | TC-088 (single cycle), TC-089 (irregular cycles) |

---

**Total Test Cases: 122** (TC-001 through TC-122)

| Category | Count |
|----------|-------|
| Happy Path | 62 |
| Edge Case | 26 |
| Negative | 10 |
| Known Issue | 4 |
| iOS Specific | 20 |
| **Total** | **122** |
