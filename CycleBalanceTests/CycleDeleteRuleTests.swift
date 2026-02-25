import Testing
import SwiftData
@testable import CycleBalance

@Suite("Cycle Delete Rule", .serialized)
@MainActor
struct CycleDeleteRuleTests {
    @Test("Deleting a cycle cascades to its entries")
    func cascadeDeleteRemovesEntries() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let cycle = Cycle(startDate: Date())
        context.insert(cycle)

        let entry = CycleEntry(date: Date(), flowIntensity: .medium, isPeriodDay: true)
        entry.cycle = cycle
        context.insert(entry)
        try context.save()

        let entryID = entry.id
        context.delete(cycle)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<CycleEntry>())
        let found = remaining.contains { $0.id == entryID }
        #expect(!found, "CycleEntry should be cascade-deleted with its Cycle")
    }

    @Test("Cycle entries without a cycle are orphans")
    func orphanedEntryDetection() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let entry = CycleEntry(date: Date(), flowIntensity: .light, isPeriodDay: true)
        context.insert(entry)
        try context.save()

        #expect(entry.cycle == nil, "Entry without a cycle assignment is orphaned")
    }
}
