import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class MealViewModel {
    typealias ExistingMealsResolver = @MainActor (_ modelContext: ModelContext, _ targetDate: Date, _ targetType: MealType) throws -> [MealEntry]

    private let modelContext: ModelContext
    private let defaultsStore: UserEntryDefaultsStore
    private let suggestionProvider: SuggestionProvider
    private let mealPlanningService: MealPlanningProviding
    private let existingMealsResolver: ExistingMealsResolver

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
    var selectedTemplateID: String?
    var postMealSymptomSeverity: Int = 0
    var postMealSymptomNote: String = ""
    var pendingNutritionImportSummary: NutritionImportDraftSummary?
    var nutritionImportID: UUID?
    var barcode: String?
    var sourceLabel: String?
    var calories: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var servingText: String?

    private var pendingNutritionCandidate: FoodProductCandidate?
    private var pendingNutritionImportedAt: Date?

    // MARK: - Validation

    var isValid: Bool {
        !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasMealDescriptionQuery: Bool {
        !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var mealDescriptionSuggestions: [String] {
        suggestionProvider.mealDescriptionSuggestions(
            query: mealDescription,
            mealType: mealType,
            limit: hasMealDescriptionQuery ? 6 : 10
        )
    }

    var mealNoteSuggestions: [String] {
        let baseSuggestions = suggestionProvider.mealNoteSuggestions(
            query: "",
            mealType: mealType,
            limit: 20
        )
        let filteredSuggestions = suggestionProvider.mealNoteSuggestions(
            query: QuickNoteComposer.suggestionQuery(in: notes, availableSuggestions: baseSuggestions),
            mealType: mealType,
            limit: 10
        )

        return QuickNoteComposer.visibleSuggestions(
            from: filteredSuggestions,
            selectedIn: notes,
            availableSuggestions: baseSuggestions
        )
    }

    var mealTemplates: [MealTemplate] {
        mealPlanningService.templates(for: mealType)
    }

    var swapSuggestions: [String] {
        mealPlanningService.swapSuggestions(for: mealDescription, glycemicImpact: glycemicImpact)
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        defaultsStore: UserEntryDefaultsStore = .shared,
        suggestionProvider: SuggestionProvider? = nil,
        mealPlanningService: MealPlanningProviding = MealPlanningService(),
        existingMealsResolver: ExistingMealsResolver? = nil
    ) {
        self.modelContext = modelContext
        self.defaultsStore = defaultsStore
        self.suggestionProvider = suggestionProvider ?? SuggestionProvider(defaultsStore: defaultsStore)
        self.mealPlanningService = mealPlanningService
        self.existingMealsResolver = existingMealsResolver ?? Self.resolveExistingMealsForUpsert
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

        do {
            let existing = try existingMealsResolver(modelContext, targetDate, targetType)
            for entry in existing {
                modelContext.delete(entry)
            }
        } catch {
            let startupMode = UserDefaults.standard.string(forKey: Self.persistenceStartupModeKey) ?? "unknown"
            Logger.meals.error(
                "Meal upsert dedupe fetch failed. mealType=\(targetType.rawValue, privacy: .public) targetDate=\(targetDate.ISO8601Format(), privacy: .public) startupMode=\(startupMode, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        let carbs: Double? = if let value = Double(carbsText), value > 0 { value } else { nil }
        let protein: Double? = if let value = Double(proteinText), value > 0 { value } else { nil }
        let fats: Double? = if let value = Double(fatText), value > 0 { value } else { nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPostMealSymptomNote = postMealSymptomNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let postMealSeverity: Int? = if postMealSymptomSeverity > 0 {
            min(max(postMealSymptomSeverity, 1), 5)
        } else {
            nil
        }
        let feedbackTimestamp: Date? = if postMealSeverity != nil || !trimmedPostMealSymptomNote.isEmpty {
            Date()
        } else {
            nil
        }
        let reviewedNutritionImport: NutritionImportRecord?
        if let pendingNutritionCandidate {
            let nutritionImport = pendingNutritionCandidate.makeNutritionImportRecord(
                importedAt: pendingNutritionImportedAt ?? mealDate,
                reviewStatus: .reviewed
            )
            modelContext.insert(nutritionImport)
            reviewedNutritionImport = nutritionImport
        } else {
            reviewedNutritionImport = nil
        }

        let entry = MealEntry(
            timestamp: mealDate,
            mealType: mealType,
            mealDescription: trimmedDescription,
            glycemicImpact: glycemicImpact,
            photoData: photoData,
            carbsGrams: carbs,
            proteinGrams: protein,
            fatGrams: fats,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            selectedTemplateID: selectedTemplateID,
            postMealSymptomSeverity: postMealSeverity,
            postMealSymptomNote: trimmedPostMealSymptomNote.isEmpty ? nil : trimmedPostMealSymptomNote,
            postMealFeedbackTimestamp: feedbackTimestamp,
            nutritionImportID: reviewedNutritionImport?.id ?? nutritionImportID,
            barcode: barcode,
            sourceLabel: sourceLabel,
            calories: calories,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams,
            servingText: servingText
        )

        modelContext.insert(entry)
        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
        defaultsStore.lastMealType = mealType
        defaultsStore.lastMealGlycemicImpact = glycemicImpact
        suggestionProvider.recordMealDescription(trimmedDescription, mealType: mealType)
        if !trimmedNotes.isEmpty {
            let noteTokens = QuickNoteComposer.tokens(from: trimmedNotes)
            if noteTokens.count > 1 {
                for token in noteTokens {
                    suggestionProvider.recordMealNote(token, mealType: mealType)
                }
            } else {
                suggestionProvider.recordMealNote(trimmedNotes, mealType: mealType)
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
            InsightRefreshCoordinator.invalidate()
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
        selectedTemplateID = nil
        postMealSymptomSeverity = 0
        postMealSymptomNote = ""
        clearPendingNutritionImport()
    }

    func applyMealDescriptionSuggestion(_ suggestion: String) {
        mealDescription = suggestion
        selectedTemplateID = nil
    }

    func applyMealTemplate(_ template: MealTemplate) {
        mealType = template.mealType
        mealDescription = template.description
        glycemicImpact = template.glycemicImpact
        selectedTemplateID = template.id
        clearPendingNutritionImport()
    }

    func applyRecentMeal(_ suggestion: RecentMealReuseSuggestion) {
        mealType = suggestion.mealType
        mealDescription = suggestion.mealDescription
        glycemicImpact = suggestion.glycemicImpact
        carbsText = suggestion.carbsGrams.map { Self.formattedMacro($0) } ?? ""
        proteinText = suggestion.proteinGrams.map { Self.formattedMacro($0) } ?? ""
        fatText = suggestion.fatGrams.map { Self.formattedMacro($0) } ?? ""
        notes = suggestion.notes ?? ""
        selectedTemplateID = nil
        clearPendingNutritionImport()
    }

    func applyNutritionCandidate(_ candidate: FoodProductCandidate, importedAt: Date = Date()) {
        mealDescription = candidate.productName
        carbsText = candidate.carbsGrams.map { Self.formattedMacro($0) } ?? carbsText
        proteinText = candidate.proteinGrams.map { Self.formattedMacro($0) } ?? proteinText
        fatText = candidate.fatGrams.map { Self.formattedMacro($0) } ?? fatText
        barcode = candidate.barcode
        sourceLabel = candidate.sourceLabel
        calories = candidate.calories
        fiberGrams = candidate.fiberGrams
        sugarGrams = candidate.sugarGrams
        servingText = candidate.servingText
        selectedTemplateID = nil
        pendingNutritionCandidate = candidate
        pendingNutritionImportedAt = importedAt
        pendingNutritionImportSummary = NutritionImportDraftSummary(
            sourceLabel: candidate.sourceLabel,
            productName: candidate.productName,
            brandName: candidate.brandName,
            servingText: candidate.servingText,
            completeness: candidate.completeness
        )
        if let fiber = candidate.fiberGrams, fiber >= 5 {
            glycemicImpact = .medium
        }
    }

    func isMealNoteSelected(_ suggestion: String) -> Bool {
        QuickNoteComposer.isSelected(suggestion, in: notes)
    }

    func toggleMealNoteSuggestion(_ suggestion: String) {
        notes = QuickNoteComposer.toggled(suggestion, in: notes)
    }

    private static let persistenceStartupModeKey = "persistence.startupMode"

    private static func formattedMacro(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private func clearPendingNutritionImport() {
        pendingNutritionImportSummary = nil
        nutritionImportID = nil
        barcode = nil
        sourceLabel = nil
        calories = nil
        fiberGrams = nil
        sugarGrams = nil
        servingText = nil
        pendingNutritionCandidate = nil
        pendingNutritionImportedAt = nil
    }

    private static func resolveExistingMealsForUpsert(
        modelContext: ModelContext,
        targetDate: Date,
        targetType: MealType
    ) throws -> [MealEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: targetDate)
        guard let endOfDay = calendar.endOfDay(for: targetDate) else {
            return []
        }

        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.timestamp >= startOfDay && entry.timestamp < endOfDay
            }
        )

        let candidates = try modelContext.fetch(descriptor)
        return candidates.filter { $0.timestamp == targetDate && $0.mealType == targetType }
    }
}
