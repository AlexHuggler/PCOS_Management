import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Blood Sugar ViewModel", .serialized)
@MainActor
struct BloodSugarViewModelTests {
    private struct DirtySnapshot: Equatable {
        let glucoseValueText: String
        let readingType: GlucoseReadingType
        let mealContext: String
        let notes: String
        let readingDate: Date
    }

    // NOTE: TestHelpers.makeModelContainer() does not yet include BloodSugarReading.
    // These tests follow the existing pattern and will compile once the integration
    // pass adds BloodSugarReading to the TestHelpers schema.

    private func snapshot(for viewModel: BloodSugarViewModel) -> DirtySnapshot {
        DirtySnapshot(
            glucoseValueText: viewModel.glucoseValueText,
            readingType: viewModel.readingType,
            mealContext: viewModel.mealContext,
            notes: viewModel.notes,
            readingDate: viewModel.readingDate
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        let sourceURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL)
    }

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

    @Test("Init starts meal context fresh even when defaults exist")
    func initStartsMealContextFresh() throws {
        let container = try TestHelpers.makeModelContainer()
        let suiteName = "BloodSugarViewModelTests.initFresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastBloodSugarReadingType = .beforeMeal
        defaultsStore.lastBloodSugarMealContext = "After snack"

        let vm = BloodSugarViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        #expect(vm.readingType == .beforeMeal)
        #expect(vm.mealContext.isEmpty)
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
        #expect(vm.mealContext.isEmpty)
        #expect(vm.notes == "")
        #expect(!vm.isValidGlucose)
    }

    @Test("Save resets the form and supports a clean dirty baseline")
    func saveResetsAndClearsDirtyBaseline() throws {
        let container = try TestHelpers.makeModelContainer()
        let suiteName = "BloodSugarViewModelTests.dirty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastBloodSugarReadingType = .beforeMeal
        let vm = BloodSugarViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)
        var dirtyTracker = FormDirtyTracker(initial: snapshot(for: vm))

        vm.glucoseValueText = "118"
        vm.mealContext = "After breakfast"
        vm.notes = "Steady"

        #expect(dirtyTracker.isDirty(current: snapshot(for: vm)))

        try vm.saveReading()
        dirtyTracker.reset(to: snapshot(for: vm))

        #expect(vm.glucoseValueText.isEmpty)
        #expect(vm.mealContext.isEmpty)
        #expect(vm.notes.isEmpty)
        #expect(vm.readingType == .beforeMeal)
        #expect(!dirtyTracker.isDirty(current: snapshot(for: vm)))
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

    @Test("Selected blood sugar notes remain visible after multi-select")
    func selectedBloodSugarNotesRemainVisible() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = BloodSugarViewModel(modelContext: container.mainContext)

        vm.toggleNoteSuggestion("Dizzy")
        vm.toggleNoteSuggestion("Low energy")

        #expect(vm.noteSuggestions.contains("Dizzy"))
        #expect(vm.noteSuggestions.contains("Low energy"))
        #expect(vm.noteSuggestions.contains("After exercise"))
    }

    @Test("Insulin resistance metrics and spike samples are computed")
    func insulinResistanceMetricsComputed() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = BloodSugarViewModel(modelContext: context)
        let now = try #require(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 5, day: 19, hour: 12, minute: 0)
            )
        )

        let cycle = Cycle(
            startDate: Calendar.current.date(byAdding: .day, value: -20, to: now) ?? now,
            endDate: nil,
            lengthDays: 30,
            isPredicted: false
        )
        context.insert(cycle)

        context.insert(BloodSugarReading(timestamp: now.addingTimeInterval(-3600 * 5), glucoseValue: 102, readingType: .fasting))
        context.insert(BloodSugarReading(timestamp: now.addingTimeInterval(-3600 * 3), glucoseValue: 99, readingType: .beforeMeal, mealContext: "Dinner"))
        context.insert(BloodSugarReading(timestamp: now.addingTimeInterval(-3600 * 2), glucoseValue: 146, readingType: .afterMeal, mealContext: "Dinner"))
        try context.save()

        let metrics = vm.insulinResistanceMetrics(days: 30)
        #expect(metrics.fastingAverage != nil)
        #expect(metrics.medianPostMealSpike != nil)
        #expect(vm.postMealSpikePatterns(days: 30).count == 1)
    }

    @Test("Blood sugar screens explain meal pairing and HealthKit source")
    func bloodSugarScreensExplainMealPairingAndHealthKitSource() throws {
        let logSource = try sourceFile("PCOS/PCOS/Features/BloodSugar/Views/BloodSugarLogView.swift")
        let historySource = try sourceFile("PCOS/PCOS/Features/BloodSugar/Views/BloodSugarHistoryView.swift")

        #expect(logSource.contains("Pair this reading with a meal or snack if you can."))
        #expect(historySource.contains("Apple Health"))
        #expect(historySource.contains("fromHealthKit"))
    }
}
