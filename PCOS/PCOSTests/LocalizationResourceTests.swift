import Testing
import Foundation
@testable import PCOS

private let localizedAppDirectoryCandidates = [
    "../PCOS",
    "../PCOS/PCOS",
]

private func resolveLocalizedAppDirectory(from testFileURL: URL) -> URL? {
    for candidate in localizedAppDirectoryCandidates {
        let candidateURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(candidate)
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: candidateURL.appendingPathComponent("Info.plist").path) {
            return candidateURL
        }
    }
    return nil
}

private func loadStringsTable(
    named tableName: String,
    languageIdentifier: String,
    appDirectory: URL
) -> [String: String]? {
    let fileURL = appDirectory
        .appendingPathComponent("\(languageIdentifier).lproj", isDirectory: true)
        .appendingPathComponent("\(tableName).strings")
    return NSDictionary(contentsOf: fileURL) as? [String: String]
}

private func loadStoreKitConfiguration(appDirectory: URL) -> [String: Any]? {
    let fileURL = appDirectory
        .appendingPathComponent("StoreKit", isDirectory: true)
        .appendingPathComponent("PCOS.storekit")

    guard
        let data = try? Data(contentsOf: fileURL),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }

    return object
}

private func storeKitLocalizations(
    for productID: String,
    configuration: [String: Any]
) -> [[String: Any]]? {
    let groups = configuration["subscriptionGroups"] as? [[String: Any]] ?? []

    for group in groups {
        let subscriptions = group["subscriptions"] as? [[String: Any]] ?? []
        if let subscription = subscriptions.first(where: { ($0["productID"] as? String) == productID }) {
            return subscription["localizations"] as? [[String: Any]]
        }
    }

    return nil
}

private func loadSourceFile(
    relativePath: String,
    projectRoot: URL
) throws -> String {
    let fileURL = projectRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: fileURL, encoding: .utf8)
}

private func printfPlaceholders(in value: String) -> [String] {
    let expression = try? NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|@|(?:\.\d+)?f)"#)
    let range = NSRange(value.startIndex..., in: value)
    return expression?.matches(in: value, range: range).compactMap { match in
        guard let range = Range(match.range, in: value) else { return nil }
        return value[range].replacingOccurrences(
            of: #"^%\d+\$"#,
            with: "%",
            options: .regularExpression
        )
    } ?? []
}

private func makeTemporaryLocalizedAppBundle(from appDirectory: URL) throws -> URL {
    let infoPlistURL = appDirectory.appendingPathComponent("Info.plist")
    let tempBundleRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("app")

    try FileManager.default.createDirectory(at: tempBundleRoot, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
        at: infoPlistURL,
        to: tempBundleRoot.appendingPathComponent("Info.plist")
    )

    for languageIdentifier in L10n.supportedLanguageIdentifiers {
        try FileManager.default.copyItem(
            at: appDirectory.appendingPathComponent("\(languageIdentifier).lproj", isDirectory: true),
            to: tempBundleRoot.appendingPathComponent("\(languageIdentifier).lproj", isDirectory: true)
        )
    }

    return tempBundleRoot
}

