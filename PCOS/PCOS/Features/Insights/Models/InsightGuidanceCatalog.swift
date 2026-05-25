import Foundation

enum InsightGuidanceCatalog {
    static func enrich(_ insight: Insight) {
        let resolvedPhase = inferredPhase(for: insight)
        if insight.phaseContext == nil {
            insight.phaseContext = resolvedPhase
        }
        insight.recommendedActions = recommendedActions(for: insight)
        insight.learnMoreTopic = learnMoreTopic(for: insight, resolvedPhase: resolvedPhase)
    }

    static func inferredPhase(for insight: Insight) -> CyclePhase? {
        if let storedPhase = insight.phaseContext {
            return storedPhase
        }

        let searchableText = [
            insight.title.lowercased(),
            insight.content.lowercased(),
            insight.scientificContent?.lowercased() ?? ""
        ].joined(separator: " ")

        for phase in CyclePhase.allCases {
            if searchableText.contains(phase.displayName.lowercased()) {
                return phase
            }
        }

        return nil
    }

    static func recommendedActions(for insight: Insight) -> [String] {
        switch insight.insightType {
        case .cyclePattern:
            return [
                L10n.string("Keep logging every period start date as soon as you can.", defaultValue: "Keep logging every period start date as soon as you can."),
                L10n.string("Use notes to flag stress, travel, illness, or medication changes around longer cycles.", defaultValue: "Use notes to flag stress, travel, illness, or medication changes around longer cycles."),
                L10n.string("Share repeated long or very irregular cycles with your clinician.", defaultValue: "Share repeated long or very irregular cycles with your clinician.")
            ]
        case .symptomCorrelation:
            return symptomActions(for: inferredPhase(for: insight))
        case .supplementEfficacy:
            return [
                L10n.string("Keep dose and timing consistent if your clinician has recommended the supplement.", defaultValue: "Keep dose and timing consistent if your clinician has recommended the supplement."),
                L10n.string("Note missed days so you can compare adherence with symptom changes.", defaultValue: "Note missed days so you can compare adherence with symptom changes."),
                L10n.string("Review side effects or lack of benefit with your clinician before making big changes.", defaultValue: "Review side effects or lack of benefit with your clinician before making big changes.")
            ]
        case .dietImpact:
            return [
                L10n.string("Repeat meals that leave you feeling steadier and less symptomatic.", defaultValue: "Repeat meals that leave you feeling steadier and less symptomatic."),
                L10n.string("Pair carbs with protein or fiber when possible to support steadier energy.", defaultValue: "Pair carbs with protein or fiber when possible to support steadier energy."),
                L10n.string("Use meal notes to flag foods linked with crashes, cravings, or breakouts.", defaultValue: "Use meal notes to flag foods linked with crashes, cravings, or breakouts.")
            ]
        case .sleepActivity:
            return [
                L10n.string("Aim for a consistent sleep window for the next week if you can.", defaultValue: "Aim for a consistent sleep window for the next week if you can."),
                L10n.string("Compare symptom intensity after lower-sleep days so the pattern stays measurable.", defaultValue: "Compare symptom intensity after lower-sleep days so the pattern stays measurable."),
                L10n.string("Choose gentle movement on lower-energy days instead of stopping completely.", defaultValue: "Choose gentle movement on lower-energy days instead of stopping completely.")
            ]
        case .seasonalPattern:
            return [
                L10n.string("Re-check the pattern over another cycle before making major changes.", defaultValue: "Re-check the pattern over another cycle before making major changes."),
                L10n.string("Use notes to capture stress, travel, weather, and routine shifts around seasonal changes.", defaultValue: "Use notes to capture stress, travel, weather, and routine shifts around seasonal changes."),
                L10n.string("Bring repeat seasonal symptom swings to your clinician if they are disruptive.", defaultValue: "Bring repeat seasonal symptom swings to your clinician if they are disruptive.")
            ]
        }
    }

    static func showsPhaseContext(for insight: Insight) -> Bool {
        if insight.phaseContext != nil {
            return true
        }

        if insight.insightType == .seasonalPattern {
            return false
        }

        return true
    }

