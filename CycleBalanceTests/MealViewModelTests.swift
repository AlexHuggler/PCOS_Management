import Testing
import Foundation
import SwiftData
@testable import CycleBalance

@Suite("Meal ViewModel", .serialized)
@MainActor
struct MealViewModelTests {

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

        #expect(defaultsStore.recentMealDescriptions(limit: 1) == ["Eggs + avocado toast"])
        #expect(defaultsStore.recentMealNotes(limit: 1) == ["Post-workout"])
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

        vm.toggleMealNoteSuggestion("High stress")
        #expect(vm.notes == "High stress")
        #expect(vm.isMealNoteSelected("High stress"))

        vm.toggleMealNoteSuggestion("Late meal")
        #expect(vm.notes == "High stress, Late meal")
        #expect(vm.isMealNoteSelected("Late meal"))

        vm.toggleMealNoteSuggestion("High stress")
        #expect(vm.notes == "Late meal")
        #expect(!vm.isMealNoteSelected("High stress"))
    }
}
