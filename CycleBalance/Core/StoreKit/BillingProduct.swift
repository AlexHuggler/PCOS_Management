import Foundation

enum BillingPeriodUnit: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year

    func displayText(for value: Int) -> String {
        switch self {
        case .day:
            value == 1 ? "day" : "\(value) days"
        case .week:
            value == 1 ? "week" : "\(value) weeks"
        case .month:
            value == 1 ? "month" : "\(value) months"
        case .year:
            value == 1 ? "year" : "\(value) years"
        }
    }
}

struct BillingPeriod: Equatable, Sendable {
    let unit: BillingPeriodUnit
    let value: Int

    var displayText: String {
        unit.displayText(for: value)
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

    var displayPriceWithPeriod: String {
        guard let subscriptionPeriod else { return displayPrice }
        return "\(displayPrice) / \(subscriptionPeriod.displayText)"
    }

    var annualizedPrice: Decimal? {
        guard let subscriptionPeriod else { return nil }
        return price * subscriptionPeriod.annualMultiplier
    }
}
