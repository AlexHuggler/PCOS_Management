import Foundation

enum LoggerShortcut: String, Codable, CaseIterable, Identifiable, Sendable {
    case period
    case ovulation
    case symptoms
    case bloodSugar
    case supplements
    case meal
    case photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .period:
            L10n.string("Log Period", defaultValue: "Log Period")
        case .ovulation:
            L10n.string("Log Ovulation Clues", defaultValue: "Log Ovulation Clues")
        case .symptoms:
            L10n.string("Log Symptoms", defaultValue: "Log Symptoms")
        case .bloodSugar:
            L10n.string("Log Blood Sugar", defaultValue: "Log Blood Sugar")
        case .supplements:
            L10n.string("Log Supplements", defaultValue: "Log Supplements")
        case .meal:
            L10n.string("Log Meal", defaultValue: "Log Meal")
        case .photo:
            L10n.string("Photo Journal", defaultValue: "Photo Journal")
        }
    }

    var systemImage: String {
        switch self {
        case .period: "drop.fill"
        case .ovulation: "scope"
        case .symptoms: "list.bullet.clipboard"
        case .bloodSugar: "drop.triangle.fill"
        case .supplements: "pills.fill"
        case .meal: "fork.knife"
        case .photo: "camera.fill"
        }
    }
}

