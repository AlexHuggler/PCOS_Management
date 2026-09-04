import Foundation

/// Copy for the post-pregnancy state. A loss must never read as "postpartum day N" or nudge the
/// user to resume cycle tracking.
enum PregnancyCopy {
    static func postpartumHeadline(dayCount: Int?, endReason: PregnancyEndReason?, language: AppLanguage? = nil) -> String {
        switch endReason {
        case .loss:
            return L10n.string("Taking things at your pace", defaultValue: "Taking things at your pace", language: language)
        case .other:
            return L10n.string("Cycle tracking is paused", defaultValue: "Cycle tracking is paused", language: language)
        case .delivery, nil:
            if let dayCount {
                return L10n.format("Postpartum — Day %lld", defaultValue: "Postpartum — Day %lld", language: language, Int64(dayCount))
            }
            return L10n.string("Postpartum", defaultValue: "Postpartum", language: language)
        }
    }

    static func postpartumSubtitle(endReason: PregnancyEndReason?, language: AppLanguage? = nil) -> String {
        switch endReason {
        case .loss:
            return L10n.string(
                "Predictions stay paused until you log a period. Log symptoms whenever it helps, and take the time you need.",
                defaultValue: "Predictions stay paused until you log a period. Log symptoms whenever it helps, and take the time you need.",
                language: language
            )
        case .other:
            return L10n.string(
                "Predictions stay paused until you log a period. Symptom and health logging continue as usual.",
                defaultValue: "Predictions stay paused until you log a period. Symptom and health logging continue as usual.",
                language: language
            )
        case .delivery, nil:
            return L10n.string(
                "Log your first period to resume cycle tracking.",
                defaultValue: "Log your first period to resume cycle tracking.",
                language: language
            )
        }
    }

    static func endConfirmationMessage(for endReason: PregnancyEndReason, language: AppLanguage? = nil) -> String {
        switch endReason {
        case .delivery:
            return L10n.string(
                "Cycle tracking will resume. Your pregnancy data will be preserved.",
                defaultValue: "Cycle tracking will resume. Your pregnancy data will be preserved.",
                language: language
            )
        case .loss:
            return L10n.string(
                "We're sorry. Your records are preserved, predictions stay paused, and nothing will prompt you to log a period until you choose to.",
                defaultValue: "We're sorry. Your records are preserved, predictions stay paused, and nothing will prompt you to log a period until you choose to.",
                language: language
            )
        case .other:
            return L10n.string(
                "Your pregnancy records are preserved and cycle predictions stay paused until you log a period.",
                defaultValue: "Your pregnancy records are preserved and cycle predictions stay paused until you log a period.",
                language: language
            )
        }
    }
}
