import Foundation
import SwiftData

enum CycleTransitionDecision: Equatable {
    case continueCurrentCycle
    case requiresNewCycleConfirmation(startDate: Date, gapDays: Int)

    var requiresConfirmation: Bool {
        if case .requiresNewCycleConfirmation = self {
            return true
        }
        return false
    }
}

struct CycleRangeSaveResult {
    let primaryEntryID: UUID?
    let savedDates: [Date]
    let undoSnapshot: CycleLogUndoSnapshot?
}

struct CycleLogUndoSnapshot {
    fileprivate struct CycleSnapshot {
        let id: UUID
        let startDate: Date
        let endDate: Date?
        let lengthDays: Int?
        let isPredicted: Bool
        let manualCycleLengthOverrideDays: Int?
        let ovulationStatus: OvulationStatus
        let endReason: CycleEndReason?
    }

    fileprivate struct CycleEntrySnapshot {
        let id: UUID
        let date: Date
        let flowIntensity: FlowIntensity?
        let isPeriodDay: Bool
        let cyclePhase: CyclePhase?
        let notes: String?
        let createdAt: Date
        let cycleID: UUID?
    }

    fileprivate var insertedCycleIDs: [UUID] = []
    fileprivate var insertedEntryIDs: [UUID] = []
    fileprivate var cycleSnapshots: [UUID: CycleSnapshot] = [:]
    fileprivate var entrySnapshots: [UUID: CycleEntrySnapshot] = [:]

    var hasChanges: Bool {
        !insertedCycleIDs.isEmpty || !insertedEntryIDs.isEmpty || !cycleSnapshots.isEmpty || !entrySnapshots.isEmpty
    }

    fileprivate mutating func recordInserted(cycle: Cycle) {
        insertedCycleIDs.append(cycle.id)
    }

    fileprivate mutating func recordInserted(entry: CycleEntry) {
        insertedEntryIDs.append(entry.id)
    }

    fileprivate mutating func snapshot(_ cycle: Cycle) {
        guard cycleSnapshots[cycle.id] == nil else { return }
        cycleSnapshots[cycle.id] = CycleSnapshot(
            id: cycle.id,
            startDate: cycle.startDate,
            endDate: cycle.endDate,
            lengthDays: cycle.lengthDays,
            isPredicted: cycle.isPredicted,
            manualCycleLengthOverrideDays: cycle.manualCycleLengthOverrideDays,
            ovulationStatus: cycle.ovulationStatus,
            endReason: cycle.endReason
        )
    }

    fileprivate mutating func snapshot(_ entry: CycleEntry) {
        guard entrySnapshots[entry.id] == nil else { return }
        entrySnapshots[entry.id] = CycleEntrySnapshot(
            id: entry.id,
            date: entry.date,
            flowIntensity: entry.flowIntensity,
            isPeriodDay: entry.isPeriodDay,
            cyclePhase: entry.cyclePhase,
            notes: entry.notes,
            createdAt: entry.createdAt,
            cycleID: entry.cycle?.id
        )
    }
}

