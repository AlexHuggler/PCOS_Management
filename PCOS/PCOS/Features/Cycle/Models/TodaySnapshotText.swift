import Foundation

/// Copy for the Today snapshot tiles. Never invents a value for something the user has not logged.
enum TodaySnapshotText {
    static func mood(hasMoodSymptomToday: Bool, language: AppLanguage? = nil) -> String {
        if hasMoodSymptomToday {
            return L10n.string("Tender", defaultValue: "Tender", language: language)
        }
        return L10n.string("Not logged", defaultValue: "Not logged", language: language)
    }

    static func energy(level: Int?, language: AppLanguage? = nil) -> String {
        guard let level else {
            return L10n.string("Not logged", defaultValue: "Not logged", language: language)
        }
        if level >= 4 {
            return L10n.string("High", defaultValue: "High", language: language)
        } else if level <= 2 {
            return L10n.string("Low", defaultValue: "Low", language: language)
        }
        return L10n.string("Medium", defaultValue: "Medium", language: language)
    }
}
