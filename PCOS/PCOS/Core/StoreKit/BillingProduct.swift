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
    /// ISO 4217 code of `price`; nil when the store did not provide one.
    var currencyCode: String? = nil

    /// Per-month equivalent of a yearly plan, e.g. "$3.33 / month", so the annual value is visible.
    /// Nil for non-yearly plans or when the store gave no currency code.
    func monthlyEquivalentPriceText(language: AppLanguage? = nil, base: Bundle = .main, preferredLanguages: [String]? = nil) -> String? {
        guard let subscriptionPeriod,
              subscriptionPeriod.unit == .year,
              subscriptionPeriod.value > 0,
              let currencyCode
        else { return nil }

        let perMonth = price / Decimal(12 * subscriptionPeriod.value)
        let locale = L10n.locale(for: language, preferredLanguages: preferredLanguages)
        let formattedPrice = perMonth.formatted(.currency(code: currencyCode).locale(locale).precision(.fractionLength(2)))
        return L10n.format(
            "%@ / month",
            defaultValue: "%@ / month",
            language: language,
            base: base,
            preferredLanguages: preferredLanguages,
            formattedPrice
        )
    }

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

    var annualizedPrice: Decimal? {
        guard let subscriptionPeriod else { return nil }
        return price * subscriptionPeriod.annualMultiplier
    }
}
