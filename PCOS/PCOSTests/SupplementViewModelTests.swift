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
        let expectedInositolDosage = L10n.decimal(4000, fractionDigits: 0)

        #expect(
            vm.recommendedDosageLabel(for: inositol) == String(
                localized: "Recommended dosage: \(expectedInositolDosage) mg",
                comment: "Supplement picker helper text showing the recommended dosage in milligrams."
            )
        )
        #expect(vm.recommendedDosageValue(for: inositol) == expectedInositolDosage)
        #expect(
            vm.recommendedDosageLabel(for: spearmintTea) == String(
                localized: "No default dosage",
                comment: "Supplement picker helper text when a supplement has no default dosage."
            )
        )
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
        let expectedTime = Calendar.current.date(bySettingHour: 21, minute: 15, second: 0, of: Date()) ?? Date()
        defaultsStore.lastSupplementTime = expectedTime
        let vm = SupplementViewModel(modelContext: container.mainContext, defaultsStore: defaultsStore)

        vm.supplementName = "Inositol"
        vm.dosageText = "4000"
        vm.brand = "TestBrand"

        vm.reset()

        #expect(vm.supplementName.isEmpty)
        #expect(vm.dosageText == "")
        #expect(vm.brand.isEmpty)

        let actualComponents = Calendar.current.dateComponents([.hour, .minute], from: vm.scheduledTime)
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute], from: expectedTime)
        #expect(actualComponents.hour == expectedComponents.hour)
        #expect(actualComponents.minute == expectedComponents.minute)
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

    @Test("Repeat yesterday copies prior-day supplements into today")
    func repeatYesterdayCopiesEntriesToToday() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vm = SupplementViewModel(modelContext: context)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let morningYesterday = calendar.date(bySettingHour: 8, minute: 30, second: 15, of: yesterdayStart) ?? yesterdayStart
        let eveningYesterday = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: yesterdayStart) ?? yesterdayStart

        context.insert(
            SupplementLog(
                date: yesterdayStart,
                supplementName: "Magnesium",
                dosageMg: 400,
                timeTaken: morningYesterday,
                taken: false,
                brand: "Thorne"
            )
        )
        context.insert(
            SupplementLog(
                date: yesterdayStart,
                supplementName: "Omega-3",
                dosageMg: 1000,
                timeTaken: eveningYesterday,
                taken: true,
                brand: "Nordic Naturals"
            )
        )
        try context.save()

        let insertedCount = try vm.repeatYesterdaySupplements()
        let todaysLogs = vm.fetchTodaysLogs()

        #expect(insertedCount == 2)
        #expect(todaysLogs.count == 2)

        let magnesium = todaysLogs.first { $0.supplementName == "Magnesium" }
        let omega = todaysLogs.first { $0.supplementName == "Omega-3" }
        #expect(magnesium?.taken == true)
        #expect(omega?.taken == true)
        #expect(omega?.brand == "Nordic Naturals")

        let magnesiumTime = calendar.dateComponents([.hour, .minute], from: magnesium?.timeTaken ?? Date.distantPast)
        let omegaTime = calendar.dateComponents([.hour, .minute], from: omega?.timeTaken ?? Date.distantPast)
        #expect(magnesiumTime.hour == 8)
        #expect(magnesiumTime.minute == 30)
        #expect(omegaTime.hour == 21)
        #expect(omegaTime.minute == 0)
        #expect(calendar.isDate(magnesium?.date ?? Date.distantPast, inSameDayAs: Date()))
        #expect(calendar.isDate(omega?.date ?? Date.distantPast, inSameDayAs: Date()))
    }

    @Test("Repeat yesterday skips entries that already exist today")
    func repeatYesterdaySkipsExistingEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vm = SupplementViewModel(modelContext: context)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let repeatedTime = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: todayStart) ?? todayStart
        let yesterdayRepeatedTime = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: yesterdayStart) ?? yesterdayStart
        let yesterdayUniqueTime = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: yesterdayStart) ?? yesterdayStart

        context.insert(
            SupplementLog(
                date: yesterdayStart,
                supplementName: "Magnesium",
                dosageMg: 400,
                timeTaken: yesterdayRepeatedTime,
                taken: true,
                brand: "Thorne"
            )
        )
        context.insert(
            SupplementLog(
                date: yesterdayStart,
                supplementName: "Zinc",
                dosageMg: 30,
                timeTaken: yesterdayUniqueTime,
                taken: true,
                brand: nil
            )
        )
        context.insert(
            SupplementLog(
                date: todayStart,
                supplementName: "Magnesium",
                dosageMg: 400,
                timeTaken: repeatedTime,
                taken: true,
                brand: "Thorne"
            )
        )
        try context.save()

        let insertedCount = try vm.repeatYesterdaySupplements()
        let todaysLogs = vm.fetchTodaysLogs()

        #expect(insertedCount == 1)
        #expect(todaysLogs.count == 2)
        #expect(todaysLogs.filter { $0.supplementName == "Magnesium" }.count == 1)
        #expect(todaysLogs.contains { $0.supplementName == "Zinc" })
    }

    @Test("Dosage changes are detected over time for same supplement")
    func dosageChangeDetection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vm = SupplementViewModel(modelContext: context)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())

        let first = SupplementLog(
            date: start,
            supplementName: "Inositol",
            dosageMg: 2000,
            timeTaken: start.addingTimeInterval(8 * 3600),
            taken: true
        )
        let second = SupplementLog(
            date: start.addingTimeInterval(24 * 3600),
            supplementName: "Inositol",
            dosageMg: 4000,
            timeTaken: start.addingTimeInterval(32 * 3600),
            taken: true
        )
        context.insert(first)
        context.insert(second)
        try context.save()

        let changes = vm.dosageChanges(days: 30)
        #expect(changes.count == 1)
        #expect(changes.first?.previousDosageMg == 2000)
        #expect(changes.first?.newDosageMg == 4000)
    }
}
