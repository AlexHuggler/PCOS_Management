import Testing
import Foundation
import SwiftData
@testable import CycleBalance

@Suite("Blood Sugar ViewModel", .serialized)
@MainActor
struct BloodSugarViewModelTests {

    // NOTE: TestHelpers.makeModelContainer() does not yet include BloodSugarReading.
    // These tests follow the existing pattern and will compile once the integration
    // pass adds BloodSugarReading to the TestHelpers schema.

    @Test("Valid glucose values in 40-600 range are accepted")
    func validGlucoseRange() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.glucoseValueText = "100"
        #expect(vm.isValidGlucose)

        vm.glucoseValueText = "40"
        #expect(vm.isValidGlucose)

        vm.glucoseValueText = "600"
        #expect(vm.isValidGlucose)

        vm.glucoseValueText = "85.5"
        #expect(vm.isValidGlucose)
    }

    @Test("Invalid glucose values are rejected")
    func invalidGlucoseRejected() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.glucoseValueText = ""
        #expect(!vm.isValidGlucose)

        vm.glucoseValueText = "abc"
        #expect(!vm.isValidGlucose)

        vm.glucoseValueText = "39"
        #expect(!vm.isValidGlucose)

        vm.glucoseValueText = "601"
        #expect(!vm.isValidGlucose)

        vm.glucoseValueText = "-10"
        #expect(!vm.isValidGlucose)
    }

    @Test("Save creates a reading in the model context")
    func saveCreatesReading() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.glucoseValueText = "120"
        vm.readingType = .fasting
        vm.mealContext = "Morning"
        vm.notes = "Felt fine"

        try vm.saveReading()

        let descriptor = FetchDescriptor<BloodSugarReading>()
        let readings = try container.mainContext.fetch(descriptor)

        #expect(readings.count == 1)
        #expect(readings.first?.glucoseValue == 120)
        #expect(readings.first?.readingType == .fasting)
        #expect(readings.first?.mealContext == "Morning")
        #expect(readings.first?.notes == "Felt fine")
        #expect(readings.first?.fromHealthKit == false)
    }

    @Test("Save persists meal context and notes for future suggestions")
    func savePersistsContextAndNotesSuggestions() throws {
        let container = try TestHelpers.makeModelContainer()
        let suiteName = "BloodSugarViewModelTests.suggestions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        let vm = BloodSugarViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.glucoseValueText = "102"
        vm.readingType = .beforeMeal
        vm.mealContext = "Before lunch"
        vm.notes = "Low energy"

        try vm.saveReading()

        #expect(defaultsStore.recentBloodSugarMealContexts(limit: 1) == ["Before lunch"])
        #expect(defaultsStore.recentBloodSugarNotes(limit: 1) == ["Low energy"])
    }

    @Test("Save with invalid glucose throws an error")
    func saveInvalidGlucoseThrows() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.glucoseValueText = "39"

        #expect(throws: BloodSugarError.self) {
            try vm.saveReading()
        }

        let descriptor = FetchDescriptor<BloodSugarReading>()
        let readings = try container.mainContext.fetch(descriptor)
        #expect(readings.isEmpty)
    }

    @Test("Fetch today's readings returns only today's entries")
    func fetchTodaysReadings() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = BloodSugarViewModel(modelContext: context)

        // Insert a reading for today
        let todayReading = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 110,
            readingType: .random
        )
        context.insert(todayReading)

        // Insert a reading for yesterday
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayReading = BloodSugarReading(
            timestamp: yesterday,
            glucoseValue: 95,
            readingType: .fasting
        )
        context.insert(yesterdayReading)

        try context.save()

        let todaysReadings = vm.fetchTodaysReadings()
        #expect(todaysReadings.count == 1)
        #expect(todaysReadings.first?.glucoseValue == 110)
    }

    @Test("Average glucose calculation across readings")
    func averageGlucoseCalculation() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = BloodSugarViewModel(modelContext: context)

        // Insert multiple readings
        let reading1 = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 100,
            readingType: .fasting
        )
        let reading2 = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 150,
            readingType: .fasting
        )
        let reading3 = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 200,
            readingType: .afterMeal
        )

        context.insert(reading1)
        context.insert(reading2)
        context.insert(reading3)
        try context.save()

        // Average of all readings
        let overallAverage = vm.averageGlucose(for: nil, days: 7)
        #expect(overallAverage == 150.0)

        // Average for fasting only
        let fastingAverage = vm.averageGlucose(for: .fasting, days: 7)
        #expect(fastingAverage == 125.0)

        // Average for a type with no readings
        let beforeMealAverage = vm.averageGlucose(for: .beforeMeal, days: 7)
        #expect(beforeMealAverage == nil)
    }

    @Test("Reset clears all form state")
    func resetClearsState() throws {
        let container = try TestHelpers.makeModelContainer()
        let suiteName = "BloodSugarViewModelTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastBloodSugarReadingType = .beforeMeal
        defaultsStore.lastBloodSugarMealContext = "After snack"
        let vm = BloodSugarViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.glucoseValueText = "120"
        vm.readingType = .fasting
        vm.mealContext = "Breakfast"
        vm.notes = "Test note"

        vm.reset()

        #expect(vm.glucoseValueText == "")
        #expect(vm.readingType == .beforeMeal)
        #expect(vm.mealContext == "After snack")
        #expect(vm.notes == "")
        #expect(!vm.isValidGlucose)
    }

    @Test("Delete removes a reading from the context")
    func deleteRemovesReading() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = BloodSugarViewModel(modelContext: context)

        let reading = BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 130,
            readingType: .random
        )
        context.insert(reading)
        try context.save()

        let beforeDelete = try context.fetch(FetchDescriptor<BloodSugarReading>())
        #expect(beforeDelete.count == 1)

        vm.deleteReading(reading)

        let afterDelete = try context.fetch(FetchDescriptor<BloodSugarReading>())
        #expect(afterDelete.isEmpty)
    }

    @Test("Quick-note toggles build comma-separated notes and support deselection")
    func quickNoteToggleComposition() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.toggleNoteSuggestion("Felt fine")
        #expect(vm.notes == "Felt fine")
        #expect(vm.isNoteSuggestionSelected("Felt fine"))

        vm.toggleNoteSuggestion("Missed meal")
        #expect(vm.notes == "Felt fine, Missed meal")
        #expect(vm.isNoteSuggestionSelected("Missed meal"))

        vm.toggleNoteSuggestion("Felt fine")
        #expect(vm.notes == "Missed meal")
        #expect(!vm.isNoteSuggestionSelected("Felt fine"))
    }
}
