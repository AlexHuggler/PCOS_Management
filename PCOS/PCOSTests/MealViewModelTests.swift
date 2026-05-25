import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Meal ViewModel", .serialized)
@MainActor
struct MealViewModelTests {
    private enum MockMealFetchError: LocalizedError {
        case dedupeFetchFailed

        var errorDescription: String? {
            "Meal dedupe fetch failed in test"
        }
    }

    /// Creates an in-memory ModelContainer that includes MealEntry.
    private func makeMealContainer() throws -> ModelContainer {
        let schema = Schema([MealEntry.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makePersistentMealContainer() throws -> (container: ModelContainer, cleanupURL: URL) {
        let schema = Schema([MealEntry.self])
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "MealViewModelTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let config = ModelConfiguration(
            schema: schema,
            url: directoryURL.appendingPathComponent("Meal.sqlite"),
            cloudKitDatabase: .none
        )

        return (try ModelContainer(for: schema, configurations: [config]), directoryURL)
    }

    private func mealLogViewSource() throws -> String {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let sourceURL = projectRoot.appendingPathComponent("PCOS/PCOS/Features/Meals/Views/MealLogView.swift")
        return try String(contentsOf: sourceURL)
    }

    @Test("Valid meal saves correctly")
    func validMealSaves() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.mealDescription = "Grilled chicken salad"
        vm.mealType = .lunch
        vm.glycemicImpact = .low
        vm.carbsText = "25"
        vm.proteinText = "30"
        vm.fatText = "18"
        vm.notes = "Light dressing"
        vm.mealDate = Date()

        try vm.saveMeal()

        // After save, form should be reset
        #expect(vm.mealDescription.isEmpty)
        #expect(vm.carbsText.isEmpty)
        #expect(vm.proteinText.isEmpty)
        #expect(vm.fatText.isEmpty)
        #expect(vm.notes.isEmpty)

        // Verify the entry was persisted
        let meals = vm.fetchTodaysMeals()
        #expect(meals.count == 1)

        let saved = meals[0]
        #expect(saved.mealDescription == "Grilled chicken salad")
        #expect(saved.mealType == .lunch)
        #expect(saved.glycemicImpact == .low)
        #expect(saved.carbsGrams == 25.0)
        #expect(saved.proteinGrams == 30.0)
        #expect(saved.fatGrams == 18.0)
        #expect(saved.notes == "Light dressing")
    }

    @Test("Save persists meal description and note suggestions")
    func savePersistsSuggestionHistory() throws {
        let container = try makeMealContainer()
        let suiteName = "MealViewModelTests.suggestions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        let vm = MealViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.mealType = .breakfast
        vm.mealDescription = "Eggs + avocado toast"
        vm.glycemicImpact = .low
        vm.notes = "Post-workout"

        try vm.saveMeal()

        #expect(defaultsStore.recentMealDescriptions(mealType: .breakfast, limit: 1) == ["Eggs + avocado toast"])
        #expect(defaultsStore.recentMealNotes(mealType: .breakfast, limit: 1) == ["Post-workout"])
    }

    @Test("Empty description fails validation")
    func emptyDescriptionInvalid() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.mealDescription = ""
        #expect(!vm.isValid)

        vm.mealDescription = "   "
        #expect(!vm.isValid)

        vm.mealDescription = "Oatmeal"
        #expect(vm.isValid)
    }

    @Test("Fetch today's meals returns correct entries")
    func fetchTodaysMeals() throws {
        let container = try makeMealContainer()
        let context = container.mainContext

        // Insert a meal for today
        let todayMeal = MealEntry(
            timestamp: Date(),
            mealType: .breakfast,
            mealDescription: "Oatmeal with berries",
            glycemicImpact: .low
        )
        context.insert(todayMeal)

        // Insert a meal for yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayMeal = MealEntry(
            timestamp: yesterday,
            mealType: .dinner,
            mealDescription: "Pasta",
            glycemicImpact: .high
        )
        context.insert(yesterdayMeal)

        try context.save()

