import Foundation
import SwiftData

/// A missing edit preserves storage; clearing and setting are deliberate edits.
enum CheckInChange<Value: Equatable>: Equatable {
    case untouched
    case clear
    case set(Value)

    var value: Value? {
        if case let .set(value) = self { return value }
        return nil
    }

    func applying(to current: Value?) -> Value? {
        switch self {
        case .untouched: current
        case .clear: nil
        case let .set(value): value
        }
    }

    static func loaded(_ value: Value?) -> Self {
        value.map(Self.set) ?? .untouched
    }
}

enum DailyMood: String, CaseIterable, Identifiable {
    case great, good, okay, low, awful
    var id: String { rawValue }
    var title: String {
        switch self {
        case .great: L10n.string("Great", defaultValue: "Great")
        case .good: L10n.string("Good", defaultValue: "Good")
        case .okay: L10n.string("Okay", defaultValue: "Okay")
        case .low: L10n.string("Low", defaultValue: "Low")
        case .awful: L10n.string("Awful", defaultValue: "Awful")
        }
    }
}

struct DailyCheckInDraft: Equatable {
    var date: Date
    var mood: CheckInChange<DailyMood> = .untouched
    var energy: CheckInChange<Int> = .untouched
    var pain: CheckInChange<Int> = .untouched
    var stress: CheckInChange<Int> = .untouched
    var water: CheckInChange<Int> = .untouched
    var note: CheckInChange<String> = .untouched
    var symptoms: CheckInChange<[SymptomType: Int]> = .untouched
    var symptomNotes: [SymptomType: String] = [:]
    private var loadedSymptomDate: Date?
    private var loadedSymptoms: [SymptomType: Int]?
    private var loadedSymptomNotes: [SymptomType: String] = [:]

    init(date: Date) { self.date = date }

    /// Nil means an explicit replacement; loaded drafts only edit types changed since loading.
    var editedSymptomTypes: Set<SymptomType>? {
        guard symptoms != .clear, loadedSymptomDate == date, let loadedSymptoms else { return nil }
        let selected = symptoms.value ?? [:]
        let types = Set(loadedSymptoms.keys).union(selected.keys)
            .union(loadedSymptomNotes.keys).union(symptomNotes.keys)
        return Set(types.filter { selected[$0] != loadedSymptoms[$0] || symptomNotes[$0] != loadedSymptomNotes[$0] })
    }

    mutating func rememberLoadedSymptoms() {
        loadedSymptomDate = date
        loadedSymptoms = symptoms.value ?? [:]
        loadedSymptomNotes = symptomNotes
    }

    mutating func recordNoSymptoms() {
        symptoms = .clear
        symptomNotes = [:]
        symptomsReviewed = true
    }
    var symptomsReviewChange: CheckInChange<Bool> = .untouched
    var symptomsReviewed: Bool {
        get { symptomsReviewChange.value ?? false }
        set { symptomsReviewChange = .set(newValue) }
    }

    /// Loading describes stored values; submitting only differences preserves unrelated source rows.
    func changes(since original: Self) -> Self {
        guard date == original.date else { return self }
        var change = self
        change.loadedSymptomDate = original.date
        change.loadedSymptoms = original.symptoms.value ?? [:]
        change.loadedSymptomNotes = original.symptomNotes
        if mood == original.mood { change.mood = .untouched }
        if energy == original.energy { change.energy = .untouched }
        if pain == original.pain { change.pain = .untouched }
        if stress == original.stress { change.stress = .untouched }
        if water == original.water { change.water = .untouched }
        if note == original.note { change.note = .untouched }
        if symptoms == original.symptoms && symptomNotes == original.symptomNotes { change.symptoms = .untouched }
        if symptomsReviewChange == original.symptomsReviewChange { change.symptomsReviewChange = .untouched }
        return change
    }

}

