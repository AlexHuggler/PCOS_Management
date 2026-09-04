import Foundation

/// Locale-aware weight presentation. Weight is stored in kilograms everywhere (HealthKit imports,
/// backups, CSV); only display and entry convert to pounds for locales that use them.
enum WeightDisplay {
    private static let poundsPerKilogram = 2.20462262185

    static func usesPounds(locale: Locale) -> Bool {
        locale.measurementSystem == .us
    }

    static func unitSymbol(locale: Locale) -> String {
        usesPounds(locale: locale) ? "lb" : "kg"
    }

    static func formatted(kilograms: Double, locale: Locale) -> String {
        let unit: UnitMass = usesPounds(locale: locale) ? .pounds : .kilograms
        let measurement = Measurement(value: kilograms, unit: UnitMass.kilograms).converted(to: unit)
        return measurement.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
            .locale(locale)
        )
    }

    /// Value shown in an entry field for the locale's unit.
    static func displayValue(kilograms: Double, locale: Locale) -> Double {
        usesPounds(locale: locale) ? kilograms * poundsPerKilogram : kilograms
    }

    /// Converts a value typed in the locale's unit back to kilograms for storage.
    static func kilograms(fromDisplayValue value: Double, locale: Locale) -> Double {
        usesPounds(locale: locale) ? value / poundsPerKilogram : value
    }
}
