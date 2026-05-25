import Testing
import Foundation
import SwiftData
@testable import PCOS

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
        let noPeriodMarker = CycleEntry(date: Date(), flowIntensity: FlowIntensity.none, isPeriodDay: false)
        noPeriodMarker.cycle = attachedCycle

        context.insert(orphan)
        context.insert(attached)
        context.insert(noPeriodMarker)
        try context.save()

        let removedCount = try service.cleanUpOrphanedEntries()
        #expect(removedCount == 1)

        let remainingEntries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(remainingEntries.count == 2)
        #expect(remainingEntries.allSatisfy { $0.cycle === attachedCycle })
        #expect(remainingEntries.contains { $0.flowIntensity == FlowIntensity.none && !$0.isPeriodDay })
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

    @Test("Fetch current cycle entries includes entries across month boundaries")
    func fetchCurrentCycleEntriesUsesCycleBoundaryNotMonthBoundary() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleQueryService(modelContext: context)

        let calendar = Calendar.current
        let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let cycleStart = calendar.date(byAdding: .day, value: -3, to: startOfCurrentMonth)!
        let currentCycle = Cycle(startDate: cycleStart)
        context.insert(currentCycle)

        let previousMonthEntry = CycleEntry(date: cycleStart, flowIntensity: .medium, isPeriodDay: true)
        previousMonthEntry.cycle = currentCycle
        let currentMonthEntry = CycleEntry(date: calendar.date(byAdding: .day, value: 1, to: startOfCurrentMonth)!, flowIntensity: .light, isPeriodDay: true)
        currentMonthEntry.cycle = currentCycle
        context.insert(previousMonthEntry)
        context.insert(currentMonthEntry)
        try context.save()

        let entries = try service.fetchCurrentCycleEntries(referenceDate: Date())
        #expect(entries.count == 2)
        #expect(entries.contains(where: { calendar.isDate($0.date, inSameDayAs: cycleStart) }))
    }
}