@MainActor
struct DailyCheckInService {
    enum ValidationError: Error { case invalidEnergy, invalidPain, invalidStress, invalidWater, invalidSeverity }
    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) { self.modelContext = modelContext }

    func load(on date: Date) throws -> DailyCheckInDraft {
        var draft = DailyCheckInDraft(date: date)
        if let log = try DailyLogService(modelContext: modelContext).fetchLog(on: date) {
            draft.mood = .loaded(log.moodRawValue.flatMap(DailyMood.init(rawValue:)))
            draft.energy = .loaded(log.energyLevel)
            draft.pain = .loaded(log.painLevel0To10)
            draft.stress = .loaded(log.stressLevel)
            draft.water = .loaded(log.waterOz)
            draft.note = .loaded(log.privateNote)
            draft.symptomsReviewed = log.symptomsReviewed
        }
        let entries = try symptoms(on: date)
        var severities: [SymptomType: Int] = [:]
        for entry in entries {
            severities[entry.symptomType] = max(severities[entry.symptomType] ?? 0, entry.severity)
            if let note = entry.notes { draft.symptomNotes[entry.symptomType] = note }
        }
        if !entries.isEmpty || draft.symptomsReviewed { draft.symptoms = .set(severities) }
        draft.rememberLoadedSymptoms()
        return draft
    }

    func save(_ draft: DailyCheckInDraft) throws {
        if let value = draft.energy.value, !(1...5).contains(value) { throw ValidationError.invalidEnergy }
        if let value = draft.pain.value, !(0...10).contains(value) { throw ValidationError.invalidPain }
        if let value = draft.stress.value, !(1...5).contains(value) { throw ValidationError.invalidStress }
        if let value = draft.water.value, value < 0 { throw ValidationError.invalidWater }
        if let values = draft.symptoms.value, values.values.contains(where: { !(1...5).contains($0) }) {
            throw ValidationError.invalidSeverity
        }
        // Fetch before mutation so read failures cannot leave a half-applied edit.
        let existingLog = try DailyLogService(modelContext: modelContext).fetchLog(on: draft.date)
        let existingSymptoms = try symptoms(on: draft.date)
        do {
            try modelContext.transaction {
                let log = existingLog ?? DailyLog(date: calendar.startOfDay(for: draft.date))
                if existingLog == nil { modelContext.insert(log) }
                switch draft.mood {
                case .untouched: break
                case .clear: log.moodRawValue = nil
                case let .set(mood): log.moodRawValue = mood.rawValue
                }
                log.energyLevel = draft.energy.applying(to: log.energyLevel)
                log.painLevel0To10 = draft.pain.applying(to: log.painLevel0To10)
                log.stressLevel = draft.stress.applying(to: log.stressLevel)
                log.waterOz = draft.water.applying(to: log.waterOz)
                if draft.note != .untouched {
                    let trimmed = draft.note.value?.trimmingCharacters(in: .whitespacesAndNewlines)
                    log.privateNote = trimmed?.isEmpty == true ? nil : trimmed
                }
                log.symptomsReviewed = draft.symptomsReviewChange.applying(to: log.symptomsReviewed) ?? false
                if draft.symptoms != .untouched {
                    let editedTypes = draft.editedSymptomTypes
                    var remaining = (draft.symptoms.value ?? [:]).filter { editedTypes?.contains($0.key) ?? true }
                    for entry in existingSymptoms where editedTypes?.contains(entry.symptomType) ?? true {
                        if let severity = remaining.removeValue(forKey: entry.symptomType) {
                            entry.severity = severity
                            entry.notes = draft.symptomNotes[entry.symptomType]
                        } else { modelContext.delete(entry) }
                    }
                    for (type, severity) in remaining {
                        modelContext.insert(SymptomEntry(date: draft.date, type: type, severity: severity, notes: draft.symptomNotes[type]))
                    }
                }
                try modelContext.save()
            }
        } catch {
            modelContext.rollback()
            throw error
        }
        InsightRefreshCoordinator.invalidate()
    }

    private func symptoms(on date: Date) throws -> [SymptomEntry] {
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try modelContext.fetch(FetchDescriptor<SymptomEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))
    }
}
