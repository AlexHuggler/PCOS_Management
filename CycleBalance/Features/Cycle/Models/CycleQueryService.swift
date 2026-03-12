import Foundation
import SwiftData

/// Handles cycle-related read/query operations and lightweight cleanup.
@MainActor
struct CycleQueryService {
    private let modelContext: ModelContext

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
        let calendar = Calendar.current
        guard let startOfMonth = calendar.startOfMonth(for: referenceDate) else {
            return []
        }

        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startOfMonth
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    func entriesForMonth(year: Int, month: Int) throws -> [Int: CycleEntry] {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let startOfMonth = calendar.date(from: components),
              let endOfMonth = calendar.endOfMonth(for: startOfMonth) else {
            return [:]
        }

        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startOfMonth && entry.date < endOfMonth
            },
            sortBy: [SortDescriptor(\.date)]
        )

        let entries = try modelContext.fetch(descriptor)

        var result: [Int: CycleEntry] = [:]
        for entry in entries {
            let day = calendar.component(.day, from: entry.date)
            result[day] = entry
        }

        return result
    }
}