        let vm = MealViewModel(modelContext: context)
        let todaysMeals = vm.fetchTodaysMeals()

        #expect(todaysMeals.count == 1)
        #expect(todaysMeals[0].mealDescription == "Oatmeal with berries")
    }

    @Test("GI distribution calculation correct")
    func giDistributionCalculation() throws {
        let container = try makeMealContainer()
        let context = container.mainContext

        // Insert meals with different GI levels
        let meals: [(MealType, GlycemicImpact)] = [
            (.breakfast, .low),
            (.lunch, .medium),
            (.dinner, .high),
            (.snack, .low),
            (.lunch, .low),
        ]

        for (type, gi) in meals {
            let entry = MealEntry(
                timestamp: Date(),
                mealType: type,
                mealDescription: "Test meal",
                glycemicImpact: gi
            )
            context.insert(entry)
        }
        try context.save()

        let vm = MealViewModel(modelContext: context)
        let distribution = vm.giDistribution(days: 7)

        #expect(distribution[.low] == 3)
        #expect(distribution[.medium] == 1)
        #expect(distribution[.high] == 1)
    }

    @Test("Delete removes meal")
    func deleteMeal() throws {
        let container = try makeMealContainer()
        let context = container.mainContext

        let meal = MealEntry(
            timestamp: Date(),
            mealType: .snack,
            mealDescription: "Apple slices",
            glycemicImpact: .low
        )
        context.insert(meal)
        try context.save()

        let vm = MealViewModel(modelContext: context)
        #expect(vm.fetchTodaysMeals().count == 1)

        vm.deleteMeal(meal)
        #expect(vm.fetchTodaysMeals().count == 0)
    }

    @Test("Reset clears state")
    func resetClearsState() throws {
        let container = try makeMealContainer()
        let suiteName = "MealViewModelTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastMealType = .breakfast
        defaultsStore.lastMealGlycemicImpact = .low
        let vm = MealViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.mealType = .dinner
        vm.mealDescription = "Salmon with rice"
        vm.glycemicImpact = .high
        vm.carbsText = "50"
        vm.proteinText = "35"
        vm.fatText = "20"
        vm.notes = "Was delicious"

        vm.reset()

        #expect(vm.mealType == .breakfast)
        #expect(vm.mealDescription.isEmpty)
        #expect(vm.glycemicImpact == .low)
        #expect(vm.carbsText.isEmpty)
        #expect(vm.proteinText.isEmpty)
        #expect(vm.fatText.isEmpty)
        #expect(vm.photoData == nil)
        #expect(vm.notes.isEmpty)
    }

    @Test("Meal quick-note toggles build comma-separated notes and support deselection")
    func mealQuickNoteToggleComposition() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.toggleMealNoteSuggestion("Balanced meal")
        #expect(vm.notes == "Balanced meal")
        #expect(vm.isMealNoteSelected("Balanced meal"))

        vm.toggleMealNoteSuggestion("Ate out")
        #expect(vm.notes == "Balanced meal, Ate out")
        #expect(vm.isMealNoteSelected("Ate out"))

        vm.toggleMealNoteSuggestion("Balanced meal")
        #expect(vm.notes == "Ate out")
        #expect(!vm.isMealNoteSelected("Balanced meal"))
    }

    @Test("Meal suggestions are scoped by meal type")
    func mealSuggestionsAreScopedByMealType() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.mealType = .breakfast
        vm.mealDescription = "parfait"
        #expect(vm.mealDescriptionSuggestions == ["Yogurt parfait"])
        #expect(vm.mealNoteSuggestions.contains("Coffee first"))
        #expect(!vm.mealNoteSuggestions.contains("Late dinner"))

        vm.mealType = .dinner
        vm.mealDescription = "parfait"
        #expect(vm.mealDescriptionSuggestions.isEmpty)
        #expect(vm.mealNoteSuggestions.contains("Late dinner"))
        #expect(!vm.mealNoteSuggestions.contains("Coffee first"))
    }

    @Test("Selected meal notes remain visible after multi-select")
    func selectedMealNotesRemainVisible() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.mealType = .dinner
        vm.toggleMealNoteSuggestion("Balanced meal")
        vm.toggleMealNoteSuggestion("Late dinner")

        #expect(vm.mealNoteSuggestions.contains("Balanced meal"))
        #expect(vm.mealNoteSuggestions.contains("Late dinner"))
        #expect(vm.mealNoteSuggestions.contains("High carb"))
    }

    @Test("Applying a meal template updates description, type, GI, and template id")
    func applyMealTemplateUpdatesFields() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        let template = try #require(vm.mealTemplates.first)
        vm.applyMealTemplate(template)

        #expect(vm.mealType == template.mealType)
        #expect(vm.mealDescription == template.description)
        #expect(vm.glycemicImpact == template.glycemicImpact)
        #expect(vm.selectedTemplateID == template.id)
    }

    @Test("High GI meal description surfaces deterministic swap suggestions")
    func highGIMealSwapSuggestions() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.glycemicImpact = .high
        vm.mealDescription = "White rice and soda"

        #expect(!vm.swapSuggestions.isEmpty)
        #expect(vm.swapSuggestions.contains(where: { $0.localizedCaseInsensitiveContains("cauliflower rice") }))
    }

    @Test("Save persists post-meal feedback and selected template id")
    func savePersistsPostMealFeedback() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(modelContext: container.mainContext)

        vm.mealDescription = "Test meal"
        vm.selectedTemplateID = "template-id"
        vm.postMealSymptomSeverity = 4
        vm.postMealSymptomNote = "Bloated"

        try vm.saveMeal()

        let saved = try #require(vm.fetchTodaysMeals().first)
        #expect(saved.selectedTemplateID == "template-id")
        #expect(saved.postMealSymptomSeverity == 4)
        #expect(saved.postMealSymptomNote == "Bloated")
        #expect(saved.postMealFeedbackTimestamp != nil)
    }

    @Test("Meal log source exposes post-meal feedback controls")
    func mealLogSourceExposesPostMealFeedbackControls() throws {
        let source = try mealLogViewSource()

        #expect(source.contains("After-meal check-in"))
        #expect(source.contains("postMealSymptomSeverity"))
        #expect(source.contains("postMealSymptomNote"))
    }

    @Test("Save dedupes matching meals in a persisted SwiftData store")
    func saveDedupesMatchingMealsInPersistedStore() throws {
        let (container, cleanupURL) = try makePersistentMealContainer()
        defer { try? FileManager.default.removeItem(at: cleanupURL) }

        let context = container.mainContext
        let timestamp = Date(timeIntervalSince1970: 1_700_111_111)
        let existingMeal = MealEntry(
            timestamp: timestamp,
            mealType: .lunch,
            mealDescription: "Old lunch",
            glycemicImpact: .low
        )
        context.insert(existingMeal)
        try context.save()

        let vm = MealViewModel(modelContext: context)
        vm.mealDate = timestamp
        vm.mealType = .lunch
        vm.mealDescription = "Updated lunch"
        vm.glycemicImpact = .medium

        try vm.saveMeal()

        let storedMeals = try context.fetch(
            FetchDescriptor<MealEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        )
        #expect(storedMeals.count == 1)
        #expect(storedMeals.first?.mealDescription == "Updated lunch")
        #expect(storedMeals.first?.glycemicImpact == .medium)
    }

    @Test("Save continues when the meal dedupe fetch path fails")
    func saveContinuesWhenDedupeFetchFails() throws {
        let container = try makeMealContainer()
        let vm = MealViewModel(
            modelContext: container.mainContext,
            existingMealsResolver: { _, _, _ in
                throw MockMealFetchError.dedupeFetchFailed
            }
        )

        vm.mealDescription = "Fallback save"
        vm.mealType = .dinner
        vm.glycemicImpact = .low

        try vm.saveMeal()

        let savedMeal = try #require(vm.fetchTodaysMeals().first)
        #expect(savedMeal.mealDescription == "Fallback save")
        #expect(savedMeal.mealType == .dinner)
    }
}
