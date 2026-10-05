import Foundation
import Observation

enum InformationDetail: String, Codable, CaseIterable, Identifiable, Sendable {
    case simple, detailed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .simple: L10n.string("Simple", defaultValue: "Simple")
        case .detailed: L10n.string("Detailed", defaultValue: "Detailed")
        }
    }
}

enum TodayCard: String, Codable, CaseIterable, Identifiable, Sendable {
    case cycle, health, observation, symptoms, meals, supplements, glucose, actions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .cycle: L10n.string("Cycle context", defaultValue: "Cycle context")
        case .health: L10n.string("Apple Health", defaultValue: "Apple Health")
        case .observation: L10n.string("Your observations", defaultValue: "Your observations")
        case .symptoms: L10n.string("Symptoms", defaultValue: "Symptoms")
        case .meals: L10n.string("Meals", defaultValue: "Meals")
        case .supplements: L10n.string("Supplements", defaultValue: "Supplements")
        case .glucose: L10n.string("Blood Sugar", defaultValue: "Blood Sugar")
        case .actions: L10n.string("Positive actions", defaultValue: "Positive actions")
        }
    }
}

enum BodyMeasurementStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case us, metric
    var id: String { rawValue }
    var title: String { self == .us ? "lb / oz" : "kg / mL" }
    func weight(fromPounds value: Double) -> Double { self == .metric ? value * 0.45359237 : value }
    func water(fromOunces value: Int) -> Int { self == .metric ? Int((Double(value) * 29.5735295625).rounded()) : value }
    func ounces(fromWater value: Int) -> Int { self == .metric ? Int((Double(value) / 29.5735295625).rounded()) : value }
}

struct TrackingSelection: Codable, Equatable, Sendable {
    var favoriteActions: [LoggerShortcut] = [.symptoms, .period, .meal]
    var visibleCards: [TodayCard] = [.cycle, .health, .observation, .symptoms]
    var pinnedSymptomRawValues: [String] = []
    var informationDetail: InformationDetail = .simple
    var bodyMeasurementStyleRaw: String?
    var showWeight = false
    var showNutritionNumbers = false
    var showFertility = false
}

@Observable
final class TrackingPreferences {
    nonisolated(unsafe) static let shared = TrackingPreferences()
    private let defaults: UserDefaults
    private let key = "tracking.preferences.v1"
    private var selection: TrackingSelection { didSet { persist() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(TrackingSelection.self, from: data) {
            selection = saved
        } else { selection = TrackingSelection() }
    }

    var favoriteActions: [LoggerShortcut] {
        get { selection.favoriteActions }
        set { selection.favoriteActions = Array(newValue.uniqued().prefix(3)) }
    }
    var visibleCards: [TodayCard] {
        get { selection.visibleCards }
        set { selection.visibleCards = newValue.uniqued() }
    }
    var pinnedSymptomRawValues: [String] {
        get { selection.pinnedSymptomRawValues }
        set { selection.pinnedSymptomRawValues = newValue.uniqued() }
    }
    var informationDetail: InformationDetail {
        get { selection.informationDetail }
        set { selection.informationDetail = newValue }
    }
    var bodyMeasurementStyle: BodyMeasurementStyle {
        get { BodyMeasurementStyle(rawValue: selection.bodyMeasurementStyleRaw ?? "us") ?? .us }
        set { selection.bodyMeasurementStyleRaw = newValue.rawValue }
    }
    var showWeight: Bool {
        get { selection.showWeight }
        set { selection.showWeight = newValue }
    }
    var showNutritionNumbers: Bool {
        get { selection.showNutritionNumbers }
        set { selection.showNutritionNumbers = newValue }
    }
    var showFertility: Bool {
        get { selection.showFertility }
        set { selection.showFertility = newValue }
    }
    func backupData() throws -> Data { try JSONEncoder().encode(selection) }
    func restore(from data: Data) throws {
        let restored = try JSONDecoder().decode(TrackingSelection.self, from: data)
        selection = restored
        favoriteActions = restored.favoriteActions
        visibleCards = restored.visibleCards
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: key) }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

extension LoggerShortcut {
    func isVisible(in lifecycleMode: LifecycleMode, showFertility: Bool) -> Bool {
        if lifecycleMode == .pregnant && (self == .period || self == .ovulation) { return false }
        return self != .ovulation || showFertility
    }

    var requiresPremium: Bool {
        switch self {
        case .period, .ovulation, .symptoms: false
        case .meal, .bloodSugar, .supplements, .photo: true
        }
    }
}
