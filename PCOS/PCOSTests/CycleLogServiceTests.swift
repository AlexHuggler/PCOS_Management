import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Cycle Log Service", .serialized)
@MainActor
struct CycleLogServiceTests {
    @Test("Logging first period creates a new cycle")
    func firstPeriodCreatesCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        _ = try service.logPeriodDay(
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

    @Test("New-cycle gap requires confirmation before resetting")
    func gapRequiresConfirmation() throws {
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

        let decision = service.evaluatePeriodTransition(
            startDate: Date(),
            existingCycles: [existingCycle],
            recentEntries: [oldEntry]
        )

        switch decision {
        case .continueCurrentCycle:
            Issue.record("Expected new-cycle confirmation to be required")
        case .requiresNewCycleConfirmation(_, let gapDays):
            #expect(gapDays >= 15)
        }
    }

    @Test("Confirmed reset creates new cycle")
    func confirmedResetCreatesNewCycle() throws {
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

        _ = try service.logPeriodDay(
            date: Date(),
            flowIntensity: .light,
            notes: nil,
            existingCycles: [existingCycle],
            recentEntries: [oldEntry],
            startingNewCycle: true
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate)]))
        #expect(cycles.count == 2)
        #expect(cycles[0].endDate != nil)
        #expect(cycles[1].endDate == nil)
    }

    @Test("Logging period returns identifier for persisted entry")
    func logPeriodReturnsPersistedEntryIdentifier() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let result = try service.logPeriodDay(
            date: Date(),
            flowIntensity: .heavy,
            notes: "Test quick log",
            existingCycles: [],
            recentEntries: []
        )

        let entryID = try #require(result.primaryEntryID)
        let persistedEntry = try fetchEntry(id: entryID, in: context)
        #expect(persistedEntry?.isPeriodDay == true)
        #expect(persistedEntry?.flowIntensity == .heavy)
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

        _ = try service.logPeriodDay(
            date: Date(),
            flowIntensity: .medium,
            notes: nil,
            existingCycles: [existingCycle],
            recentEntries: [oldEntry]
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 1)
    }

    @Test("No-period day upserts a non-bleeding entry on the current cycle")
    func noPeriodDayUpsertsNonBleedingEntry() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let cycleStart = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let existingCycle = Cycle(startDate: cycleStart)
        context.insert(existingCycle)
        try context.save()

        let firstResult = try service.logNoPeriodDay(
            date: Date(),
            existingCycles: [existingCycle]
        )
        let secondResult = try service.logNoPeriodDay(
            date: Date(),
            existingCycles: [existingCycle]
        )

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        let entries = try context.fetch(FetchDescriptor<CycleEntry>())

        #expect(cycles.count == 1)
        #expect(entries.count == 1)
        #expect(entries.first?.flowIntensity == FlowIntensity.none)
        #expect(entries.first?.isPeriodDay == false)
        #expect(entries.first?.cycle === existingCycle)
        #expect(firstResult.savedDates.count == 1)
        #expect(secondResult.savedDates.count == 1)
    }

    @Test("No-period day is overwritten by a later bleeding log")
    func noPeriodDayCanBecomeBleedingEntry() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let cycleStart = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        let existingCycle = Cycle(startDate: cycleStart)
        context.insert(existingCycle)
        try context.save()

        _ = try service.logNoPeriodDay(date: Date(), existingCycles: [existingCycle])
        let noPeriodEntry = try #require(try context.fetch(FetchDescriptor<CycleEntry>()).first)

        _ = try service.logPeriodDay(
            date: Date(),
            flowIntensity: .medium,
            notes: "Bleeding started",
            existingCycles: [existingCycle],
            recentEntries: [noPeriodEntry]
        )

        let entries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.flowIntensity == .medium)
        #expect(entries.first?.isPeriodDay == true)
        #expect(entries.first?.notes == "Bleeding started")
    }

    @Test("No-period day does not create a cycle when no containing cycle exists")
    func noPeriodDayDoesNotCreateCycle() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let result = try service.logNoPeriodDay(
            date: Date(),
            existingCycles: []
        )

        #expect(result.savedDates.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).isEmpty)
    }

    @Test("Active period is inferred from recent contiguous bleeding days")
    func activePeriodIsInferredFromRecentBleedingRange() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let lastBleedingDate = calendar.date(byAdding: .day, value: 2, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        for offset in 0...2 {
            let entry = CycleEntry(
                date: calendar.date(byAdding: .day, value: offset, to: cycleStart)!,
                flowIntensity: offset == 0 ? .heavy : .medium,
                isPeriodDay: true,
                cyclePhase: .menstrual
            )
            entry.cycle = cycle
            context.insert(entry)
        }
        try context.save()

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let state = try #require(
            service.currentPeriodState(
                existingCycles: [cycle],
                entries: entries,
                referenceDate: today
            )
        )

        #expect(state.periodStartDate == cycleStart)
        #expect(state.lastBleedingDate == lastBleedingDate)
        #expect(state.suggestedEndDate == lastBleedingDate)
        #expect(state.isActive)
        #expect(state.periodEndedDate == nil)
    }

    @Test("Backdated period end creates no-period markers while keeping current cycle open")
    func backdatedPeriodEndCreatesNoPeriodMarkersAndKeepsCycleOpen() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let selectedEnd = calendar.date(byAdding: .day, value: 2, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        for offset in 0...2 {
            let entry = CycleEntry(
                date: calendar.date(byAdding: .day, value: offset, to: cycleStart)!,
                flowIntensity: .medium,
                isPeriodDay: true,
                cyclePhase: .menstrual
            )
            entry.cycle = cycle
            context.insert(entry)
        }
        try context.save()

        let result = try service.markPeriodEnded(
            on: selectedEnd,
            referenceDate: today,
            existingCycles: [cycle]
        )

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let bleedingDates = entries.filter(\.isPeriodDay).map { calendar.startOfDay(for: $0.date) }
        let noPeriodDates = entries.filter { !$0.isPeriodDay }.map { calendar.startOfDay(for: $0.date) }
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: selectedEnd)!

        #expect(cycle.endDate == nil)
        #expect(cycle.lengthDays == nil)
        #expect(bleedingDates == [cycleStart, calendar.date(byAdding: .day, value: 1, to: cycleStart)!, selectedEnd])
        #expect(noPeriodDates.contains(dayAfterEnd))
        #expect(noPeriodDates.contains(today))
        #expect(result.undoSnapshot != nil)

        let updatedState = try #require(
            service.currentPeriodState(
                existingCycles: [cycle],
                entries: entries,
                referenceDate: today
            )
        )
        #expect(!updatedState.isActive)
        #expect(updatedState.periodEndedDate == selectedEnd)
    }

    @Test("Earlier period end correction trims only later bleeding days in the active range")
    func earlierPeriodEndCorrectionTrimsLaterBleedingDays() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let selectedEnd = calendar.date(byAdding: .day, value: 2, to: cycleStart)!
        let trimmedDate = calendar.date(byAdding: .day, value: 3, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        for offset in 0...4 {
            let entry = CycleEntry(
                date: calendar.date(byAdding: .day, value: offset, to: cycleStart)!,
                flowIntensity: .medium,
                isPeriodDay: true,
                cyclePhase: .menstrual,
                notes: offset == 3 ? "Later bleeding note" : nil
            )
            entry.cycle = cycle
            context.insert(entry)
        }
        try context.save()

        _ = try service.markPeriodEnded(
            on: selectedEnd,
            referenceDate: today,
            existingCycles: [cycle]
        )

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let trimmedEntry = try #require(entries.first { calendar.isDate($0.date, inSameDayAs: trimmedDate) })
        #expect(trimmedEntry.flowIntensity == FlowIntensity.none)
        #expect(trimmedEntry.isPeriodDay == false)
        #expect(trimmedEntry.cyclePhase == nil)
        #expect(trimmedEntry.notes == nil)
        #expect(entries.filter(\.isPeriodDay).count == 3)
    }

    @Test("Later period end inserts missing bleeding days without overwriting existing notes")
    func laterPeriodEndInsertsMissingBleedingDaysWithoutOverwritingExistingNotes() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let existingSecondDay = calendar.date(byAdding: .day, value: 1, to: cycleStart)!
        let selectedEnd = calendar.date(byAdding: .day, value: 3, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        let firstEntry = CycleEntry(date: cycleStart, flowIntensity: .heavy, isPeriodDay: true, cyclePhase: .menstrual)
        firstEntry.cycle = cycle
        context.insert(firstEntry)
        let secondEntry = CycleEntry(date: existingSecondDay, flowIntensity: .light, isPeriodDay: true, cyclePhase: .menstrual, notes: "Keep this")
        secondEntry.cycle = cycle
        context.insert(secondEntry)
        try context.save()

        _ = try service.markPeriodEnded(
            on: selectedEnd,
            referenceDate: today,
            existingCycles: [cycle]
        )

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let existingEntry = try #require(entries.first { calendar.isDate($0.date, inSameDayAs: existingSecondDay) })
        let insertedEndEntry = try #require(entries.first { calendar.isDate($0.date, inSameDayAs: selectedEnd) })

        #expect(existingEntry.flowIntensity == .light)
        #expect(existingEntry.notes == "Keep this")
        #expect(insertedEndEntry.isPeriodDay)
        #expect(insertedEndEntry.flowIntensity == .light)
        #expect(entries.filter(\.isPeriodDay).count == 4)
    }

    @Test("Already ended period is inactive but keeps editable end date")
    func alreadyEndedPeriodIsInactiveWithEditableEndDate() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let selectedEnd = calendar.date(byAdding: .day, value: 2, to: cycleStart)!
        let noPeriodDate = calendar.date(byAdding: .day, value: 3, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        for offset in 0...2 {
            let entry = CycleEntry(
                date: calendar.date(byAdding: .day, value: offset, to: cycleStart)!,
                flowIntensity: .medium,
                isPeriodDay: true,
                cyclePhase: .menstrual
            )
            entry.cycle = cycle
            context.insert(entry)
        }
        let noPeriodEntry = CycleEntry(date: noPeriodDate, flowIntensity: FlowIntensity.none, isPeriodDay: false)
        noPeriodEntry.cycle = cycle
        context.insert(noPeriodEntry)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let state = try #require(
            service.currentPeriodState(
                existingCycles: [cycle],
                entries: entries,
                referenceDate: today
            )
        )

        #expect(!state.isActive)
        #expect(state.periodEndedDate == selectedEnd)
        #expect(state.suggestedEndDate == selectedEnd)
    }

    @Test("Range save upserts contiguous days without duplicating entries")
    func rangeSaveUpsertsContiguousDays() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let startDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let existingCycle = Cycle(startDate: startDate)
        context.insert(existingCycle)

        let existingEntryDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        let existingEntry = CycleEntry(date: existingEntryDate, flowIntensity: .spotting, isPeriodDay: false, notes: "Old")
        existingEntry.cycle = existingCycle
        context.insert(existingEntry)
        try context.save()

        _ = try service.logPeriodRange(
            startDate: startDate,
            endDate: Date(),
            flowIntensity: .medium,
            notes: "Backfilled",
            existingCycles: [existingCycle],
            recentEntries: [existingEntry]
        )

        let entries = try context.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        #expect(entries.count == 3)
        #expect(entries.filter { $0.isPeriodDay }.count == 3)
        #expect(entries.filter { Calendar.current.isDate($0.date, inSameDayAs: existingEntryDate) }.count == 1)
        #expect(entries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: existingEntryDate) })?.notes == "Backfilled")
    }

    @Test("Range undo restores prior state")
    func rangeUndoRestoresPriorState() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = CycleLogService(modelContext: context)

        let originalStartDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let existingCycle = Cycle(startDate: originalStartDate)
        context.insert(existingCycle)

        let originalEntry = CycleEntry(date: Date(), flowIntensity: .spotting, isPeriodDay: false, notes: "Original")
        originalEntry.cycle = existingCycle
        context.insert(originalEntry)
        try context.save()

        let result = try service.logPeriodRange(
            startDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            endDate: Date(),
            flowIntensity: .heavy,
            notes: "Range",
            existingCycles: [existingCycle],
            recentEntries: [originalEntry]
        )

        let undoSnapshot = try #require(result.undoSnapshot)
        try service.undoSave(using: undoSnapshot)

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        let entries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(cycles.count == 1)
        #expect(cycles.first?.startDate == originalStartDate)
        #expect(entries.count == 1)
        #expect(entries.first?.isPeriodDay == false)
        #expect(entries.first?.notes == "Original")
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

        #expect(existingCycle.endDate != nil)
        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(cycles.count == 2)
    }

    @Test("View model cycle day stays based on cycle start after marking period ended")
    func viewModelCycleDayStaysBasedOnCycleStartAfterPeriodEnd() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let cycleStart = calendar.date(byAdding: .day, value: -8, to: today)!
        let selectedEnd = calendar.date(byAdding: .day, value: 2, to: cycleStart)!
        let cycle = Cycle(startDate: cycleStart)
        context.insert(cycle)

        for offset in 0...2 {
            let entry = CycleEntry(
                date: calendar.date(byAdding: .day, value: offset, to: cycleStart)!,
                flowIntensity: .medium,
                isPeriodDay: true,
                cyclePhase: .menstrual
            )
            entry.cycle = cycle
            context.insert(entry)
        }
        try context.save()

        let viewModel = CycleViewModel(modelContext: context)
        viewModel.loadData(referenceDate: today)
        _ = try viewModel.markPeriodEnded(on: selectedEnd, referenceDate: today)

        #expect(viewModel.currentCycleDayCount(on: today) == 9)
        #expect(viewModel.currentPeriodState?.isActive == false)
        #expect(viewModel.currentPeriodState?.periodEndedDate == selectedEnd)
    }
}

private extension CycleLogServiceTests {
    func fetchEntry(id: UUID, in context: ModelContext) throws -> CycleEntry? {
        try context.fetch(FetchDescriptor<CycleEntry>()).first(where: { $0.id == id })
    }
}
