import Foundation

/// Onboarding promises about when insights appear, derived from `InsightThresholds` so the copy
/// can never drift from what the analyzers actually require.
enum OnboardingThresholdCopy {
    static func timelineNote(for goal: PrimaryGoal?, language: AppLanguage? = nil) -> String {
        let cycles = Int64(InsightThresholds.completedCyclesForCyclePatterns)
        let days = Int64(InsightThresholds.trackedSymptomDaysForCorrelations)
        switch goal {
        case .understandSymptoms:
            return L10n.format(
                "Your first symptom patterns can appear after about %lld tracked days.",
                defaultValue: "Your first symptom patterns can appear after about %lld tracked days.",
                language: language,
                days
            )
        default:
            return L10n.format(
                "Your first period estimate appears after your 2nd logged period start. Cycle patterns need %lld completed cycles; symptom patterns can appear after about %lld tracked days.",
                defaultValue: "Your first period estimate appears after your 2nd logged period start. Cycle patterns need %lld completed cycles; symptom patterns can appear after about %lld tracked days.",
                language: language,
                cycles,
                days
            )
        }
    }
}