/// Handles all write operations for cycle/period data: inserting entries,
/// managing cycle boundaries, and persisting to SwiftData.
@MainActor
struct CycleLogService {
    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func evaluatePeriodTransition(
        startDate: Date,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry]
    ) -> CycleTransitionDecision {
        let normalizedStartDate = normalized(startDate)

        guard let currentCycle = currentOpenCycle(in: existingCycles) else {
            return .continueCurrentCycle
        }

        let currentCycleStart = normalized(currentCycle.startDate)
        if normalizedStartDate <= currentCycleStart {
            return .continueCurrentCycle
        }

        guard let lastPeriodEntry = recentEntries
            .filter(\.isPeriodDay)
            .sorted(by: { $0.date < $1.date })
            .last
        else {
            return .continueCurrentCycle
        }

        let gapDays = calendar.dateComponents(
            [.day],
            from: normalized(lastPeriodEntry.date),
            to: normalizedStartDate
        ).day ?? 0

        if gapDays > 10 {
            return .requiresNewCycleConfirmation(startDate: normalizedStartDate, gapDays: gapDays)
        }

        return .continueCurrentCycle
    }

    @discardableResult
    func logPeriodDay(
        date: Date,
        flowIntensity: FlowIntensity,
        notes: String?,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry],
        startingNewCycle: Bool = false
    ) throws -> CycleRangeSaveResult {
        try logPeriodRange(
            startDate: date,
            endDate: date,
            flowIntensity: flowIntensity,
            notes: notes,
            existingCycles: existingCycles,
            recentEntries: recentEntries,
            startingNewCycle: startingNewCycle
        )
    }

    @discardableResult
    func logNoPeriodDay(
        date: Date,
        existingCycles: [Cycle]
    ) throws -> CycleRangeSaveResult {
        let normalizedDate = normalized(date)
        let sortedCycles = existingCycles.sorted(by: { $0.startDate < $1.startDate })
        let openCycle = currentOpenCycle(in: sortedCycles)
        let fallbackCycle = openCycle.flatMap { normalizedDate >= normalized($0.startDate) ? $0 : nil }

        guard let targetCycle = cycleContaining(normalizedDate, in: sortedCycles) ?? fallbackCycle else {
            return CycleRangeSaveResult(primaryEntryID: nil, savedDates: [], undoSnapshot: nil)
        }

        let existingEntries = try fetchEntries(from: normalizedDate, through: normalizedDate)
        var undoSnapshot = CycleLogUndoSnapshot()
        let entry: CycleEntry

        if let existingEntry = existingEntries.first(where: { normalized($0.date) == normalizedDate }) {
            undoSnapshot.snapshot(existingEntry)
            entry = existingEntry
            entry.date = normalizedDate
            entry.flowIntensity = FlowIntensity.none
            entry.isPeriodDay = false
            entry.cyclePhase = nil
            entry.notes = nil
        } else {
            entry = CycleEntry(
                date: normalizedDate,
                flowIntensity: FlowIntensity.none,
                isPeriodDay: false,
                cyclePhase: nil,
                notes: nil
            )
            modelContext.insert(entry)
            undoSnapshot.recordInserted(entry: entry)
        }

        if entry.cycle?.id != targetCycle.id {
            undoSnapshot.snapshot(entry)
            entry.cycle = targetCycle
        }

        try modelContext.save()
        InsightRefreshCoordinator.invalidate()

        return CycleRangeSaveResult(
            primaryEntryID: entry.id,
            savedDates: [normalizedDate],
            undoSnapshot: undoSnapshot.hasChanges ? undoSnapshot : nil
        )
    }

    @discardableResult
    func stagePeriodDay(
        date: Date,
        flowIntensity: FlowIntensity,
        notes: String?,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry]
    ) throws -> CycleEntry {
        let normalizedDate = normalized(date)
        let startNewCycle: Bool
        switch evaluatePeriodTransition(
            startDate: normalizedDate,
            existingCycles: existingCycles,
            recentEntries: recentEntries
        ) {
        case .continueCurrentCycle:
            startNewCycle = false
        case .requiresNewCycleConfirmation:
            // Imports are explicit historical data, so staged import backfills can
            // safely materialize the new cycle without an extra UI confirmation step.
            startNewCycle = true
        }

        var undoSnapshot = CycleLogUndoSnapshot()
        let targetCycle = try prepareTargetCycle(
            earliestDate: normalizedDate,
            existingCycles: existingCycles,
            startingNewCycle: startNewCycle,
            undoSnapshot: &undoSnapshot
        )

        let existingEntries = try fetchEntries(from: normalizedDate, through: normalizedDate)
        if let existingEntry = existingEntries.first(where: { normalized($0.date) == normalizedDate }) {
            existingEntry.date = normalizedDate
            existingEntry.flowIntensity = flowIntensity
            existingEntry.isPeriodDay = true
            existingEntry.cyclePhase = .menstrual
            existingEntry.notes = sanitizedNotes(notes)
            existingEntry.cycle = targetCycle
            return existingEntry
        }

        let entry = CycleEntry(
            date: normalizedDate,
            flowIntensity: flowIntensity,
            isPeriodDay: true,
            cyclePhase: .menstrual,
            notes: sanitizedNotes(notes)
        )
        modelContext.insert(entry)
        entry.cycle = targetCycle
        return entry
    }

    @discardableResult
    func logPeriodRange(
        startDate: Date,
        endDate: Date,
        flowIntensity: FlowIntensity,
        notes: String?,
        existingCycles: [Cycle],
        recentEntries: [CycleEntry],
        startingNewCycle: Bool = false
    ) throws -> CycleRangeSaveResult {
        let resolvedStartDate = normalized(min(startDate, endDate))
        let resolvedEndDate = normalized(max(startDate, endDate))

        if !startingNewCycle {
            let decision = evaluatePeriodTransition(
                startDate: resolvedStartDate,
                existingCycles: existingCycles,
                recentEntries: recentEntries
            )
            if case .requiresNewCycleConfirmation = decision {
                throw CycleLoggingError.newCycleConfirmationRequired
            }
        }

        let selectedDates = dates(from: resolvedStartDate, through: resolvedEndDate)
        let existingEntries = try fetchEntries(from: resolvedStartDate, through: resolvedEndDate)
        let existingEntriesByDate = Dictionary(
            existingEntries.map { (normalized($0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var undoSnapshot = CycleLogUndoSnapshot()
        let targetCycle = try prepareTargetCycle(
            earliestDate: resolvedStartDate,
            existingCycles: existingCycles,
            startingNewCycle: startingNewCycle,
            undoSnapshot: &undoSnapshot
        )

        var savedEntryIDs: [UUID] = []
        let trimmedNotes = sanitizedNotes(notes)

        for selectedDate in selectedDates {
            let entry: CycleEntry

            if let existingEntry = existingEntriesByDate[selectedDate] {
                undoSnapshot.snapshot(existingEntry)
                entry = existingEntry
                entry.date = selectedDate
                entry.flowIntensity = flowIntensity
                entry.isPeriodDay = true
                entry.cyclePhase = .menstrual
                entry.notes = trimmedNotes
            } else {
                entry = CycleEntry(
                    date: selectedDate,
                    flowIntensity: flowIntensity,
                    isPeriodDay: true,
                    cyclePhase: .menstrual,
                    notes: trimmedNotes
                )
                modelContext.insert(entry)
                undoSnapshot.recordInserted(entry: entry)
            }

            if entry.cycle?.id != targetCycle.id {
                if existingEntriesByDate[selectedDate] != nil {
                    undoSnapshot.snapshot(entry)
                }
                entry.cycle = targetCycle
            }

            savedEntryIDs.append(entry.id)
        }

        try modelContext.save()
        InsightRefreshCoordinator.invalidate()

        return CycleRangeSaveResult(
            primaryEntryID: savedEntryIDs.first,
            savedDates: selectedDates,
            undoSnapshot: undoSnapshot.hasChanges ? undoSnapshot : nil
        )
    }

    func undoSave(using snapshot: CycleLogUndoSnapshot) throws {
        let insertedEntries = try fetchEntries(withIDs: snapshot.insertedEntryIDs)
        for entry in insertedEntries {
            modelContext.delete(entry)
        }

        let insertedCycles = try fetchCycles(withIDs: snapshot.insertedCycleIDs)
        for cycle in insertedCycles {
            modelContext.delete(cycle)
        }

        let existingCycles = try fetchCycles(withIDs: Array(snapshot.cycleSnapshots.keys))
        let cyclesByID = Dictionary(existingCycles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for cycleSnapshot in snapshot.cycleSnapshots.values {
            let cycle = cyclesByID[cycleSnapshot.id] ?? Cycle(
                id: cycleSnapshot.id,
                startDate: cycleSnapshot.startDate,
                endDate: cycleSnapshot.endDate,
                lengthDays: cycleSnapshot.lengthDays,
                isPredicted: cycleSnapshot.isPredicted,
                manualCycleLengthOverrideDays: cycleSnapshot.manualCycleLengthOverrideDays,
                ovulationStatus: cycleSnapshot.ovulationStatus,
                endReason: cycleSnapshot.endReason
            )
            if cyclesByID[cycleSnapshot.id] == nil {
                modelContext.insert(cycle)
            }
            cycle.startDate = cycleSnapshot.startDate
            cycle.endDate = cycleSnapshot.endDate
            cycle.lengthDays = cycleSnapshot.lengthDays
            cycle.isPredicted = cycleSnapshot.isPredicted
            cycle.manualCycleLengthOverrideDays = cycleSnapshot.manualCycleLengthOverrideDays
            cycle.ovulationStatus = cycleSnapshot.ovulationStatus
            cycle.endReason = cycleSnapshot.endReason
        }

        let restoredCycles = try fetchCycles(withIDs: Array(snapshot.cycleSnapshots.keys))
        let restoredCyclesByID = Dictionary(restoredCycles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingEntries = try fetchEntries(withIDs: Array(snapshot.entrySnapshots.keys))
        let entriesByID = Dictionary(existingEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for entrySnapshot in snapshot.entrySnapshots.values {
            let entry = entriesByID[entrySnapshot.id] ?? CycleEntry(
                id: entrySnapshot.id,
                date: entrySnapshot.date,
                flowIntensity: entrySnapshot.flowIntensity,
                isPeriodDay: entrySnapshot.isPeriodDay,
                cyclePhase: entrySnapshot.cyclePhase,
                notes: entrySnapshot.notes,
                createdAt: entrySnapshot.createdAt
            )
            if entriesByID[entrySnapshot.id] == nil {
                modelContext.insert(entry)
            }
            entry.date = entrySnapshot.date
            entry.flowIntensity = entrySnapshot.flowIntensity
            entry.isPeriodDay = entrySnapshot.isPeriodDay
            entry.cyclePhase = entrySnapshot.cyclePhase
            entry.notes = entrySnapshot.notes
            entry.createdAt = entrySnapshot.createdAt
            entry.cycle = entrySnapshot.cycleID.flatMap { restoredCyclesByID[$0] }
        }

        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
    }

    /// Close the current cycle and start a new one (skipped period).
    func logSkippedPeriod(existingCycles: [Cycle]) throws {
        if let lastCycle = existingCycles.last, lastCycle.endDate == nil {
            lastCycle.endDate = Date()
            lastCycle.lengthDays = calendar.dateComponents(
                [.day],
                from: lastCycle.startDate,
                to: Date()
            ).day
        }

        let newCycle = Cycle(startDate: Date(), isPredicted: false)
        modelContext.insert(newCycle)
        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
    }
}

extension CycleLogService {
    enum CycleLoggingError: LocalizedError {
        case newCycleConfirmationRequired

        var errorDescription: String? {
            switch self {
            case .newCycleConfirmationRequired:
                return L10n.string(
                    "Please confirm before starting a new cycle.",
                    defaultValue: "Please confirm before starting a new cycle."
                )
            }
        }
    }
}

private extension CycleLogService {
    func prepareTargetCycle(
        earliestDate: Date,
        existingCycles: [Cycle],
        startingNewCycle: Bool,
        undoSnapshot: inout CycleLogUndoSnapshot
    ) throws -> Cycle {
        let sortedCycles = existingCycles.sorted(by: { $0.startDate < $1.startDate })

        if startingNewCycle {
            if let currentCycle = currentOpenCycle(in: sortedCycles) {
                let currentCycleID = currentCycle.id
                undoSnapshot.snapshot(currentCycle)
                currentCycle.endDate = earliestDate
                currentCycle.lengthDays = cycleLengthDays(from: currentCycle.startDate, to: earliestDate)

                let futureEntries = try fetchEntries(startingFrom: earliestDate)
                for entry in futureEntries where entry.cycle?.id == currentCycleID {
                    undoSnapshot.snapshot(entry)
                }

                let newCycle = Cycle(startDate: earliestDate, isPredicted: false)
                modelContext.insert(newCycle)
                undoSnapshot.recordInserted(cycle: newCycle)

                for entry in futureEntries where entry.cycle?.id == currentCycleID {
                    entry.cycle = newCycle
                }

                return newCycle
            }

            let newCycle = Cycle(startDate: earliestDate, isPredicted: false)
            modelContext.insert(newCycle)
            undoSnapshot.recordInserted(cycle: newCycle)
            return newCycle
        }

        if let currentCycle = currentOpenCycle(in: sortedCycles) {
            let normalizedCurrentStart = normalized(currentCycle.startDate)
            if earliestDate < normalizedCurrentStart {
                undoSnapshot.snapshot(currentCycle)
                currentCycle.startDate = earliestDate

                if let previousCycle = previousCycle(before: currentCycle, in: sortedCycles) {
                    undoSnapshot.snapshot(previousCycle)
                    previousCycle.endDate = earliestDate
                    previousCycle.lengthDays = cycleLengthDays(from: previousCycle.startDate, to: earliestDate)
                }
            }

            return currentCycle
        }

        if let containingCycle = cycleContaining(earliestDate, in: sortedCycles) {
            return containingCycle
        }

        let newCycle = Cycle(startDate: earliestDate, isPredicted: false)
        modelContext.insert(newCycle)
        undoSnapshot.recordInserted(cycle: newCycle)
        return newCycle
    }

    func currentOpenCycle(in cycles: [Cycle]) -> Cycle? {
        cycles.sorted(by: { $0.startDate < $1.startDate }).last { $0.endDate == nil }
    }

    func previousCycle(before cycle: Cycle, in cycles: [Cycle]) -> Cycle? {
        let sortedCycles = cycles.sorted(by: { $0.startDate < $1.startDate })
        guard let index = sortedCycles.firstIndex(where: { $0.id == cycle.id }), index > 0 else {
            return nil
        }
        return sortedCycles[index - 1]
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

    func fetchEntries(from startDate: Date, through endDate: Date) throws -> [CycleEntry] {
        let inclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startDate && entry.date < inclusiveEnd
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchEntries(startingFrom startDate: Date) throws -> [CycleEntry] {
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startDate
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchEntries(withIDs ids: [UUID]) throws -> [CycleEntry] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CycleEntry>()
        return try modelContext.fetch(descriptor).filter { ids.contains($0.id) }
    }

    func fetchCycles(withIDs ids: [UUID]) throws -> [Cycle] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Cycle>()
        return try modelContext.fetch(descriptor).filter { ids.contains($0.id) }
    }

    func dates(from startDate: Date, through endDate: Date) -> [Date] {
        var dates: [Date] = []
        var currentDate = startDate

        while currentDate <= endDate {
            dates.append(currentDate)
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                break
            }
            currentDate = nextDate
        }

        return dates
    }

    func cycleLengthDays(from startDate: Date, to endDate: Date) -> Int? {
        calendar.dateComponents(
            [.day],
            from: normalized(startDate),
            to: normalized(endDate)
        ).day
    }

    func normalized(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func sanitizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