    static func phaseSummary(for phase: CyclePhase) -> String {
        switch phase {
        case .menstrual:
            return L10n.string("This pattern lines up with your menstrual phase, when bleeding and inflammation can make symptoms feel louder.", defaultValue: "This pattern lines up with your menstrual phase, when bleeding and inflammation can make symptoms feel louder.")
        case .follicular:
            return L10n.string("This pattern lines up with your follicular phase, when hormones are rising and your cycle is rebuilding after bleeding.", defaultValue: "This pattern lines up with your follicular phase, when hormones are rising and your cycle is rebuilding after bleeding.")
        case .ovulatory:
            return L10n.string("This pattern lines up with your ovulatory phase, when ovulation-related hormone shifts can change how you feel.", defaultValue: "This pattern lines up with your ovulatory phase, when ovulation-related hormone shifts can change how you feel.")
        case .luteal:
            return L10n.string("This pattern lines up with your luteal phase, when progesterone shifts often change mood, appetite, and energy.", defaultValue: "This pattern lines up with your luteal phase, when progesterone shifts often change mood, appetite, and energy.")
        }
    }

    static func unavailablePhaseMessage() -> String {
        L10n.string(
            "Cycle phase estimate unavailable right now because your recent cycle history is too irregular or does not yet show a reliable ovulatory pattern.",
            defaultValue: "Cycle phase estimate unavailable right now because your recent cycle history is too irregular or does not yet show a reliable ovulatory pattern."
        )
    }
}

private extension InsightGuidanceCatalog {
    static func learnMoreTopic(for insight: Insight, resolvedPhase: CyclePhase?) -> String {
        let phaseKey: String
        if showsPhaseContext(for: insight) {
            phaseKey = resolvedPhase?.rawValue ?? "phase_unavailable"
        } else {
            phaseKey = "general"
        }
        return "\(insight.insightType.rawValue).\(phaseKey)"
    }

    static func symptomActions(for phase: CyclePhase?) -> [String] {
        switch phase {
        case .menstrual:
            return [
                L10n.string("Plan lighter days and extra rest around the start of bleeding.", defaultValue: "Plan lighter days and extra rest around the start of bleeding."),
                L10n.string("Use heat, hydration, and symptom notes to track what actually helps.", defaultValue: "Use heat, hydration, and symptom notes to track what actually helps."),
                L10n.string("Share repeated severe pain or heavy symptoms with your clinician.", defaultValue: "Share repeated severe pain or heavy symptoms with your clinician.")
            ]
        case .follicular:
            return [
                L10n.string("Use this phase for steadier routines and note what seems to help symptoms settle.", defaultValue: "Use this phase for steadier routines and note what seems to help symptoms settle."),
                L10n.string("Keep logging energy, mood, and skin changes so you can compare later phases against this baseline.", defaultValue: "Keep logging energy, mood, and skin changes so you can compare later phases against this baseline."),
                L10n.string("Carry forward meals, movement, or sleep habits that feel easiest here.", defaultValue: "Carry forward meals, movement, or sleep habits that feel easiest here.")
            ]
        case .ovulatory:
            return [
                L10n.string("Watch for short-lived symptom spikes and log them the same day so the pattern stays clear.", defaultValue: "Watch for short-lived symptom spikes and log them the same day so the pattern stays clear."),
                L10n.string("Note cervical changes, LH tests, or other ovulation clues if you track fertility.", defaultValue: "Note cervical changes, LH tests, or other ovulation clues if you track fertility."),
                L10n.string("Bring repeated ovulation-time pain or unusual symptoms to your clinician.", defaultValue: "Bring repeated ovulation-time pain or unusual symptoms to your clinician.")
            ]
        case .luteal:
            return [
                L10n.string("Plan more margin for mood, cravings, and energy shifts during this part of your cycle.", defaultValue: "Plan more margin for mood, cravings, and energy shifts during this part of your cycle."),
                L10n.string("Keep meals and sleep as consistent as possible to make this phase easier to compare over time.", defaultValue: "Keep meals and sleep as consistent as possible to make this phase easier to compare over time."),
                L10n.string("Use symptom notes to flag whether stress, sleep, or food patterns make luteal symptoms worse.", defaultValue: "Use symptom notes to flag whether stress, sleep, or food patterns make luteal symptoms worse.")
            ]
        case nil:
            return [
                L10n.string("Keep logging symptoms and period starts so the app has enough history to estimate timing more safely.", defaultValue: "Keep logging symptoms and period starts so the app has enough history to estimate timing more safely."),
                L10n.string("Use notes to capture what was happening around harder symptom days.", defaultValue: "Use notes to capture what was happening around harder symptom days."),
                L10n.string("Bring persistent or worsening symptom clusters to your clinician even when cycle timing is unclear.", defaultValue: "Bring persistent or worsening symptom clusters to your clinician even when cycle timing is unclear.")
            ]
        }
    }
}
