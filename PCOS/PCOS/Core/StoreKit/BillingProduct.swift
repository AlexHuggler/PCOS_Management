import Foundation

enum BillingPeriodUnit: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year

    func displayText(
        for value: Int,
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        let singularKey: String
        let pluralKey: String

        switch self {
        case .day:
            singularKey = "%lld day"
            pluralKey = "%lld days"
        case .week:
            singularKey = "%lld week"
            pluralKey = "%lld weeks"
        case .month:
            singularKey = "%lld month"
            pluralKey = "%lld months"
        case .year:
            singularKey = "%lld year"
            pluralKey = "%lld years"
        }

        let key = value == 1 ? singularKey : pluralKey
        return L10n.format(
            key,
            defaultValue: key,
            language: language,
            base: base,
            preferredLanguages: preferredLanguages,
            Int64(value)
        )
    }
}

struct BillingPeriod: Equatable, Sendable {
    let unit: BillingPeriodUnit
    let value: Int

    var displayText: String {
        displayText()
    }

    func displayText(
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        unit.displayText(
            for: value,
            language: language,
            base: base,
            preferredLanguages: preferredLanguages
        )
    }

    var annualMultiplier: Decimal {
        let periodValue = max(1, value)
        switch unit {
        case .day:
            return Decimal(365) / Decimal(periodValue)
        case .week:
            return Decimal(52) / Decimal(periodValue)
        case .month:
            return Decimal(12) / Decimal(periodValue)
        case .year:
            return Decimal(1) / Decimal(periodValue)
        }
    }
}

struct BillingProduct: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let price: Decimal
    let subscriptionPeriod: BillingPeriod?
    /// Store-formatted monthly equivalent (e.g. "$6.67"), when the store can provide it.
    var localizedPricePerMonth: String? = nil

    var paywallDisplayName: String {
        paywallDisplayName()
    }

    func paywallDisplayName(
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        switch id {
        case SubscriptionManager.monthlyProductID:
            L10n.string(
                "CycleBalance Premium Monthly",
                defaultValue: "CycleBalance Premium Monthly",
                language: language,
                base: base,
                preferredLanguages: preferredLanguages
            )
        case SubscriptionManager.yearlyProductID:
            L10n.string(
                "CycleBalance Premium Yearly",
                defaultValue: "CycleBalance Premium Yearly",
                language: language,
                base: base,
                preferredLanguages: preferredLanguages
            )
        default:
            displayName
        }
    }

    var displayPriceWithPeriod: String {
        displayPriceWithPeriod()
    }

    func displayPriceWithPeriod(
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        guard let subscriptionPeriod else { return displayPrice }
        return L10n.format(
            "%@ / %@",
            defaultValue: "%@ / %@",
            language: language,
            base: base,
            preferredLanguages: preferredLanguages,
            displayPrice,
            subscriptionPeriod.displayText(
                language: language,
                base: base,
                preferredLanguages: preferredLanguages
            )
        )
    }

    /// "$9.99/month" style text for single-unit periods (paywall CTA and renewal line);
    /// multi-unit periods keep "$X / 3 months".
    func displayPricePerPeriod(
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        guard let subscriptionPeriod else { return displayPrice }
        guard subscriptionPeriod.value == 1 else {
            return displayPriceWithPeriod(language: language, base: base, preferredLanguages: preferredLanguages)
        }
        let key: String
        switch subscriptionPeriod.unit {
        case .day: key = "%@/day"
        case .week: key = "%@/week"
        case .month: key = "%@/month"
        case .year: key = "%@/year"
        }
        return L10n.format(
            key,
            defaultValue: key,
            language: language,
            base: base,
            preferredLanguages: preferredLanguages,
            displayPrice
        )
    }

    /// Short plan name for plan cards ("Yearly", "Monthly").
    func planTitle(
        language: AppLanguage? = nil,
        base: Bundle = .main,
        preferredLanguages: [String]? = nil
    ) -> String {
        let key: String
        switch subscriptionPeriod?.unit {
        case .year?: key = "Yearly"
        case .month?: key = "Monthly"
        case .week?: key = "Weekly"
        default: return paywallDisplayName(language: language, base: base, preferredLanguages: preferredLanguages)
        }
        return L10n.string(key, defaultValue: key, language: language, base: base, preferredLanguages: preferredLanguages)
    }

    /// Value used for analytics `plan` properties. Product identifiers only, never user data.
    var analyticsPlanName: String {
        switch subscriptionPeriod?.unit {
        case .year?: "yearly"
        case .month?: "monthly"
        case .week?: "weekly"
        case .day?: "daily"
        case nil: id
        }
    }

    var annualizedPrice: Decimal? {
        guard let subscriptionPeriod else { return nil }
        return price * subscriptionPeriod.annualMultiplier
    }
}
