import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class BloodSugarViewModel {
    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore
    private let suggestionProvider: SuggestionProvider

    // MARK: - Form State

    var glucoseValueText: String = ""
    var readingType: GlucoseReadingType = .random
    var mealContext: String = ""
    var notes: String = ""
    var readingDate: Date = Date()

    // MARK: - Computed

    var isValidGlucose: Bool {
        guard let value = Double(glucoseValueText) else { return false }
        return (40...600).contains(value)
    }

    /// Whether the form has any user-entered data worth preserving.
    var hasUnsavedChanges: Bool {
        !glucoseValueText.isEmpty || !mealContext.isEmpty || !notes.isEmpty
    }

    var mealContextSuggestions: [String] {
        suggestionProvider.bloodSugarMealContextSuggestions(query: mealContext, limit: 8)
    }

    var noteSuggestions: [String] {
        suggestionProvider.bloodSugarNoteSuggestions(query: noteSuggestionQuery, limit: 8)
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        defaultsStore: UserEntryDefaultsStore = .shared,
        suggestionProvider: SuggestionProvider? = nil
    ) {
        self.modelContext = modelContext
        self.defaultsStore = defaultsStore
        self.suggestionProvider = suggestionProvider ?? SuggestionProvider(defaultsStore: defaultsStore)
        self.readingType = defaultsStore.lastBloodSugarReadingType
        self.mealContext = defaultsStore.lastBloodSugarMealContext ?? ""
    }

    // MARK: - Actions

    /// Validate form state, create a `BloodSugarReading`, insert, and save.
    func saveReading() throws {
        guard let glucoseValue = Double(glucoseValueText),
              (40...600).contains(glucoseValue) else {
            throw BloodSugarError.invalidGlucose
        }

        let trimmedMealContext = mealContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let reading = BloodSugarReading(
            timestamp: readingDate,
            glucoseValue: glucoseValue,
            readingType: readingType,
            mealContext: trimmedMealContext.isEmpty ? nil : trimmedMealContext,
            fromHealthKit: false,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        modelContext.insert(reading)
        try modelContext.save()

        defaultsStore.lastBloodSugarReadingType = readingType
        defaultsStore.lastBloodSugarMealContext = trimmedMealContext
        if !trimmedMealContext.isEmpty {
            suggestionProvider.recordBloodSugarMealContext(trimmedMealContext)
        }
        if !trimmedNotes.isEmpty {
            let noteTokens = QuickNoteComposer.tokens(from: trimmedNotes)
            if noteTokens.count > 1 {
                for token in noteTokens {
                    suggestionProvider.recordBloodSugarNote(token)
                }
            } else {
                suggestionProvider.recordBloodSugarNote(trimmedNotes)
            }
        }

        reset()
    }

    /// Fetch all readings logged today.
    func fetchTodaysReadings() -> [BloodSugarReading] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.endOfDay(for: Date()) else { return [] }

        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.timestamp >= startOfDay && reading.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch today's blood sugar readings: \(error.localizedDescription)")
            return []
        }
    }

    /// Fetch readings from the last N days.
    func fetchRecentReadings(days: Int) -> [BloodSugarReading] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return []
        }

        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.timestamp >= startDate
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch recent blood sugar readings: \(error.localizedDescription)")
            return []
        }
    }

    /// Delete a single reading.
    func deleteReading(_ reading: BloodSugarReading) {
        modelContext.delete(reading)
        do {
            try modelContext.save()
        } catch {
            Logger.database.error("Failed to delete blood sugar reading: \(error.localizedDescription)")
        }
    }

    /// Average glucose for an optional reading type over the last N days.
    /// Returns `nil` when there are no matching readings.
    func averageGlucose(for type: GlucoseReadingType?, days: Int) -> Double? {
        let readings = fetchRecentReadings(days: days)
        let filtered: [BloodSugarReading]
        if let type {
            filtered = readings.filter { $0.readingType == type }
        } else {
            filtered = readings
        }
        guard !filtered.isEmpty else { return nil }
        let sum = filtered.reduce(0.0) { $0 + $1.glucoseValue }
        return sum / Double(filtered.count)
    }

    /// Reset form to defaults.
    func reset() {
        glucoseValueText = ""
        readingType = defaultsStore.lastBloodSugarReadingType
        mealContext = defaultsStore.lastBloodSugarMealContext ?? ""
        notes = ""
        readingDate = Date()
    }

    func applyMealContextSuggestion(_ suggestion: String) {
        mealContext = suggestion
    }

    func isNoteSuggestionSelected(_ suggestion: String) -> Bool {
        QuickNoteComposer.isSelected(suggestion, in: notes)
    }

    func toggleNoteSuggestion(_ suggestion: String) {
        notes = QuickNoteComposer.toggled(suggestion, in: notes)
    }

    private var noteSuggestionQuery: String {
        let baseSuggestions = suggestionProvider.bloodSugarNoteSuggestions(query: "", limit: 20)

        let segments = notes.split(separator: ",", omittingEmptySubsequences: false)
        guard let lastSegment = segments.last else {
            return notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let candidate = String(lastSegment).trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.contains(",") {
            return candidate
        }

        if baseSuggestions.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            return ""
        }
        return candidate
    }
}

// MARK: - Errors

enum BloodSugarError: LocalizedError {
    case invalidGlucose

    var errorDescription: String? {
        switch self {
        case .invalidGlucose:
            return "Glucose value must be between 40 and 600 mg/dL."
        }
    }
}