final class UserEntryDefaultsStore: @unchecked Sendable {
    static let shared = UserEntryDefaultsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastBloodSugarReadingType: GlucoseReadingType {
        get {
            guard let raw = defaults.string(forKey: Keys.lastBloodSugarReadingType),
                  let readingType = GlucoseReadingType(rawValue: raw)
            else {
                return .random
            }
            return readingType
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.lastBloodSugarReadingType) }
    }

    var lastBloodSugarMealContext: String? {
        get { defaults.string(forKey: Keys.lastBloodSugarMealContext) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Keys.lastBloodSugarMealContext)
            } else {
                defaults.removeObject(forKey: Keys.lastBloodSugarMealContext)
            }
        }
    }

    var lastMealType: MealType {
        get {
            guard let raw = defaults.string(forKey: Keys.lastMealType),
                  let type = MealType(rawValue: raw)
            else {
                return .lunch
            }
            return type
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.lastMealType) }
    }

    var lastMealGlycemicImpact: GlycemicImpact {
        get {
            guard let raw = defaults.string(forKey: Keys.lastMealGlycemicImpact),
                  let impact = GlycemicImpact(rawValue: raw)
            else {
                return .medium
            }
            return impact
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.lastMealGlycemicImpact) }
    }

    var lastSupplementName: String? {
        get { defaults.string(forKey: Keys.lastSupplementName) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Keys.lastSupplementName)
            } else {
                defaults.removeObject(forKey: Keys.lastSupplementName)
            }
        }
    }

    var lastSupplementBrand: String? {
        get { defaults.string(forKey: Keys.lastSupplementBrand) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults.set(trimmed, forKey: Keys.lastSupplementBrand)
            } else {
                defaults.removeObject(forKey: Keys.lastSupplementBrand)
            }
        }
    }

    var lastSupplementTime: Date {
        get {
            let hour = defaults.object(forKey: Keys.lastSupplementHour) as? Int
            let minute = defaults.object(forKey: Keys.lastSupplementMinute) as? Int

            guard let hour, let minute else {
                return Date()
            }

            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour
            components.minute = minute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            defaults.set(components.hour, forKey: Keys.lastSupplementHour)
            defaults.set(components.minute, forKey: Keys.lastSupplementMinute)
        }
    }

    var hasLastSupplementTime: Bool {
        defaults.object(forKey: Keys.lastSupplementHour) != nil
            && defaults.object(forKey: Keys.lastSupplementMinute) != nil
    }

    var lastPhotoType: HairPhotoType {
        get {
            guard let raw = defaults.string(forKey: Keys.lastPhotoType),
                  let type = HairPhotoType(rawValue: raw)
            else {
                return .scalpPart
            }
            return type
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.lastPhotoType) }
    }

    var lastLoggerShortcut: LoggerShortcut? {
        get {
            guard let raw = defaults.string(forKey: Keys.lastLoggerShortcut) else { return nil }
            return LoggerShortcut(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Keys.lastLoggerShortcut)
            } else {
                defaults.removeObject(forKey: Keys.lastLoggerShortcut)
            }
        }
    }

    func recordRecentBloodSugarMealContext(_ value: String) {
        recordRecent(value, key: Keys.recentBloodSugarContexts)
    }

    func recentBloodSugarMealContexts(limit: Int = 4) -> [String] {
        recentValues(for: Keys.recentBloodSugarContexts, limit: limit)
    }

    func recordRecentBloodSugarNote(_ value: String) {
        recordRecent(value, key: Keys.recentBloodSugarNotes)
    }

    func recentBloodSugarNotes(limit: Int = 6) -> [String] {
        recentValues(for: Keys.recentBloodSugarNotes, limit: limit)
    }

    func recordRecentMealDescription(_ value: String) {
        recordRecent(value, key: Keys.recentMealDescriptions)
    }

    func recentMealDescriptions(limit: Int = 4) -> [String] {
        recentValues(for: Keys.recentMealDescriptions, limit: limit)
    }

    func recordRecentMealDescription(_ value: String, mealType: MealType) {
        recordRecent(value, key: mealDescriptionKey(for: mealType))
    }

    func recentMealDescriptions(mealType: MealType, limit: Int = 4) -> [String] {
        scopedRecentValues(
            primaryKey: mealDescriptionKey(for: mealType),
            fallbackKey: Keys.recentMealDescriptions,
            limit: limit
        )
    }

    func recordRecentMealNote(_ value: String) {
        recordRecent(value, key: Keys.recentMealNotes)
    }

    func recentMealNotes(limit: Int = 6) -> [String] {
        recentValues(for: Keys.recentMealNotes, limit: limit)
    }

    func recordRecentMealNote(_ value: String, mealType: MealType) {
        recordRecent(value, key: mealNoteKey(for: mealType))
    }

    func recentMealNotes(mealType: MealType, limit: Int = 6) -> [String] {
        scopedRecentValues(
            primaryKey: mealNoteKey(for: mealType),
            fallbackKey: Keys.recentMealNotes,
            limit: limit
        )
    }

    func recordRecentPhotoNote(_ value: String, photoType: HairPhotoType) {
        recordRecent(value, key: photoNoteKey(for: photoType))
    }

    func recentPhotoNotes(photoType: HairPhotoType, limit: Int = 6) -> [String] {
        recentValues(for: photoNoteKey(for: photoType), limit: limit)
    }

    func recordRecentPeriodNote(_ value: String, flowIntensity: FlowIntensity) {
        guard let key = periodNotesKey(for: flowIntensity) else { return }
        recordRecent(value, key: key)
    }

    func recentPeriodNotes(flowIntensity: FlowIntensity, limit: Int = 6) -> [String] {
        guard let key = periodNotesKey(for: flowIntensity) else { return [] }
        return recentValues(for: key, limit: limit)
    }

    func recordRecentSupplementName(_ value: String) {
        recordRecent(value, key: Keys.recentSupplementNames)
    }

    func recentSupplementNames(limit: Int = 6) -> [String] {
        recentValues(for: Keys.recentSupplementNames, limit: limit)
    }

    func recordRecentSupplementBrand(_ value: String) {
        recordRecent(value, key: Keys.recentSupplementBrands)
    }

    func recentSupplementBrands(limit: Int = 4) -> [String] {
        recentValues(for: Keys.recentSupplementBrands, limit: limit)
    }

    private func recordRecent(_ value: String, key: String, maxCount: Int = 8) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var values = defaults.stringArray(forKey: key) ?? []
        values.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        values.insert(trimmed, at: 0)
        if values.count > maxCount {
            values = Array(values.prefix(maxCount))
        }

        defaults.set(values, forKey: key)
    }

    private func recentValues(for key: String, limit: Int) -> [String] {
        let values = defaults.stringArray(forKey: key) ?? []
        return Array(values.prefix(limit))
    }

    private func scopedRecentValues(primaryKey: String, fallbackKey: String, limit: Int) -> [String] {
        let primaryValues = defaults.stringArray(forKey: primaryKey) ?? []
        let fallbackValues = defaults.stringArray(forKey: fallbackKey) ?? []

        var seen = Set<String>()
        var output: [String] = []

        for value in primaryValues + fallbackValues {
            let normalizedValue = normalized(value)
            guard !normalizedValue.isEmpty else { continue }
            guard seen.insert(normalizedValue).inserted else { continue }
            output.append(value.trimmingCharacters(in: .whitespacesAndNewlines))
            if output.count >= limit { break }
        }

        return output
    }

    private func periodNotesKey(for flowIntensity: FlowIntensity) -> String? {
        switch flowIntensity {
        case .spotting, .light, .medium, .heavy:
            return "\(Keys.recentPeriodNotesPrefix)\(flowIntensity.rawValue)"
        case .none:
            return nil
        }
    }

    private func mealDescriptionKey(for mealType: MealType) -> String {
        "\(Keys.recentMealDescriptionsPrefix)\(mealType.rawValue)"
    }

    private func mealNoteKey(for mealType: MealType) -> String {
        "\(Keys.recentMealNotesPrefix)\(mealType.rawValue)"
    }

    private func photoNoteKey(for photoType: HairPhotoType) -> String {
        "\(Keys.recentPhotoNotesPrefix)\(photoType.rawValue)"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private enum Keys {
        static let lastBloodSugarReadingType = "entryDefaults.lastBloodSugarReadingType"
        static let lastBloodSugarMealContext = "entryDefaults.lastBloodSugarMealContext"
        static let lastMealType = "entryDefaults.lastMealType"
        static let lastMealGlycemicImpact = "entryDefaults.lastMealGlycemicImpact"
        static let lastSupplementName = "entryDefaults.lastSupplementName"
        static let lastSupplementBrand = "entryDefaults.lastSupplementBrand"
        static let lastSupplementHour = "entryDefaults.lastSupplementHour"
        static let lastSupplementMinute = "entryDefaults.lastSupplementMinute"
        static let lastPhotoType = "entryDefaults.lastPhotoType"
        static let lastLoggerShortcut = "entryDefaults.lastLoggerShortcut"

        static let recentBloodSugarContexts = "entryDefaults.recentBloodSugarContexts"
        static let recentBloodSugarNotes = "entryDefaults.recentBloodSugarNotes"
        static let recentMealDescriptions = "entryDefaults.recentMealDescriptions"
        static let recentMealDescriptionsPrefix = "entryDefaults.recentMealDescriptions."
        static let recentMealNotes = "entryDefaults.recentMealNotes"
        static let recentMealNotesPrefix = "entryDefaults.recentMealNotes."
        static let recentPhotoNotesPrefix = "entryDefaults.recentPhotoNotes."
        static let recentPeriodNotesPrefix = "entryDefaults.recentPeriodNotes."
        static let recentSupplementNames = "entryDefaults.recentSupplementNames"
        static let recentSupplementBrands = "entryDefaults.recentSupplementBrands"
    }
}
