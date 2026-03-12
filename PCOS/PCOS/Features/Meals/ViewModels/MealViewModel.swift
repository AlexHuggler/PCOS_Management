import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class MealViewModel {
    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore
    private let suggestionProvider: SuggestionProvider

    // MARK: - Form State

    var mealType: MealType = .lunch
    var mealDescription: String = ""
    var glycemicImpact: GlycemicImpact = .medium
    var carbsText: String = ""
    var proteinText: String = ""
    var fatText: String = ""
    var photoData: Data? = nil
    var notes: String = ""
    var mealDate: Date = Date()

    // MARK: - Validation

    var isValid: Bool {
        !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var mealDescriptionSuggestions: [String] {
        suggestionProvider.mealDescriptionSuggestions(
            query: mealDescription,
            mealType: mealType,
            limit: 6
        )
    }

    var mealNoteSuggestions: [String] {
        suggestionProvider.mealNoteSuggestions(query: noteSuggestionQuery, limit: 8)
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
        self.mealType = defaultsStore.lastMealType
        self.glycemicImpact = defaultsStore.lastMealGlycemicImpact
    }

    // MARK: - Persistence

    func saveMeal() throws {
        let trimmedDescription = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else { return }

        // Delete-then-insert upsert: remove any existing meal for the same timestamp
        let targetDate = mealDate
        let targetType = mealType
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.timestamp == targetDate && entry.mealType == targetType
            }
        )

        do {
            let existing = try modelContext.fetch(descriptor)
            for entry in existing {
                modelContext.delete(entry)
            }
        } catch {
            Logger.database.error("Failed to fetch existing meals for upsert: \(error.localizedDescription)")
        }

        let carbs: Double? = if let value = Double(carbsText), value > 0 { value } else { nil }
        let protein: Double? = if let value = Double(proteinText), value > 0 { value } else { nil }
        let fats: Double? = if let value = Double(fatText), value > 0 { value } else { nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let entry = MealEntry(
            timestamp: mealDate,
            mealType: mealType,
            mealDescription: trimmedDescription,
            glycemicImpact: glycemicImpact,
            photoData: photoData,
            carbsGrams: carbs,
            proteinGrams: protein,
            fatGrams: fats,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )

        modelContext.insert(entry)
        try modelContext.save()
        defaultsStore.lastMealType = mealType
        defaultsStore.lastMealGlycemicImpact = glycemicImpact
        suggestionProvider.recordMealDescription(trimmedDescription)
        if !trimmedNotes.isEmpty {
            let noteTokens = QuickNoteComposer.tokens(from: trimmedNotes)
            if noteTokens.count > 1 {
                for token in noteTokens {
                    suggestionProvider.recordMealNote(token)
                }
            } else {
                suggestionProvider.recordMealNote(trimmedNotes)
            }
        }
        Logger.database.info("Saved meal: \(trimmedDescription) (\(self.mealType.displayName))")
        reset()
    }

    // MARK: - Fetching

    func fetchTodaysMeals() -> [MealEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.endOfDay(for: Date()) else { return [] }

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.timestamp >= startOfDay && entry.timestamp < endOfDay
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch today's meals: \(error.localizedDescription)")
            return []
        }
    }

    func fetchRecentMeals(days: Int) -> [MealEntry] {
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: Date())) else {
            return []
        }

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.timestamp >= startDate
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.database.error("Failed to fetch recent meals: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Delete

    func deleteMeal(_ meal: MealEntry) {
        modelContext.delete(meal)
        do {
            try modelContext.save()
            Logger.database.info("Deleted meal: \(meal.mealDescription)")
        } catch {
            Logger.database.error("Failed to delete meal: \(error.localizedDescription)")
        }
    }

    // MARK: - Analytics

    func giDistribution(days: Int) -> [GlycemicImpact: Int] {
        let meals = fetchRecentMeals(days: days)
        var counts: [GlycemicImpact: Int] = [:]
        for impact in GlycemicImpact.allCases {
            counts[impact] = 0
        }
        for meal in meals {
            counts[meal.glycemicImpact, default: 0] += 1
        }
        return counts
    }

    // MARK: - Reset

    func reset() {
        mealType = defaultsStore.lastMealType
        mealDescription = ""
        glycemicImpact = defaultsStore.lastMealGlycemicImpact
        carbsText = ""
        proteinText = ""
        fatText = ""
        photoData = nil
        notes = ""
        mealDate = Date()
    }

    func applyMealDescriptionSuggestion(_ suggestion: String) {
        mealDescription = suggestion
    }

    func isMealNoteSelected(_ suggestion: String) -> Bool {
        QuickNoteComposer.isSelected(suggestion, in: notes)
    }

    func toggleMealNoteSuggestion(_ suggestion: String) {
        notes = QuickNoteComposer.toggled(suggestion, in: notes)
    }

    private var noteSuggestionQuery: String {
        let baseSuggestions = suggestionProvider.mealNoteSuggestions(query: "", limit: 20)

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
