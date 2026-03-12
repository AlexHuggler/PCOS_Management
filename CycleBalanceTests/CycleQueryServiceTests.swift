import Testing
import Foundation
import SwiftData
@testable import CycleBalance

@Suite("Cycle Query Service", .serialized)
@MainActor
struct CycleQueryServiceTests {
    @Test("Cleanup removes orphaned entries")
    func cleanUpOrphanedEntries() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleQueryService(modelContext: context)

        let attachedCycle = Cycle(startDate: Date())
        context.insert(attachedCycle)

        let orphan = CycleEntry(date: Date(), isPeriodDay: true)
        let attached = CycleEntry(date: Date(), isPeriodDay: true)
        attached.cycle = attachedCycle

        context.insert(orphan)
        context.insert(attached)
        try context.save()

        let removedCount = try service.cleanUpOrphanedEntries()
        #expect(removedCount == 1)

        let remainingEntries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(remainingEntries.count == 1)
        #expect(remainingEntries.first?.cycle === attachedCycle)
    }

    @Test("Fetch cycles returns ascending start date")
    func fetchCyclesSortedAscending() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleQueryService(modelContext: context)

        let oldDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let newDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!

        context.insert(Cycle(startDate: newDate))
        context.insert(Cycle(startDate: oldDate))
        try context.save()

        let cycles = try service.fetchCycles()
        #expect(cycles.count == 2)
        #expect(cycles[0].startDate <= cycles[1].startDate)
    }
}
