import Foundation

/// Unit of a supplement dose. Stored by raw value on `SupplementLog`; milligrams is the historical default.
enum DosageUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case milligram = "mg"
    case microgram = "mcg"
    case internationalUnit = "IU"
    case gram = "g"
    case cup = "cup"

    var id: String { rawValue }

    /// Short label shown after a dose value.
    var symbol: String {
        switch self {
        case .cup:
            L10n.string("cup(s)", defaultValue: "cup(s)")
        default:
            rawValue
        }
    }

    /// Sanity ceiling for catalog presets, per unit.
    var plausibleMaximumDose: Double {
        switch self {
        case .milligram: 5000
        case .microgram: 1000
        case .internationalUnit: 5000
        case .gram: 20
        case .cup: 6
        }
    }

    /// Formats a dose with its unit symbol using the app locale, e.g. "2,000 IU".
    static func formatted(_ value: Double, unit: DosageUnit) -> String {
        let number = value.rounded(.towardZero) == value
            ? L10n.decimal(value, fractionDigits: 0)
            : L10n.decimal(value, fractionDigits: 1)
        return "\(number) \(unit.symbol)"
    }
}
