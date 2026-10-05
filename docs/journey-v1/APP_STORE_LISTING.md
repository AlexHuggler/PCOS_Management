# CycleBalance — App Store listing for journey v1 (A1)

Status: draft for Alex, 5 Oct 2026. Built from the approved Figma target journey (page `27:14`, step A1)
and the Oct 2 journey audit. Nothing here has been uploaded to App Store Connect.

**Goal of A1:** the store page should show the app people actually get on first launch (Calm theme, light),
promise only what the free app does on day 1, and avoid absolute or medical claims.
**Done when:** every screenshot is taken from the Calm (light) UI, and no text makes a diagnostic,
treatment, prediction or absolute privacy claim.

---

## 1. Rules for every caption and text field

Use

- "see what seems connected", "patterns", "notice", "prepare for appointments", "your records"
- "stays on your iPhone" or "stored on your iPhone by default"
- "Not a medical device" wherever health features are described

Avoid

- Absolutes: "100% private", "no cloud uploads", "completely secure", "never", "guaranteed"
- Medical claims: "diagnose", "treat", "manage your PCOS", "insulin resistance", "predict your period",
  "fertility window" (fertility is optional and hidden by default), "doctor-approved", "clinically proven"
- Urgency or pricing pressure: "limited time", "save now", countdowns, discount badges
- Premium features in the first two screenshots: meal, glucose, supplement and photo logs are Premium

Privacy wording must match the app and the App Privacy label: health records are stored on the device in
Release builds (no iCloud sync); optional network services are App Store / RevenueCat purchases and the
barcode lookup. Analytics, when the TelemetryDeck key is added, sends UI step events only (no health values).

## 2. Screenshot set (6.9" and 6.5", Calm theme, Light mode, en-US)

Shoot on a fresh install with the demo data scenario off unless noted. Status bar 9:41, full battery.
Do not show a name other than a neutral one such as "Maya". Captions are the large line above each screen.

| # | Screen to capture | Caption (headline) | Sub-caption (optional, smaller) |
|---|---|---|---|
| 1 | Today (A8) with mood "Okay" selected, chips Fatigue / Acne / Bloating, ring at 3/7 | A 20-second check-in | Tap how you feel. Every field is optional. |
| 2 | Onboarding first check-in (A5) with Moderate fatigue and Mild acne | Log symptoms in a few taps | Mild, moderate or strong. "Nothing today" counts too. |
| 3 | Insights (14-day dot plots, "Your patterns, with context") using the symptomManagement demo scenario | See what seems connected | Cycles, symptoms, sleep and more, over time. |
| 4 | Calendar (Month) with two logged periods | Your cycles, as they are | Irregular cycles are common. Your history is yours to keep. |
| 5 | Welcome (A2) trust row, or Apple Health step (A7) showing "Read-only" | Private by default | Your records stay on your iPhone. Apple Health is optional and read-only. |
| 6 | Report configuration / PDF preview | Bring a clear summary to appointments | Choose the dates and notes to include. |

Notes

- Screenshots 3 and 6 show features that need several days of data; use the `-uiTest.demoScenario symptomManagement`
  launch argument so no real health data is shown.
- Screenshot 6: the first PDF export is free; unlimited exports are Premium. If a Premium surface is shown,
  add "Premium" in the sub-caption.
- Do not reuse the July Lunar Calm (dark) images: they show a different home screen ("Pattern strength 69%")
  than new users get.

### Localized captions

Translate captions with the same rules. Suggested starting points (native review needed):

| Caption | de | fr | it | ja | ko | nl |
|---|---|---|---|---|---|---|
| A 20-second check-in | Check-in in 20 Sekunden | Un bilan en 20 secondes | Un check-in in 20 secondi | 20秒のチェックイン | 20초 체크인 | Een check-in van 20 seconden |
| See what seems connected | Sieh, was zusammenzuhängen scheint | Voyez ce qui semble lié | Scopri cosa sembra collegato | つながりが見えてくる | 연결된 것처럼 보이는 것을 확인 | Zie wat met elkaar samen lijkt te hangen |
| Private by default | Standardmäßig privat | Privé par défaut | Privato per impostazione predefinita | 標準でプライベート | 기본적으로 비공개 | Standaard privé |

## 3. Text fields (en-US)

**Name:** CycleBalance (unchanged)

**Subtitle (30):** PCOS Cycle & Symptom Tracker (unchanged)

