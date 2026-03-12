import Foundation
import SwiftData
import os

/// Handles all write operations for cycle/period data: inserting entries,
/// managing cycle boundaries, and persisting to SwiftData.
@MainActor
struct CycleLogService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Log a period day, assigning it to the appropriate cycle.
    @discardableResult
    func logPeriodDay(
        date: Date,
        flowIntensity: FlowIntensity,
        notes: String?,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry]
    ) throws -> PersistentIdentifier {
        let entry = CycleEntry(
            date: date,
            flowIntensity: flowIntensity,
            isPeriodDay: true,
            cyclePhase: .menstrual,
            notes: notes
        )

        modelContext.insert(entry)
        assignEntryToCycle(entry, existingCycles: existingCycles, recentEntries: recentEntries)
        try modelContext.save()
        return entry.persistentModelID
    }

    /// Close the current cycle and start a new one (skipped period).
    func logSkippedPeriod(existingCycles: [Cycle]) throws {
        if let lastCycle = existingCycles.last, lastCycle.endDate == nil {
            lastCycle.endDate = Date()
            lastCycle.lengthDays = Calendar.current.dateComponents(
                [.day],
                from: lastCycle.startDate,
                to: Date()
            ).day
        }

        let newCycle = Cycle(startDate: Date(), isPredicted: false)
        modelContext.insert(newCycle)
        try modelContext.save()
    }

    // MARK: - Private

    private func assignEntryToCycle(
        _ entry: CycleEntry,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry]
    ) {
        if let currentCycle = existingCycles.last, currentCycle.endDate == nil {
            let lastPeriodEntry = recentEntries.last { $0.isPeriodDay }
            if let lastEntry = lastPeriodEntry {
                let daysSinceLastPeriod = Calendar.current.dateComponents(
                    [.day],
                    from: lastEntry.date,
                    to: entry.date
                ).day ?? 0

                if daysSinceLastPeriod > 10 {
                    // New period started — close old cycle, create new one
                    currentCycle.endDate = entry.date
                    currentCycle.lengthDays = Calendar.current.dateComponents(
                        [.day],
                        from: currentCycle.startDate,
                        to: entry.date
                    ).day

                    let newCycle = Cycle(startDate: entry.date)
                    modelContext.insert(newCycle)
                    entry.cycle = newCycle
                    return
                }
            }
            entry.cycle = currentCycle
        } else {
            let newCycle = Cycle(startDate: entry.date)
            modelContext.insert(newCycle)
            entry.cycle = newCycle
        }
    }
}
