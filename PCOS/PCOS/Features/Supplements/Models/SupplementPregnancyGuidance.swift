import Foundation

/// Pregnancy-mode guidance for the supplement logger. The app never decides what is safe; it
/// points the user to their prenatal team and surfaces the catalog's specific cautions.
enum SupplementPregnancyGuidance {
    static func bannerText(language: AppLanguage? = nil) -> String {
        L10n.string(
            "You're in pregnancy mode. Check every supplement with your prenatal team before continuing it.",
            defaultValue: "You're in pregnancy mode. Check every supplement with your prenatal team before continuing it.",
            language: language
        )
    }

    static func caution(for supplement: PCOSSupplement?) -> String? {
        supplement?.pregnancyCaution
    }
}