**Promotional text (170):**
Check in in about 20 seconds and, over time, see what seems connected: cycles, symptoms, sleep and more. Your records stay on your iPhone.

**Description:**

> CycleBalance is a calm, private place to keep track of PCOS day to day.
>
> A CHECK-IN IN ABOUT 20 SECONDS
> Tap how you feel, add the symptoms you care about as mild, moderate or strong, or note that there is nothing to report. Every field is optional, and missed days are fine.
>
> SEE WHAT SEEMS CONNECTED
> After a week of check-ins you'll see your first symptom pattern. Over time, CycleBalance shows how cycles, symptoms, sleep and activity line up, so you can notice what seems to matter for you.
>
> YOUR CYCLES, AS THEY ARE
> Log periods and see your full history and your cycle-length range. Irregular cycles are common with PCOS; nothing here assumes a 28-day cycle.
>
> PRIVATE BY DEFAULT
> Your records are stored on your iPhone. Apple Health is optional and read-only: CycleBalance never writes to it. No ads, and we don't sell your data.
>
> READY FOR APPOINTMENTS
> Create a PDF summary for a date range, with only the notes you choose.
>
> CYCLEBALANCE PREMIUM (optional subscription)
> Meal, glucose and supplement logs linked to your symptoms; deeper insights about sleep, activity and meals; unlimited PDF reports; and a private photo journal for skin and hair. Premium is $9.99 per month or $79.99 per year in the US (prices vary by country and are shown in the app before you buy). Subscriptions renew automatically until cancelled; cancel anytime in Settings › Apple Account › Subscriptions at least 24 hours before renewal.
>
> CycleBalance is not a medical device and does not diagnose, treat or prevent any condition. Talk to your healthcare provider about your health.
>
> Terms of Use: https://cyclebalance.app/terms
> Privacy Policy: https://cyclebalance.app/privacy

Check the prices in the description against App Store Connect before submitting; the app itself only shows
store-provided prices.

**Keywords (100):** keep the 2026-06-22 recommendation
`irregular period,blood sugar,meal log,supplements,ovulation,hormones,HealthKit,PDF,glucose,acne`

**What's New (1.0.5 or next):**
A new, faster start: a first check-in during setup, a gentle optional daily reminder, and progress toward
your first pattern on Today. Premium now shows its renewal terms up front, and subscribers can manage their
plan from Settings.

## 4. In-app purchase metadata

| Product | Reference name | Display name (en-US) | Description (en-US) |
|---|---|---|---|
| `cyclebalance.premium.annual` | Premium Yearly | CycleBalance Premium (Yearly) | Meal, glucose and supplement logs, deeper insights and unlimited reports. |
| `cyclebalance.premium.monthly` | Premium Monthly | CycleBalance Premium (Monthly) | Meal, glucose and supplement logs, deeper insights and unlimited reports. |

No introductory offer or free trial at launch (approved decision 1). If a 7-day Yearly trial is added later,
the paywall must show the trial terms next to the button before the test starts.

## 5. App Review notes (paste into App Store Connect)

> CycleBalance is a local-first PCOS tracker. No account is required.
>
> To see the subscription: complete or skip onboarding, then open Settings › Account › Subscription, or tap
> "Log Meal" in the Track tab. The paywall lists Yearly and Monthly with prices from the App Store, renewal
> terms next to the Continue button, Restore purchases, Terms of Use and Privacy Policy. Nothing is purchased
> until Continue is tapped. After purchase, Settings › Subscription opens "Manage subscription"
> (AppStore.showManageSubscriptions).
>
> Previous builds unlocked Premium automatically for sandbox receipts; this build does not, so the
> subscriptions can be purchased and reviewed in the sandbox.
>
> Apple Health access is optional and read-only. Notification permission is requested only after the user
> taps "Turn on reminder" in onboarding. CycleBalance is not a medical device.

## 6. Checklist before submitting

- [ ] New screenshots captured from the Calm (light) build, all six, every locale or en-US fallback
- [ ] Description, promo text and localized descriptions searched for "100%", "no cloud", "diagnos", "treat",
      "predict", "guarantee" — none left
- [ ] App Privacy label matches section 1 (no data linked to identity for health; Purchase History and User ID
      for App Functionality via RevenueCat; add Product Interaction / Analytics only when the TelemetryDeck key ships)
- [ ] IAPs attached to the version, with review screenshot of the new paywall
- [ ] Review notes from section 5 pasted
