import Foundation

/// App Store Review Guideline 3.1.2 requires the binary itself to state the renewal terms and to
/// link a Terms of Use (EULA). Copy lives here so the paywall and Settings share one wording.
enum SubscriptionDisclosure {
    static func autoRenewText(language: AppLanguage? = nil) -> String {
        L10n.string(
            "Subscriptions renew automatically at the shown price until cancelled at least 24 hours before the current period ends. Manage or cancel any time in Settings > Apple ID > Subscriptions.",
            defaultValue: "Subscriptions renew automatically at the shown price until cancelled at least 24 hours before the current period ends. Manage or cancel any time in Settings > Apple ID > Subscriptions.",
            language: language
        )
    }

    static func termsOfUseLabel(language: AppLanguage? = nil) -> String {
        L10n.string("Terms of Use (EULA)", defaultValue: "Terms of Use (EULA)", language: language)
    }
}
