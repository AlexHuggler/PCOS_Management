import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Supplement ViewModel", .serialized)
@MainActor
struct SupplementViewModelTests {

    /// Helper to create a container that includes SupplementLog.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SupplementLog.self,
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Log supplement creates entry")
    func logSupplementCreatesEntry() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)

        let now = Date()
        try vm.logSupplement(name: "Inositol", dosageMg: 4000, brand: "TestBrand", time: now)

        let logs = vm.fetchTodaysLogs()
        #expect(logs.count == 1)
        #expect(logs.first?.supplementName == "Inositol")
        #expect(logs.first?.dosageMg == 4000)
        #expect(logs.first?.brand == "TestBrand")
        #expect(logs.first?.taken == true)
    }

    @Test("Recommended dosage helpers return explicit values")
    func recommendedDosageHelpers() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)
        let inositol = PCOSSupplements.catalog.first { $0.name == "Inositol" }
        let spearmintTea = PCOSSupplements.catalog.first { $0.name == "Spearmint Tea" }

        #expect(vm.recommendedDosageLabel(for: inositol) == "Recommended dosage: 4000 mg")
        #expect(vm.recommendedDosageValue(for: inositol) == "4000")
        #expect(vm.recommendedDosageLabel(for: spearmintTea) == "No default dosage")
        #expect(vm.recommendedDosageValue(for: spearmintTea) == nil)
    }

    @Test("Saving supplement updates recent brand suggestions")
    func saveUpdatesRecentBrandSuggestions() throws {
        let container = try makeContainer()
        let suiteName = "SupplementViewModelTests.recentBrands.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        let provider = SuggestionProvider(defaultsStore: defaultsStore)
        let vm = SupplementViewModel(
            modelContext: container.mainContext,
            defaultsStore: defaultsStore,
            suggestionProvider: provider
        )

        try vm.logSupplement(name: "Magnesium", dosageMg: 400, brand: "Thorne", time: Date())
        try vm.logSupplement(name: "Omega-3", dosageMg: 1000, brand: "Nordic Naturals", time: Date())

        #expect(defaultsStore.recentSupplementBrands(limit: 2) == ["Nordic Naturals", "Thorne"])
    }

    @Test("Toggle taken flips boolean")
    func toggleTakenFlipsBoolean() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)

        try vm.logSupplement(name: "Vitamin D", dosageMg: 2000, brand: nil, time: Date())
        let logs = vm.fetchTodaysLogs()
        #expect(logs.count == 1)

        let log = logs[0]
        #expect(log.taken == true)

        vm.toggleTaken(log)
        #expect(log.taken == false)

        vm.toggleTaken(log)
        #expect(log.taken == true)
    }

    @Test("Fetch today's logs returns correct entries")
    func fetchTodaysLogsReturnsCorrectEntries() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)

        // Log two supplements today
        try vm.logSupplement(name: "Zinc", dosageMg: 30, brand: nil, time: Date())
        try vm.logSupplement(name: "Magnesium", dosageMg: 400, brand: nil, time: Date())

        // Insert one for yesterday directly (should NOT appear in today's logs)
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!
        let oldEntry = SupplementLog(
            date: yesterday,
            supplementName: "Old Entry",
            dosageMg: 100,
            timeTaken: yesterday,
            taken: true
        )
        container.mainContext.insert(oldEntry)
        try container.mainContext.save()

        let todaysLogs = vm.fetchTodaysLogs()
        #expect(todaysLogs.count == 2)

        let names = todaysLogs.map(\.supplementName)
        #expect(names.contains("Zinc"))
        #expect(names.contains("Magnesium"))
        #expect(!names.contains("Old Entry"))
    }

    @Test("Fetch user supplements returns distinct names")
    func fetchUserSupplementsReturnsDistinctNames() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)

        // Log same supplement twice and a different one
        try vm.logSupplement(name: "NAC", dosageMg: 600, brand: nil, time: Date())
        try vm.logSupplement(name: "NAC", dosageMg: 600, brand: nil, time: Date())
        try vm.logSupplement(name: "Folate", dosageMg: 400, brand: nil, time: Date())

        let userSupplements = vm.fetchUserSupplements()
        #expect(userSupplements.count == 2)
        #expect(userSupplements.contains("NAC"))
        #expect(userSupplements.contains("Folate"))
    }

    @Test("Adherence calculation correct")
    func adherenceCalculationCorrect() throws {
        let container = try makeContainer()
        let vm = SupplementViewModel(modelContext: container.mainContext)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Create 4 logs: 3 taken, 1 missed
        for i in 0..<3 {
            let time = calendar.date(byAdding: .hour, value: 8 + i, to: today)!
            let entry = SupplementLog(
                date: today,
                supplementName: "Supplement \(i)",
                dosageMg: 100,
                timeTaken: time,
                taken: true
            )
            container.mainContext.insert(entry)
        }

        let missedEntry = SupplementLog(
            date: today,
            supplementName: "Missed Supplement",
            dosageMg: 100,
            timeTaken: calendar.date(byAdding: .hour, value: 12, to: today)!,
            taken: false
        )
        container.mainContext.insert(missedEntry)
        try container.mainContext.save()

        let stats = vm.calculateAdherence(days: 7)
        #expect(stats.totalScheduled == 4)
        #expect(stats.totalTaken == 3)
        #expect(stats.percentage == 75.0)
    }

    @Test("Reset clears form state")
    func resetClearsState() throws {
        let container = try makeContainer()
        let suiteName = "SupplementViewModelTests.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        defaultsStore.lastSupplementName = "Myo-Inositol"
        defaultsStore.lastSupplementBrand = "Theralogix"
        let vm = SupplementViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.supplementName = "Inositol"
        vm.dosageText = "4000"
        vm.brand = "TestBrand"

        vm.reset()

        #expect(vm.supplementName == "Myo-Inositol")
        #expect(vm.dosageText == "")
        #expect(vm.brand == "Theralogix")
    }

    @Test("Preferred supplement time becomes available after save")
    func preferredTimeAvailability() throws {
        let container = try makeContainer()
        let suiteName = "SupplementViewModelTests.preferredTime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let defaultsStore = UserEntryDefaultsStore(defaults: defaults)
        let vm = SupplementViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        #expect(!vm.hasPreferredSupplementTime)

        let expectedTime = Date().addingTimeInterval(-3600)
        try vm.logSupplement(name: "Magnesium", dosageMg: 400, brand: nil, time: expectedTime)

        #expect(vm.hasPreferredSupplementTime)
        let actual = vm.preferredSupplementTime
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute], from: expectedTime)
        let actualComponents = Calendar.current.dateComponents([.hour, .minute], from: actual)
        #expect(actualComponents.hour == expectedComponents.hour)
        #expect(actualComponents.minute == expectedComponents.minute)
    }
}
