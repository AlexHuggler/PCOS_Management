import Testing
import SwiftData
@testable import CycleBalance

@Suite("Cycle Log Service", .serialized)
@MainActor
struct CycleLogServiceTests {
    @Test("Logging first period creates a new cycle")
    func firstPeriodCreatesCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        try service.logPeriodDay(
            date: Date(),
            flowIntensity: .medium,
            notes: nil,
            existingCycles: [],
            recentEntries: []
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 1)

        let entries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.cycle === cycles.first)
    }

    @Test("Period >10 days after last entry starts new cycle")
    func gapStartsNewCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let oldDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())!
        let existingCycle = Cycle(startDate: oldDate)
        context.insert(existingCycle)

        let oldEntry = CycleEntry(date: oldDate, flowIntensity: .medium, isPeriodDay: true)
        oldEntry.cycle = existingCycle
        context.insert(oldEntry)
        try context.save()

        try service.logPeriodDay(
            date: Date(),
            flowIntensity: .light,
            notes: nil,
            existingCycles: [existingCycle],
            recentEntries: [oldEntry]
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 2, "A new cycle should be created after 10+ day gap")
    }

    @Test("Period within 10 days stays in same cycle")
    func continuousPeriodSameCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let existingCycle = Cycle(startDate: yesterday)
        context.insert(existingCycle)

        let oldEntry = CycleEntry(date: yesterday, flowIntensity: .heavy, isPeriodDay: true)
        oldEntry.cycle = existingCycle
        context.insert(oldEntry)
        try context.save()

        try service.logPeriodDay(
            date: Date(),
            flowIntensity: .medium,
            notes: nil,
            existingCycles: [existingCycle],
            recentEntries: [oldEntry]
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 1, "Same cycle should be reused for consecutive period days")
    }

    @Test("Skipping period closes current cycle and creates new one")
    func skipPeriodCreatesNewCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let existingCycle = Cycle(startDate: Date().addingTimeInterval(-30 * 86400))
        context.insert(existingCycle)
        try context.save()

        try service.logSkippedPeriod(existingCycles: [existingCycle])

        #expect(existingCycle.endDate != nil, "Old cycle should be closed")
        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 2, "A new cycle should be created")
    }
}