@Suite("Localization Resources", .serialized)
struct LocalizationResourceTests {
    private let mealReuseLocalizationKeys = [
        "Looks familiar",
        "You can adjust anything before saving.",
        "Use Previous Meal",
        "Scan as New",
        "last logged %@",
    ]
    private let scannerReleaseLocalizationKeys = [
        "A structured estimate may be cached for up to 24 hours so the same request can be reused without another model call.",
        "AI photo allowance",
        "Analysis status unknown",
        "Analysis still processing",
        "Cached result — no fresh AI photo analysis was used.",
        "Check for cached result",
        "Check the same request",
        "Checking again uses the same request ID and cannot create a second charge for this request. Starting a new analysis uses a new request ID and may consume another fresh analysis.",
        "Choose Another Photo",
        "Consider a new analysis",
        "CycleBalance could not confirm whether this analysis completed. Checking again with the same request is safe; starting a new analysis may use another fresh analysis.",
        "CycleBalance could not confirm whether the previous analysis completed.",
        "CycleBalance could not find a verified active monthly or annual subscription.",
        "CycleBalance could not prepare this meal photo for a cloud estimate.",
        "CycleBalance could not reduce this photo to the secure upload limit.",
        "CycleBalance could not verify an active App Store subscription for this analysis.",
        "CycleBalance could not verify this app install. Update the app and try again.",
        "CycleBalance did not receive complete nutrition for %@. Nothing was added to your meal log.",
        "Enter Manually",
        "Enter manually",
        "Enter nutrition manually",
        "Fresh AI photo allowance used",
        "Gemini did not return any foods to review.",
        "Gemini estimate only; review and edit before saving.",
        "Gemini returned a meal estimate CycleBalance could not read.",
        "Go back",
        "Google does not use paid API photos or responses to improve its products, but it may retain the photo and response for up to 55 days for abuse monitoring and legal or regulatory requirements. CycleBalance does not retain the uploaded photo on its server.",
        "If this exact photo has not already been processed on this device, CycleBalance will send one compressed copy to Google Gemini to estimate foods, portions, and nutrients.",
        "Next rolling-window reset in your local time: %@.",
        "No fresh AI photo analysis was used.",
        "Only %lld fresh AI photo analyses remain in this rolling window.",
        "Photo analysis unavailable",
        "Photo estimate",
        "Photo estimates are not configured. Scan a barcode or enter the meal manually.",
        "Photo estimates are temporarily unavailable. Close Photo Estimate to scan a barcode, or enter the meal manually.",
        "Photo estimates are unavailable right now. Close Photo Estimate to scan a barcode, or enter the meal manually.",
        "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually.",
        "Photo meal estimates require an active trial or subscription.",
        "paid",
        "Scan a barcode",
        "sandbox",
        "Send this photo to Google Gemini?",
        "Send to Google Gemini",
        "standard",
        "Start a new billable analysis",
        "Start a separate analysis?",
        "That photo is too large to estimate. Try another photo or enter the meal manually.",
        "That photo could not be reduced to the secure upload limit. Try another photo or enter the meal manually.",
        "That photo request is too large to send. Try another photo or enter the meal manually.",
        "The photo estimate could not start. You can try another photo or enter the meal manually.",
        "The photo estimate timed out. Try again, close Photo Estimate to scan a barcode, or enter the meal manually.",
        "The previous outcome is still unknown. A separate request may consume another fresh AI photo analysis even if the first request completed.",
        "The safe same-request check limit has been reached for now. Use barcode or manual entry, or return later.",
        "The server asked CycleBalance to wait before checking again. Next check: %@.",
        "The standard paid allowance is 10 fresh AI photo analyses in any rolling 24 hours. Trial, sandbox, or temporary service-safeguard limits may be lower. Cached results do not use a fresh analysis.",
        "This rolling window resets as earlier analyses age out; the next reset is shown in your local time: %@.",
        "This analysis is still processing. Check the same request again in about %lld seconds.",
        "This analysis is still processing. Check the same request again shortly.",
        "trial",
        "UPC codes are sent to Open Food Facts for a keyless product lookup. You can review and edit the result before adding it to this meal.",
        "You will review and edit the estimate before anything is added to your meal log.",
        "You've used all %lld fresh AI photo analyses in the current rolling 24-hour %@ allowance. Scan a barcode or enter the meal manually while the window resets.",
        "You've used all fresh AI photo analyses in the current rolling 24-hour allowance. Scan a barcode or enter the meal manually while the window resets.",
        "You've used the lifetime trial AI photo analysis allowance. Scan a barcode or enter the meal manually.",
        "Your fresh AI photo allowance is used for the current rolling window. You can still check for an existing cached result; a cache miss will not dispatch a fresh model analysis.",
        "%lld of %lld fresh AI photo analyses remain in your rolling 24-hour %@ allowance.",
    ]
    private let representativeLocalizableKeys = [
        "Spotting",
        "Premium active",
        "Good afternoon",
        "Good evening",
        "Insight for you",
        "Skip for now",
        "Period May Be Coming",
        "Taken",
        "increase",
        "decrease",
        "How this works",
        "How to read your insights",
        "Built from your logs",
        "Confidence shows pattern strength",
        "Research adds context",
        "Why you're seeing this",
        "Evidence overview",
        "References",
        "Direct study or review for this supplement in PCOS.",
        "What the confidence means",
        "Research context",
        "Sources",
        "View Source",
        "Evidence strength",
        "PCOS-studied",
        "Mixed evidence",
        "Emerging evidence",
        "Limited evidence",
        "General guidance",
        "Insights are based on your personal data and on-device analysis. They are not medical advice.",
    ]
    private let insightExplainerLocalizationKeys = [
        "How this works",
        "How to read your insights",
        "Built from your logs",
        "Each insight comes from patterns in the cycle, symptom, meal, supplement, sleep, and daily data you track on this device.",
        "Confidence shows pattern strength",
        "Higher confidence usually means the app has seen the same pattern more than once in your recent history.",
        "Research adds context",
        "Research helps explain why a pattern may matter, but it does not prove that a study finding caused your specific result.",
        "Why you're seeing this",
        "Evidence overview",
        "References",
        "References expanded",
        "View Source",
        "Premium Insights",
        "Build your first insights",
        "Keep logging period starts and symptoms so this tab can start surfacing useful patterns.",
        "Build your first symptom insights",
        "Symptom correlations need about 14 tracked days, and cycle pattern summaries need 3 complete cycles. Start with daily symptoms and period starts.",
        "Build your first cycle insights",
        "Cycle pattern summaries need 3 complete cycles, and symptom correlations need about 14 tracked days. Keep logging period starts and daily symptoms.",
        "More cycle data will sharpen your insights",
        "Cycle pattern summaries become reliable after 3 complete cycles. Keep logging each period start so your pattern can stabilize.",
        "More symptom days will unlock correlations",
        "Symptom correlations and trends need about 14 tracked days. Daily symptom check-ins are the fastest way to make this tab more useful.",
        "You have the basics covered",
        "Log meals, supplements, sleep, activity, or blood sugar to unlock deeper lifestyle correlations and predictive insights.",
        "Insights are still taking shape",
        "Keep logging consistently. As your data fills in, this tab will highlight stronger cycle and symptom patterns.",
        "Predictive forecasts",
        "Unlock forecast ranges for cycle length and next-week symptom severity when enough data is available.",
        "Meal impact insights",
        "Unlock meal and glycemic impact correlations tied to your next-day symptoms.",
        "Supplement response insights",
        "Unlock adherence and symptom-delta insights for the supplements you track.",
        "Sleep and activity insights",
        "Unlock sleep, activity, and recovery patterns linked to symptom severity.",
        "Seasonal pattern insights",
        "Unlock month-to-month symptom pattern changes as you log across seasons.",
        "Analyzing your data...",
        "Saving insights...",
        "Insight refresh error. %@",
        "Forecast cards compare your recent cycle, symptom, meal, supplement, blood sugar, and daily-log history on this device to estimate a likely range. If the app does not have enough recent or consistent data, it stays cautious or skips the forecast.",
        "This forecast is driven mostly by your own logging history rather than a specific external study, so it should be treated as a personalized estimate, not a medical prediction.",
        "This card compares the length and variability of your completed, non-predicted cycles logged on this device.",
        "PCOS guidelines and review papers treat cycle regularity as an important signal, but this card is still describing your own logged cycle pattern rather than making a diagnosis.",
        "This card looks for symptom timing, clustering, and trend changes across the symptom days and cycle phases you have logged.",
        "PCOS research shows that symptom burden can affect daily life and emotional wellbeing, but this card is still a personal pattern from your own symptom history rather than proof of a cause.",
        "This card compares the glycemic pattern of your logged meals with later symptoms and breakout timing from meals saved on this device.",
        "PCOS lifestyle guidance often focuses on meal quality, blood sugar, and sustainable activity habits. This card uses that context, but the relationship shown here still comes from your own meal and symptom logs.",
        "This card compares your logged sleep, energy, and activity trends with symptom severity from daily logs saved on this device.",
        "Sleep problems are more common in PCOS populations, but this card is still mainly a personal recovery-pattern check from your own logs rather than proof of a cause.",
        "This card compares symptom averages across months using the history you have logged on this device.",
        "Seasonal shifts are not a core benchmark topic in PCOS research, so this card should be read mostly as a personal pattern from your own logs.",
        "These catalog presets are tracking-friendly starting points for commonly discussed supplements. They are not prescriptions, treatment plans, or personalized medical recommendations.",
        "This card compares your logged taken versus missed days, symptom severity, and cycle patterns from supplement entries saved on this device.",
        "This result is mostly a personal adherence pattern from your own logs. Because the supplement does not match a curated preset, the app avoids attaching a broader study list that could feel misleading.",
        "This card compares your logged taken versus missed days, symptom severity, and cycle patterns for the supplement you tracked.",
        "Your card still does not prove that the supplement caused the change; it highlights a pattern worth tracking over time.",
        "Benchmark international guideline used for broad PCOS assessment and management context.",
        "High-level review explaining core PCOS mechanisms and why cycle and metabolic patterns matter.",
        "Guideline-linked review summarizing diet and activity patterns discussed in PCOS care.",
        "Commonly cited evidence showing why exercise and lifestyle patterns are discussed in PCOS management.",
        "Overview of sleep-related difficulties reported more often in PCOS populations.",
        "Shows why symptom burden and emotional wellbeing are often discussed together in PCOS care.",
    ]
    private let supplementEvidenceLocalizationKeys = [
        "International PCOS guideline (2023)",
        "BMJ Medicine review (2023)",
        "PubMed review (2019)",
        "PubMed systematic review (2019)",
        "PubMed overview (2024)",
        "PubMed umbrella review (2024)",
        "PubMed meta-analysis (2017)",
        "PubMed meta-analysis (2018)",
        "PubMed meta-analysis (2019)",
        "PubMed meta-analysis (2021)",
        "PubMed meta-analysis (2024)",
        "PubMed randomized trial (2010)",
        "USPSTF recommendation",
        "Inositol has direct PCOS literature support, especially for insulin-related and reproductive outcomes, though benefit size varies across trials.",
        "Vitamin D has direct PCOS trial and meta-analysis support, but results vary and deficiency status may matter.",
        "Omega-3 has direct PCOS meta-analysis support for selected cardiometabolic markers, though effects are not uniform across outcomes.",
        "Berberine has direct PCOS meta-analysis support for metabolic outcomes, but the trial base is smaller than for core guideline-backed therapies.",
        "N-acetylcysteine has direct PCOS meta-analysis support, but findings are still interpreted cautiously alongside standard care.",
        "Zinc appears in newer mineral-supplement analyses for PCOS, but the overall evidence base is still mixed and not strong enough for a broad treatment claim.",
        "Magnesium appears in newer mineral-supplement analyses for PCOS, but the evidence base is still emerging and should be framed conservatively.",
        "Spearmint tea has small-trial support for androgen-related symptoms, but the evidence base remains limited.",
        "Folate is included as broader preconception and reproductive-health guidance rather than as a direct PCOS treatment recommendation.",
        "Chromium has direct PCOS meta-analysis support for some insulin-resistance markers, but the overall evidence remains mixed.",
    ]
    private let accessibilityAndExportKeys = [
        "Borderline",
        "Previous month",
        "Next month",
        "Jump to month, %@",
        "Double tap to open month and year picker",
        "No flow",
        "Very light, occasional drops",
        "Light flow, minimal pad or tampon use",
        "Moderate, regular pad or tampon use",
        "Heavy flow, frequent pad or tampon changes",
    ]
    private let settingsSubmissionKeys = [
        "Language",
        "App Language",
        "FSA/HSA Tools",
        "CSV Import Guide",
        "Download CSV Template",
        "Share CSV Template",
        "Import External Data (CSV)",
        "Use the CSV template for imports. Each row must set record_type, and unused columns can be left blank.",
        "Export Data (CSV) creates a readable report. Import External Data (CSV) expects the template columns shown here.",
        "Supported Record Types",
        "Format Rules",
        "Required fields",
        "Optional fields",
        "Accepted values",
        "date uses YYYY-MM-DD",
        "timestamp uses ISO8601",
        "time_taken uses HH:mm",
        "taken uses true or false",
        "severity, stress_level, and energy_level use 1-5",
        "daily_log requires at least one of weight, sleep_hours, active_minutes, stress_level, energy_level, or water_oz.",
        "Generate a Letter of Medical Necessity for FSA/HSA reimbursement of PCOS-related wellness expenses.",
        "An unknown error occurred.",
        "Get in Touch with the Dev Team ⚡!",
        "Import Failed",
        "Import Completed with Issues",
        "Import Counts",
        "Inserted",
        "Updated",
        "Skipped",
        "Rejected",
        "Example Issues",
        "And %lld more issues...",
        "No records were imported because the backup could not be validated.",
        "No records were imported because the CSV file could not be validated.",
        "No records were imported. %lld records need attention.",
        "%lld records were applied. %lld records need attention.",
        "%lld inserted • %lld updated • %lld skipped • %lld rejected",
        "%lld imported • %lld rejected • schema v%lld",
        "Manage the optional Apple Health connection for CycleBalance.",
        "Health Data Access",
        "These data types are read only after you connect Apple Health.",
        "Read-only",
        "On device",
        "Health data stays private",
        "CycleBalance reads data only after you grant permission. Data stays on your device and helps enrich logs, trends, and insights.",
        "No writes to Apple Health",
        "Body Mass",
        "HealthKit type: Body Mass",
        "Used for daily weight and weight trends.",
        "Sleep Analysis",
        "HealthKit type: Sleep Analysis",
        "Used for sleep hours and sleep/recovery insights.",
        "Active Energy Burned",
        "HealthKit type: Active Energy Burned",
        "Used as activity context for daily logs and activity insights.",
        "Blood Glucose",
        "HealthKit type: Blood Glucose",
        "Used for blood sugar history and metabolic insight context.",
        "Step Count",
        "HealthKit type: Step Count",
        "Requested for activity context; not saved or used for insights.",
        "Resting Heart Rate",
        "HealthKit type: Resting Heart Rate",
        "Used for daily resting BPM and recovery context.",
        "Connected",
    ]
    private let paywallKeys = [
        "Error",
        "OK",
        "An unknown error occurred.",
        "Unable to load subscription options. Please check your connection and try again.",
        "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.",
        "Purchase failed. Please try again.",
        "Could not restore purchases. Please try again.",
        "Close",
        "Feature",
        "Free",
        "Premium",
        "Local Test Mode",
        "CycleBalance Premium Monthly",
        "CycleBalance Premium Yearly",
        "Basic cycle tracking",
        "Symptom logging",
        "Calendar view",
        "Apple Health sync",
        "Advanced insights",
        "Unlimited PDF reports",
        "Meal & glucose logging",
        "Supplement tracking",
        "Photo journal",
        "Full cycle history",
        "Loading Premium Options...",
        "Restore Purchases",
        "Privacy Policy",
        "Terms of Service",
        "Unlock Premium",
        "Get the full CycleBalance experience",
        "Save %lld%%",
        "Subscriptions Unavailable",
        "Try Again",
        "%lld day",
        "%lld days",
        "%lld week",
        "%lld weeks",
        "%lld month",
        "%lld months",
        "%lld year",
        "%lld years",
    ]
    private let onboardingKeys = [
        "CycleBalance will help you find your rhythm",
        "CycleBalance will help you decode your symptoms",
        "CycleBalance is ready to help",
        "Starting fresh is the hardest part — we'll guide you step by step.",
        "You already know your body. Let's make your data work harder.",
        "Tracking is a powerful first step toward answers.",
        "Your personalized tracking starts now.",
        "Start with a few simple logs, then use patterns as conversation starters with your care team.",
        "Bring cycle, symptom, meal, glucose, and supplement context together without turning it into a diagnosis.",
        "Track what you notice so your next appointment starts with clearer context.",
        "Your tracker is set up around your goals, preferences, and first logs.",
        "Perfect for spotting patterns in your mood and energy levels.",
        "Ideal for tracking how pain and cramps relate to your cycle.",
        "Great for tracking how your skin and hair change across your cycle.",
        "Perfect for spotting trends in your bloating and cravings.",
        "Smart Cycle Calendar",
        "See your cycle at a glance. CycleBalance learns your pattern — even when it's irregular.",
        "Predictions That Adapt",
        "Our predictions improve with every log. No 28-day assumptions.",
        "Daily Symptom Tracking",
        "Log symptoms in seconds. We'll find the patterns you can't see.",
        "Cycle–Symptom Insights",
        "Discover how your symptoms relate to your cycle phase.",
        "Your Personal Health Hub",
        "Track periods, symptoms, and more — all in one private place.",
        "Cycle calendar",
        "See your cycle history at a glance",
        "Period predictions",
        "Smarter forecasts after each cycle",
        "Symptom dashboard",
        "All your symptoms organized in one place",
        "Pattern insights",
        "Connections you can't spot on your own",
        "Personalized tracking",
        "A dashboard built around your needs",
        "Highlighted on your dashboard",
        "Your plan is set — let's get your first data point.",
        "Your insights start with today's first log.",
        "Let's capture your first entry.",
        "We're a small team building this for you — find \"Share Feedback\" in Settings anytime.",
        "Everything's set. Log when you're ready — CycleBalance adapts to your rhythm, not the other way around.",
        "Your tracking journey starts now. You're part of a growing community of women making sense of their symptoms.",
        "You're part of a growing community of women taking control of their PCOS. We're glad you're here.",
        "Help CycleBalance work better",
        "These permissions are optional. You can change them anytime in Settings.",
        "Your data stays on your device. No accounts, no servers, no exceptions.",
        "Camera",
        "Take photos for your hair & skin journal to track changes over time.",
        "See skin and hair changes side by side over months.",
        "Apple Health",
        "Read nutrition, glucose, weight, sleep, steps, activity, and heart rate for richer insights.",
        "See which source apps contributed data and reduce manual entry.",
        "Your first aha moment",
        "CycleBalance connects what you log, what Apple Health can read, and what you review before saving.",
        "Aha preview",
        "Example: if a scanned snack is mostly carbs, pair it with protein or fiber when testing your glucose response.",
        "Apple Health fills in context",
        "Read-only imports can add nutrition, glucose, sleep, activity, steps, weight, and resting heart rate when you choose those permissions. Source summaries show which apps contributed data.",
        "Where: Settings > Apple Health",
        "A barcode can start a meal draft",
        "Scan or type a UPC, look it up with Open Food Facts, then review serving, calories, macros, fiber, and sugar before anything is saved.",
        "Where: Track > Meals > Scan barcode",
        "Track the full PCOS picture",
        "Log cycles, symptoms, meals, glucose, supplements, ovulation clues, photo journal changes, and doctor-ready reports from Track, Today, and Insights.",
        "Where: Track, Today, and Insights",
        "You can log and review",
        "Cycles",
        "Symptoms",
        "Meals",
        "Glucose",
        "Supplements",
        "Ovulation",
        "Photo journal",
        "Reports",
        "Show me how to use it",
        "Skip for now",
        "Support our mission",
        "We're a small team dedicated to giving women with PCOS actionable insights from their data, to manage and improve their lives. A rating on the App Store helps others find us.",
        "Leave a Quick Review",
        "Maybe later",
        "Local health records",
        "Your cycle, symptom, meal, glucose, supplement, and photo logs are stored on your device by default.",
        "Review before saving",
        "Meal and barcode results stay editable so nothing becomes a saved log until you choose it.",
        "Care-team ready",
        "Exportable reports help you bring organized context to appointments without replacing medical care.",
        "Built around your data, not hype",
        "Designed for PCOS-aware tracking, irregular cycles, and reviewable health context.",
        "Built to give women with PCOS the insights they deserve.",
        "Photo meal estimates are coming soon",
        "This sample shows the future photo flow. For this release, barcode scanning and manual meal logging are available now.",
        "Estimated from a sample preview. You would review and edit before saving.",
        "Nutrition values can vary by preparation, portion size, hidden oil, sauce, or dressing. Barcode scanning is available now from meal logging. Photo-based estimates are still being prepared, and every meal stays editable before saving.",
        "Review the source notes, then scan a barcode or log your next meal to see how new entries fit in.",
        "Choose one quick log, scan a barcode, or enter your next meal manually.",
    ]
    private let pregnancyPostpartumKeys = [
        "Cycle Recovery",
        "Cycle tracking and predictions are paused while pregnancy mode is active. Your previous cycle data is safe and will be used to improve predictions once you return to normal tracking.",
        "Cycle tracking will be paused and your current cycle will be closed. You can return to cycle tracking from Settings.",
        "Cycle tracking will resume. Your pregnancy data will be preserved.",
        "Delivery",
        "Due date",
        "End Date",
        "End Pregnancy Mode",
        "End Pregnancy Mode?",
        "End Reason",
        "Enter Pregnancy Mode",
        "Enter Pregnancy Mode?",
        "Estimated Due Date",
        "I have an estimated due date",
        "Log your first period to resume cycle tracking.",
        "Not active",
        "Other",
        "Postpartum",
        "Postpartum — Day %lld",
        "Pregnancy",
        "Pregnancy & Postpartum",
        "Pregnancy Mode",
        "Pregnancy Start Date",
        "Pregnancy loss",
        "Reason",
        "Return to Normal Tracking",
        "Start date",
        "This will pause cycle tracking. You can return to cycle tracking anytime from Settings.",
        "Undo Activation",
        "Week %lld",
        "Week %lld • Trimester %lld",
        "We're learning your new cycle pattern. Keep logging period starts and we'll have an estimate for you soon.",
        "Your cycles may be irregular as your body recovers. Log your first period when it arrives to resume cycle tracking. CycleBalance will adapt its predictions as your cycles stabilize.",
        "Pregnancy mode pauses cycle tracking and predictions while you're expecting. Your existing cycle data is preserved. When you're ready, postpartum mode helps you ease back into tracking as your cycles return.",
    ]
    private let janineGermanRegressionKeys: [String: String] = [
        "Log Ovulation Clues": "Ovulationszeichen erfassen",
        "BBT, cervical mucus, and LH tests": "Basaltemperatur, Zervixschleim und LH-Tests",
        "Basal body temperature": "Basaltemperatur",
        "Temperature unit": "Temperatureinheit",
        "Cervical mucus": "Zervixschleim",
        "LH test": "LH-Test",
        "Not observed": "Nicht beobachtet",
        "Not tested": "Nicht getestet",
        "CycleBalance uses these fertility clues to narrow fertile-window estimates without assuming every cycle ovulates the same way.": "CycleBalance nutzt diese Fruchtbarkeitszeichen, um das fruchtbare Fenster genauer einzugrenzen, ohne anzunehmen, dass jeder Zyklus gleich ovuliert.",
        "Logging Mode": "Erfassungsmodus",
        "Single day": "Einzelner Tag",
        "Date range": "Zeitraum",
        "Suggestions": "Vorschläge",
        "Same as yesterday": "Wie gestern",
        "No period today": "Heute keine Blutung",
        "Are you bleeding today?": "Blutest du heute?",
        "Cycle day %lld": "Zyklustag %lld",
        "Positive actions": "Positive Aktionen",
        "Apple Health context": "Apple-Health-Kontext",
        "Couldn't Save": "Konnte nicht gespeichert werden",
        "Sleep": "Schlaf",
        "Activity": "Aktivität",
        "Weight": "Gewicht",
        "Resting heart rate": "Ruheherzfrequenz",
        "Estimate Update": "Aktualisierte Schätzung",
        "Through today": "Bis heute",
        "Log Period Range": "Periodenzeitraum erfassen",
        "Photo deleted": "Foto gelöscht",
        "No period on this date": "Keine Periode an diesem Datum",
    ]
    private let curatedTranslations: [String: [String: String]] = [
        "ja": [
            "Spotting": "少量出血",
            "Light": "少ない",
            "Heavy": "多い",
            "Taken": "服用済み",
            "Missed": "未服用",
            "Low GI": "低GI",
            "Low GI: %lld meals": "低GIの食事: %lld回",
            "Premium active": "プレミアム有効",
            "Period May Be Coming": "生理が近いかもしれません",
            "Severe": "重度",
            "Supplement History": "サプリ履歴",
            "Close": "閉じる",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "購入は保留中です。StoreKit セッションまたは App Store アカウントで取引を承認してから、もう一度プレミアム状態を更新してください。",
            "Feature": "機能",
            "Premium": "プレミアム",
            "CycleBalance Premium Monthly": "CycleBalance プレミアム 月額",
            "CycleBalance Premium Yearly": "CycleBalance プレミアム 年額",
            "Unlock Premium": "プレミアムをアンロック",
            "Save %lld%%": "%lld%%お得",
            "%lld day": "%lld 日",
            "%lld week": "%lld 週間",
            "%lld weeks": "%lld 週間",
            "%lld month": "%lld か月",
            "%lld months": "%lld か月",
            "%lld year": "%lld 年",
            "%lld years": "%lld 年",
            "Insights": "分析",
            "Track": "記録",
        ],
        "it": [
            "Spotting": "Perdite leggere",
            "Light": "Leggero",
            "Heavy": "Abbondante",
            "Taken": "Assunto",
            "Missed": "Saltato",
            "Low GI": "Basso IG",
            "Low GI: %lld meals": "Basso IG: %lld pasti",
            "Premium active": "Premium attivo",
            "Period May Be Coming": "Le mestruazioni potrebbero arrivare presto",
            "Severe": "Grave",
            "Supplement History": "Storico integratori",
            "Close": "Chiudi",
            "Feature": "Funzionalità",
            "Free": "Gratis",
            "Premium": "Premium",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "L'acquisto è in sospeso. Approva la transazione nella sessione StoreKit o nell'account App Store, quindi prova di nuovo ad aggiornare lo stato Premium.",
            "CycleBalance Premium Monthly": "CycleBalance Premium Mensile",
            "CycleBalance Premium Yearly": "CycleBalance Premium Annuale",
            "Save %lld%%": "Risparmia il %lld%%",
            "%lld day": "%lld giorno",
            "%lld week": "%lld settimana",
            "%lld weeks": "%lld settimane",
            "%lld month": "%lld mese",
            "%lld months": "%lld mesi",
            "%lld year": "%lld anno",
            "%lld years": "%lld anni",
            "Insights": "Analisi",
            "Track": "Registra",
        ],
        "ko": [
            "Spotting": "소량 출혈",
            "Light": "적음",
            "Heavy": "많음",
            "Taken": "복용함",
            "Missed": "미복용",
            "Low GI": "저GI",
            "Low GI: %lld meals": "저GI 식사: %lld회",
            "Premium active": "프리미엄 활성화됨",
            "Period May Be Coming": "생리가 곧 시작될 수 있어요",
            "Severe": "심함",
            "Supplement History": "보충제 기록",
            "Close": "닫기",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "구매가 보류 중입니다. StoreKit 세션 또는 App Store 계정에서 거래를 승인한 후 프리미엄 상태를 다시 새로고침해 주세요.",
            "Feature": "기능",
            "CycleBalance Premium Monthly": "CycleBalance 프리미엄 월간",
            "CycleBalance Premium Yearly": "CycleBalance 프리미엄 연간",
            "Save %lld%%": "%lld%% 절약",
            "%lld day": "%lld일",
            "%lld week": "%lld주",
            "%lld weeks": "%lld주",
            "%lld month": "%lld개월",
            "%lld months": "%lld개월",
            "%lld year": "%lld년",
            "%lld years": "%lld년",
            "Insights": "분석",
            "Track": "기록",
        ],
        "fr": [
            "Spotting": "Légers saignements",
            "Light": "Léger",
            "Heavy": "Abondant",
            "Taken": "Pris",
            "Missed": "Oublié",
            "Low GI": "IG bas",
            "Low GI: %lld meals": "IG bas : %lld repas",
            "Premium active": "Premium actif",
            "Period May Be Coming": "Les règles pourraient bientôt arriver",
            "Severe": "Sévère",
            "Supplement History": "Historique des compléments",
            "Premium": "Premium",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "L'achat est en attente. Approuvez la transaction dans la session StoreKit ou dans votre compte App Store, puis réessayez d'actualiser le statut Premium.",
            "CycleBalance Premium Monthly": "CycleBalance Premium Mensuel",
            "CycleBalance Premium Yearly": "CycleBalance Premium Annuel",
            "Unlock Premium": "Débloquez Premium",
            "Save %lld%%": "Économisez %lld%%",
            "%lld day": "%lld jour",
            "%lld week": "%lld semaine",
            "%lld weeks": "%lld semaines",
            "%lld month": "%lld mois",
            "%lld months": "%lld mois",
            "%lld year": "%lld an",
            "%lld years": "%lld ans",
            "Insights": "Analyses",
            "Track": "Suivi",
        ],
        "de": [
            "Spotting": "Schmierblutung",
            "Light": "Leicht",
            "Heavy": "Stark",
            "Taken": "Eingenommen",
            "Missed": "Ausgelassen",
            "Low GI": "Niedriger GI",
            "Low GI: %lld meals": "Niedriger GI: %lld Mahlzeiten",
            "Premium active": "Premium aktiv",
            "Period May Be Coming": "Die Periode könnte bald einsetzen",
            "Severe": "Schwer",
            "Supplement History": "Supplement-Verlauf",
            "Feature": "Funktion",
            "Free": "Kostenlos",
            "Premium": "Premium",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "Der Kauf steht noch aus. Genehmigen Sie die Transaktion in der StoreKit-Sitzung oder in Ihrem App-Store-Account und aktualisieren Sie dann den Premium-Status erneut.",
            "CycleBalance Premium Monthly": "CycleBalance Premium Monatlich",
            "CycleBalance Premium Yearly": "CycleBalance Premium Jährlich",
            "Save %lld%%": "Spare %lld%%",
            "%lld day": "%lld Tag",
            "%lld week": "%lld Woche",
            "%lld weeks": "%lld Wochen",
            "%lld month": "%lld Monat",
            "%lld months": "%lld Monate",
            "%lld year": "%lld Jahr",
            "%lld years": "%lld Jahre",
            "Insights": "Analysen",
            "Track": "Erfassen",
        ],
        "nl": [
            "Spotting": "Licht bloedverlies",
            "Light": "Licht",
            "Heavy": "Hevig",
            "Taken": "Ingenomen",
            "Missed": "Overgeslagen",
            "Low GI": "Lage GI",
            "Low GI: %lld meals": "Lage GI: %lld maaltijden",
            "Premium active": "Premium actief",
            "Period May Be Coming": "Je menstruatie kan binnenkort beginnen",
            "Severe": "Ernstig",
            "Supplement History": "Supplementgeschiedenis",
            "Close": "Sluiten",
            "Free": "Gratis",
            "Premium": "Premium",
            "Purchase is pending. Approve the transaction in the StoreKit session or App Store account and try refreshing premium status again.": "De aankoop is in behandeling. Keur de transactie goed in de StoreKit-sessie of in je App Store-account en probeer daarna de Premium-status opnieuw te verversen.",
            "CycleBalance Premium Monthly": "CycleBalance Premium Maandelijks",
            "CycleBalance Premium Yearly": "CycleBalance Premium Jaarlijks",
            "Save %lld%%": "Bespaar %lld%%",
            "%lld day": "%lld dag",
            "%lld week": "%lld week",
            "%lld weeks": "%lld weken",
            "%lld month": "%lld maand",
            "%lld months": "%lld maanden",
            "%lld year": "%lld jaar",
            "%lld years": "%lld jaren",
            "Track": "Bijhouden",
        ],
    ]
    private let storeKitLocalesByLanguage = [
        "ja": "ja_JP",
        "it": "it_IT",
        "ko": "ko_KR",
        "fr": "fr_FR",
        "de": "de_DE",
        "nl": "nl_NL",
    ]
    private let localizedProductIDs = [
        "cyclebalance.premium.monthly",
        "cyclebalance.premium.annual",
    ]
    private let tokenPlaceholderPattern = #"__[^"]+__|[A-Z]*TOKEN_[0-9]+__|__[^"]+TOKEN_[0-9]+__"#

