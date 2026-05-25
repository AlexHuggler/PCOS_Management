import Foundation
import SwiftData

/// Handles cycle-related read/query operations and lightweight cleanup.
@MainActor
struct CycleQueryService {
    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func cleanUpOrphanedEntries() throws -> Int {
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.cycle == nil
            }
        )

        let orphans = try modelContext.fetch(descriptor)
        guard !orphans.isEmpty else { return 0 }

        for orphan in orphans {
            modelContext.delete(orphan)
        }
        try modelContext.save()

        return orphans.count
    }

    func fetchCycles() throws -> [Cycle] {
        let descriptor = FetchDescriptor<Cycle>(
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCurrentCycleEntries(referenceDate: Date = Date()) throws -> [CycleEntry] {
        let cycles = try fetchCycles()
        guard let targetCycle = cycleContaining(referenceDate, in: cycles) ?? currentOpenCycle(in: cycles) else {
            return []
        }

        let cycleStart = normalized(targetCycle.startDate)
        let nextCycleStart = nextCycle(after: targetCycle, in: cycles).map { normalized($0.startDate) }

        let descriptor: FetchDescriptor<CycleEntry>
        if let nextCycleStart {
            descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { entry in
                    entry.date >= cycleStart && entry.date < nextCycleStart
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { entry in
                    entry.date >= cycleStart
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
        }

        return try modelContext.fetch(descriptor)
    }

    func entriesForMonth(year: Int, month: Int, earliestDate: Date? = nil) throws -> [Int: CycleEntry] {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.endOfMonth(for: startOfMonth) else {
            return [:]
        }

        let descriptor: FetchDescriptor<CycleEntry>
        if let earliestDate {
            descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { entry in
                    entry.date >= startOfMonth && entry.date < endOfMonth && entry.date >= earliestDate
                },
                sortBy: [SortDescriptor(\.date)]
            )
        } else {
            descriptor = FetchDescriptor<CycleEntry>(
                predicate: #Predicate<CycleEntry> { entry in
                    entry.date >= startOfMonth && entry.date < endOfMonth
                },
                sortBy: [SortDescriptor(\.date)]
            )
        }

        let entries = try modelContext.fetch(descriptor)

        var result: [Int: CycleEntry] = [:]
        for entry in entries {
            let day = calendar.component(.day, from: entry.date)
            result[day] = entry
        }

        return result
    }
}

private extension CycleQueryService {
    func currentOpenCycle(in cycles: [Cycle]) -> Cycle? {
        cycles.sorted(by: { $0.startDate < $1.startDate }).last { $0.endDate == nil }
    }

    func nextCycle(after cycle: Cycle, in cycles: [Cycle]) -> Cycle? {
        let sortedCycles = cycles.sorted(by: { $0.startDate < $1.startDate })
        guard let index = sortedCycles.firstIndex(where: { $0.id == cycle.id }),
              index < sortedCycles.index(before: sortedCycles.endIndex) else {
            return nil
        }

        return sortedCycles[sortedCycles.index(after: index)]
    }

    func cycleContaining(_ date: Date, in cycles: [Cycle]) -> Cycle? {
        let normalizedDate = normalized(date)
        let sortedCycles = cycles.sorted(by: { $0.startDate < $1.startDate })

        for index in sortedCycles.indices {
            let cycle = sortedCycles[index]
            let cycleStart = normalized(cycle.startDate)
            let nextCycleStart = index < sortedCycles.index(before: sortedCycles.endIndex)
                ? normalized(sortedCycles[sortedCycles.index(after: index)].startDate)
                : nil

            if normalizedDate >= cycleStart && (nextCycleStart == nil || normalizedDate < nextCycleStart!) {
                return cycle
            }
        }

        return nil
    }

    func normalized(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