    @Test("Localized strings files exist for all supported languages")
    func localizedFilesExist() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            let languageDirectory = appDirectory.appendingPathComponent("\(languageIdentifier).lproj", isDirectory: true)
            let localizablePath = languageDirectory.appendingPathComponent("Localizable.strings").path
            let infoPlistPath = languageDirectory.appendingPathComponent("InfoPlist.strings").path

            #expect(FileManager.default.fileExists(atPath: languageDirectory.path))
            #expect(FileManager.default.fileExists(atPath: localizablePath))
            #expect(FileManager.default.fileExists(atPath: infoPlistPath))
        }
    }

    @Test("Representative localizable strings are translated for all supported languages")
    func representativeStringsAreTranslated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in representativeLocalizableKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Previous meal scan strings are translated for all supported languages")
    func previousMealScanStringsAreTranslated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in mealReuseLocalizationKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing previous-meal localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Previous-meal localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Scanner release strings are translated for all supported languages")
    func scannerReleaseStringsAreTranslated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in scannerReleaseLocalizationKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing scanner localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Scanner localized value for '\(key)' in \(languageIdentifier) fell back to English.")
                #expect(
                    printfPlaceholders(in: value) == printfPlaceholders(in: key),
                    "Scanner placeholders for '\(key)' do not match in \(languageIdentifier): '\(value)'."
                )
            }
        }
    }

    @Test("Scanner release source routes user-visible copy through L10n")
    func scannerReleaseSourceUsesLocalizationHelpers() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }
        let projectRoot = appDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let sourcePaths = [
            "PCOS/PCOS/Features/Meals/MealScan/Remote/GeminiMealScanRemote.swift",
            "PCOS/PCOS/Features/Meals/MealScan/Remote/MealScanImageNormalizer.swift",
            "PCOS/PCOS/Features/Meals/MealScan/ViewModels/MealScanViewModel.swift",
            "PCOS/PCOS/Features/Meals/MealScan/Views/MealScanFlowView.swift",
            "PCOS/PCOS/Features/Meals/Views/MealLogView.swift",
        ]
        let source = try sourcePaths
            .map { try loadSourceFile(relativePath: $0, projectRoot: projectRoot) }
            .joined(separator: "\n")

        for key in scannerReleaseLocalizationKeys {
            let quotedKey = NSRegularExpression.escapedPattern(for: "\"\(key)\"")
            let localizedCallPattern = #"L10n\.(?:string|format)\s*\(\s*"# + quotedKey
            #expect(
                source.range(of: localizedCallPattern, options: .regularExpression) != nil,
                "Scanner release key is not routed through L10n.string or L10n.format: '\(key)'."
            )
        }
        #expect(
            !source.contains("quota.tier"),
            "Scanner UI must format a localized tier display label, not the raw backend tier token."
        )
    }

    @Test("Insight explanation strings are translated for all supported languages")
    func insightExplanationStringsAreTranslated() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let keys = insightExplainerLocalizationKeys + supplementEvidenceLocalizationKeys

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in keys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing insight-localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Insight-localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Curated high-risk localizations match the manual polish set")
    func curatedTranslationsMatchExpectedValues() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for (languageIdentifier, expectedValues) in curatedTranslations {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for (key, expectedValue) in expectedValues {
                #expect(
                    table[key] == expectedValue,
                    "Expected '\(key)' in \(languageIdentifier) to equal '\(expectedValue)', but found '\(table[key] ?? "<missing>")'."
                )
            }
        }
    }

    @Test("Localized Info.plist usage descriptions are present for all supported languages")
    func localizedInfoPlistStringsArePresent() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let usageDescriptionKeys = [
            "NSPhotoLibraryUsageDescription",
            "NSCameraUsageDescription",
            "NSHealthShareUsageDescription",
            "NSHealthUpdateUsageDescription",
        ]

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "InfoPlist", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load InfoPlist.strings for \(languageIdentifier).")
                continue
            }

            for key in usageDescriptionKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized Info.plist value for '\(key)' in \(languageIdentifier).")
            }
        }
    }

    @Test("Accessibility and blood sugar strings are localized for all supported languages")
    func accessibilityAndBloodSugarStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in accessibilityAndExportKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Settings and submission strings are localized for all supported languages")
    func settingsAndSubmissionStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in settingsSubmissionKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Onboarding strings are localized for all supported languages")
    func onboardingStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in onboardingKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized onboarding value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Localized onboarding value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Paywall strings are localized for all supported languages")
    func paywallStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in paywallKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized paywall value for '\(key)' in \(languageIdentifier).")
                if let expectedValue = curatedTranslations[languageIdentifier]?[key] {
                    #expect(
                        value == expectedValue,
                        "Localized paywall value for '\(key)' in \(languageIdentifier) did not match the curated translation."
                    )
                } else {
                    #expect(value != key, "Localized paywall value for '\(key)' in \(languageIdentifier) fell back to English.")
                }
            }
        }
    }

    @Test("BillingProduct paywall text follows explicit app language and supported system locales")
    func billingProductPaywallTextFollowsResolvedLanguage() throws {
        let monthlyProductID = "cyclebalance.premium.monthly"
        let yearlyProductID = "cyclebalance.premium.annual"
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let tempBundleRoot = try makeTemporaryLocalizedAppBundle(from: appDirectory)
        defer { try? FileManager.default.removeItem(at: tempBundleRoot) }

        guard let bundle = Bundle(url: tempBundleRoot) else {
            Issue.record("Unable to instantiate a bundle for the temporary localized app bundle.")
            return
        }

        let monthly = BillingProduct(
            id: monthlyProductID,
            displayName: "CycleBalance Premium Monthly",
            displayPrice: "$9.99",
            price: Decimal(string: "9.99")!,
            subscriptionPeriod: BillingPeriod(unit: .month, value: 1)
        )
        let yearly = BillingProduct(
            id: yearlyProductID,
            displayName: "CycleBalance Premium Yearly",
            displayPrice: "$79.99",
            price: Decimal(string: "79.99")!,
            subscriptionPeriod: BillingPeriod(unit: .year, value: 1)
        )

        #expect(
            monthly.paywallDisplayName(language: .ko, base: bundle) == "CycleBalance 프리미엄 월간"
        )
        #expect(
            monthly.displayPriceWithPeriod(language: .ko, base: bundle) == "$9.99 / 1개월"
        )
        #expect(
            yearly.displayPriceWithPeriod(language: .fr, base: bundle) == "$79.99 / 1 an"
        )
        #expect(
            yearly.displayPriceWithPeriod(language: .de, base: bundle) == "$79.99 / 1 Jahr"
        )
        #expect(
            monthly.displayPriceWithPeriod(language: .en, base: bundle) == "$9.99 / 1 month"
        )
        #expect(
            monthly.paywallDisplayName(
                language: .system,
                base: bundle,
                preferredLanguages: ["ja_JP"]
            ) == "CycleBalance プレミアム 月額"
        )
        #expect(
            monthly.displayPriceWithPeriod(
                language: .system,
                base: bundle,
                preferredLanguages: ["ja_JP"]
            ) == "$9.99 / 1 か月"
        )
    }

    @Test("Pregnancy and postpartum strings are localized for all supported languages")
    func pregnancyAndPostpartumStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            guard let table = loadStringsTable(named: "Localizable", languageIdentifier: languageIdentifier, appDirectory: appDirectory) else {
                Issue.record("Unable to load Localizable.strings for \(languageIdentifier).")
                continue
            }

            for key in pregnancyPostpartumKeys {
                let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                #expect(!value.isEmpty, "Missing localized value for '\(key)' in \(languageIdentifier).")
                #expect(value != key, "Localized value for '\(key)' in \(languageIdentifier) fell back to English.")
            }
        }
    }

    @Test("Janine German screenshot regression strings are localized")
    func janineGermanScreenshotRegressionStringsAreLocalized() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL),
              let table = loadStringsTable(named: "Localizable", languageIdentifier: "de", appDirectory: appDirectory) else {
            Issue.record("Unable to load German Localizable.strings.")
            return
        }

        for (key, expectedValue) in janineGermanRegressionKeys {
            let value = table[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            #expect(value == expectedValue, "Expected German value for '\(key)' to be '\(expectedValue)', found '\(value)'.")
        }
    }

    @Test("Accessibility and export source files route copy through localization helpers")
    @MainActor
    func accessibilityAndExportSourceFilesUseLocalizationHelpers() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)

        let flowPickerSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/SharedUI/Components/FlowIntensityPicker.swift",
            projectRoot: projectRoot
        )
        #expect(flowPickerSource.contains("L10n.flowAccessibilityLabel("))
        #expect(flowPickerSource.contains("L10n.flowAccessibilityHint("))
        #expect(!flowPickerSource.contains("Very light, occasional drops"))
        #expect(!flowPickerSource.contains("Light flow, minimal pad or tampon use"))
        #expect(!flowPickerSource.contains("Moderate, regular pad or tampon use"))
        #expect(!flowPickerSource.contains("Heavy flow, frequent pad or tampon changes"))
        #expect(!flowPickerSource.contains("Double tap to select"))

        let calendarSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/Features/Cycle/Views/CalendarMonthView.swift",
            projectRoot: projectRoot
        )
        #expect(!calendarSource.contains(".accessibilityLabel(\"Previous month\")"))
        #expect(!calendarSource.contains(".accessibilityLabel(\"Next month\")"))
        #expect(!calendarSource.contains(".accessibilityLabel(\"Jump to month,"))
        #expect(!calendarSource.contains(".accessibilityHint(\"Double tap to open month and year picker\")"))
        #expect(!calendarSource.contains("dateString = \"Day \\(day)\""))
        #expect(!calendarSource.contains("parts.append(\"today\")"))
        #expect(!calendarSource.contains("parts.append(\"period\")"))
        #expect(!calendarSource.contains("parts.append(\"predicted period\")"))

        let bloodSugarSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift",
            projectRoot: projectRoot
        )
        #expect(bloodSugarSource.contains("L10n.string("))
        #expect(!bloodSugarSource.contains("return \"Normal\""))
        #expect(!bloodSugarSource.contains("return \"Borderline\""))
        #expect(!bloodSugarSource.contains("return \"Elevated\""))

        let fsaSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/App/FSAHSAResourcesView.swift",
            projectRoot: projectRoot
        )
        #expect(fsaSource.contains("L10n.string(") || fsaSource.contains("String(localized:"))
        #expect(!fsaSource.contains("Section(\"FSA/HSA Reference\")"))
        #expect(!fsaSource.contains("Text(\"Potentially eligible expenses can include condition-related tracking support and clinician-recommended supplies.\")"))
        #expect(!fsaSource.contains("Text(\"Final reimbursement decisions are made by the plan administrator.\")"))
        #expect(!fsaSource.contains("TextField(\"Patient name\""))
        #expect(!fsaSource.contains("TextField(\"Clinician name\""))
        #expect(!fsaSource.contains("TextField(\"Practice / contact\""))
        #expect(!fsaSource.contains("Text(\"Recommended items\")"))
        #expect(!fsaSource.contains("Text(\"Additional notes\")"))
        #expect(!fsaSource.contains("Label(\"Copy Letter\""))
        #expect(!fsaSource.contains("Label(\"Share Letter\""))
        #expect(!fsaSource.contains(".navigationTitle(\"FSA/HSA Tools\")"))

        let letterSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/Core/Services/MedicalNecessityLetterService.swift",
            projectRoot: projectRoot
        )
        #expect(letterSource.contains("private func localized("))
        #expect(letterSource.contains("L10n.string("))
        #expect(letterSource.contains("localized(\"Clinician Name\""))
        #expect(letterSource.contains("localized(\"Practice / Contact\""))
        #expect(letterSource.contains("localized(\"Patient Name\""))
        #expect(letterSource.contains("localized(\"Disclaimer: Template only. Final clinical wording should be reviewed and edited by a licensed clinician.\""))

        let settingsSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/App/SettingsView.swift",
            projectRoot: projectRoot
        )
        #expect(settingsSource.contains("L10n.string("))
        #expect(!settingsSource.contains("Section(\"Language\")"))
        #expect(!settingsSource.contains("Label(\"App Language\""))
        #expect(!settingsSource.contains("Label(\"FSA/HSA Tools\""))
        #expect(!settingsSource.contains(".navigationTitle(\"Settings\")"))

        let todaySource = try loadSourceFile(
            relativePath: "PCOS/PCOS/Features/Cycle/Views/TodayView.swift",
            projectRoot: projectRoot
        )
        #expect(!todaySource.contains("Text(\"Period today?\")"))
        #expect(!todaySource.contains("Text(\"Undo\")"))
        #expect(!todaySource.contains("Text(\"Blood Sugar\")"))
        #expect(!todaySource.contains("Text(\"Supplements\")"))
        #expect(!todaySource.contains("Text(\"Meals\")"))

        let cycleLogSource = try loadSourceFile(
            relativePath: "PCOS/PCOS/Features/Cycle/Views/CycleLogView.swift",
            projectRoot: projectRoot
        )
        #expect(!cycleLogSource.contains("Section(\"Date\")"))
        #expect(!cycleLogSource.contains("Section(\"Flow Intensity\")"))
        #expect(!cycleLogSource.contains("Section(\"Notes\")"))
        #expect(!cycleLogSource.contains(".navigationTitle(\"Log Period\")"))
        #expect(!cycleLogSource.contains("I skipped a period"))
        #expect(!cycleLogSource.contains("logSkippedPeriod()"))
        #expect(cycleLogSource.contains("No period on this date"))
    }

    @Test("Localized strings files do not contain token placeholder markers")
    func localizedStringsDoNotContainTokenPlaceholders() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let expression = try NSRegularExpression(pattern: tokenPlaceholderPattern)

        for languageIdentifier in L10n.supportedLanguageIdentifiers {
            for tableName in ["Localizable", "InfoPlist"] {
                let fileURL = appDirectory
                    .appendingPathComponent("\(languageIdentifier).lproj", isDirectory: true)
                    .appendingPathComponent("\(tableName).strings")
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
                let matches = expression.matches(in: contents, range: range).compactMap {
                    Range($0.range, in: contents).map { String(contents[$0]) }
                }

                #expect(
                    matches.isEmpty,
                    "Found token placeholders in \(languageIdentifier)/\(tableName).strings: \(matches.joined(separator: ", "))"
                )
            }
        }
    }

    @Test("App metadata declares English as the development localization")
    func appMetadataDeclaresEnglishDevelopmentLocalization() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let infoPlistURL = appDirectory.appendingPathComponent("Info.plist")
        guard let infoPlist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any] else {
            Issue.record("Unable to read Info.plist from the localized app resource directory.")
            return
        }

        #expect(infoPlist["CFBundleDevelopmentRegion"] as? String == "en")

        let tempBundleRoot = try makeTemporaryLocalizedAppBundle(from: appDirectory)
        defer { try? FileManager.default.removeItem(at: tempBundleRoot) }

        guard let bundle = Bundle(url: tempBundleRoot) else {
            Issue.record("Unable to instantiate a bundle for the temporary localized app bundle.")
            return
        }

        #expect(bundle.developmentLocalization == "en")
        #expect(Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: ["en", "en-US"]) == ["en"])
    }

    @Test("Runtime localization resolves selected language bundle without relaunch")
    func runtimeLocalizationResolvesSelectedLanguageBundleWithoutRelaunch() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        let tempBundleRoot = try makeTemporaryLocalizedAppBundle(from: appDirectory)
        defer { try? FileManager.default.removeItem(at: tempBundleRoot) }

        guard let bundle = Bundle(url: tempBundleRoot) else {
            Issue.record("Unable to instantiate a bundle for the temporary localized app bundle.")
            return
        }

        #expect(L10n.string("Settings", defaultValue: "Settings", language: .fr, base: bundle) == "Paramètres")
        #expect(L10n.string("Settings", defaultValue: "Settings", language: .ja, base: bundle) == "設定")
        #expect(L10n.string("Settings", defaultValue: "Settings", language: .en, base: bundle) == "Settings")
        #expect(L10n.resolvedLanguageIdentifier(for: .system, preferredLanguages: ["es_ES"]) == "en")
        #expect(
            L10n.string(
                "Settings",
                defaultValue: "Settings",
                language: .system,
                base: bundle,
                preferredLanguages: ["es_ES"]
            ) == L10n.string("Settings", defaultValue: "Settings", language: .en, base: bundle)
        )
        #expect(L10n.resolvedLanguageIdentifier(for: .system, preferredLanguages: ["fr_CA"]) == "fr")
    }

    @Test("StoreKit products include localized metadata for all supported languages")
    func storeKitProductLocalizationsExist() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        guard let appDirectory = resolveLocalizedAppDirectory(from: testFileURL) else {
            Issue.record("Unable to locate the localized app resource directory from the test bundle.")
            return
        }

        guard let configuration = loadStoreKitConfiguration(appDirectory: appDirectory) else {
            Issue.record("Unable to load PCOS.storekit from the app directory.")
            return
        }

        for productID in localizedProductIDs {
            guard let localizations = storeKitLocalizations(for: productID, configuration: configuration) else {
                Issue.record("Unable to find StoreKit localizations for \(productID).")
                continue
            }

            let englishEntry = localizations.first { ($0["locale"] as? String) == "en_US" }
            let englishDisplayName = englishEntry?["displayName"] as? String ?? ""
            let englishDescription = englishEntry?["description"] as? String ?? ""

            for languageIdentifier in L10n.supportedLanguageIdentifiers {
                guard let localeIdentifier = storeKitLocalesByLanguage[languageIdentifier] else {
                    Issue.record("Missing StoreKit locale mapping for \(languageIdentifier).")
                    continue
                }

                let entry = localizations.first { ($0["locale"] as? String) == localeIdentifier }
                #expect(entry != nil, "Missing StoreKit localization for \(productID) in \(localeIdentifier).")

                let displayName = entry?["displayName"] as? String ?? ""
                let description = entry?["description"] as? String ?? ""

                #expect(!displayName.isEmpty, "Missing StoreKit display name for \(productID) in \(localeIdentifier).")
                #expect(!description.isEmpty, "Missing StoreKit description for \(productID) in \(localeIdentifier).")
                #expect(displayName != englishDisplayName, "StoreKit display name for \(productID) in \(localeIdentifier) should not match en_US.")
                #expect(description != englishDescription, "StoreKit description for \(productID) in \(localeIdentifier) should not match en_US.")
            }
        }
    }
}
