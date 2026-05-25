import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Symptom ViewModel", .serialized)
@MainActor
struct SymptomViewModelTests {
    @Test("Setting severity to 0 removes the symptom")
    func zeroSeverityRemoves() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(3, for: .fatigue)
        #expect(vm.severity(for: .fatigue) == 3)
        #expect(vm.selectionCount == 1)

        vm.setSeverity(0, for: .fatigue)
        #expect(vm.severity(for: .fatigue) == 0)
        #expect(vm.selectionCount == 0)
    }

    @Test("Severity clamped to 1-5 range")
    func severityClamped() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(10, for: .bloating)
        #expect(vm.severity(for: .bloating) == 5)

        vm.setSeverity(-1, for: .cramps)
        #expect(vm.severity(for: .cramps) == 1)
    }

    @Test("Reset clears all state")
    func resetClearsState() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        vm.setSeverity(3, for: .fatigue)
        vm.setSeverity(2, for: .bloating)
        vm.selectedCategory = .physical

        vm.reset()

        #expect(vm.selectionCount == 0)
        #expect(vm.selectedCategory == nil)
        #expect(!vm.hasSelections)
    }

    @Test("hasSelections is true when symptoms are logged")
    func hasSelectionsReflectsState() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        #expect(!vm.hasSelections)
        vm.setSeverity(2, for: .headache)
        #expect(vm.hasSelections)
    }

    @Test("Visible symptom types filter by category")
    func visibleSymptomTypesFilter() throws {
        let container = try TestHelpers.makeModelContainer()
        let vm = SymptomViewModel(modelContext: container.mainContext)

        // All types when no category
        let allCount = vm.visibleSymptomTypes.count
        #expect(allCount == SymptomType.allCases.count)

        // Filtered by physical
        vm.selectedCategory = .physical
        let physicalTypes = vm.visibleSymptomTypes
        #expect(physicalTypes.count == SymptomCategory.physical.symptomTypes.count)
        for type in physicalTypes {
            #expect(type.category == .physical)
        }
    }

    @Test("Fetch today's symptoms returns deterministic sorted order")
    func fetchTodaysSymptomsDeterministicOrder() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let startOfDay = Calendar.current.startOfDay(for: Date())

        let entries = [
            SymptomEntry(date: startOfDay.addingTimeInterval(9 * 3600), type: .hunger, severity: 2),
            SymptomEntry(date: startOfDay.addingTimeInterval(10 * 3600), type: .anxious, severity: 3),
            SymptomEntry(date: startOfDay.addingTimeInterval(12 * 3600), type: .acne, severity: 1),
            SymptomEntry(date: startOfDay.addingTimeInterval(8 * 3600), type: .acne, severity: 4),
            SymptomEntry(date: startOfDay.addingTimeInterval(11 * 3600), type: .bloating, severity: 2),
        ]

        for entry in entries {
            context.insert(entry)
        }
        try context.save()

        let vm = SymptomViewModel(modelContext: context)
        let fetched = vm.fetchTodaysSymptoms()

        #expect(fetched.count == 5)
        #expect(fetched.map(\.symptomType) == [.hunger, .anxious, .acne, .acne, .bloating])

        let acneEntries = fetched.filter { $0.symptomType == .acne }
        #expect(acneEntries.count == 2)
        #expect(acneEntries[0].date < acneEntries[1].date)
    }

    @Test("Reload supporting data caches yesterday count and suggested symptoms")
    func reloadSupportingDataCachesSupportState() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
        let twoDaysAgo = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))

        let entries = [
            SymptomEntry(date: yesterday.addingTimeInterval(8 * 3600), type: .fatigue, severity: 2),
            SymptomEntry(date: yesterday.addingTimeInterval(10 * 3600), type: .headache, severity: 1),
            SymptomEntry(date: twoDaysAgo.addingTimeInterval(9 * 3600), type: .fatigue, severity: 4),
            SymptomEntry(date: startOfToday.addingTimeInterval(7 * 3600), type: .fatigue, severity: 3),
            SymptomEntry(date: startOfToday.addingTimeInterval(11 * 3600), type: .acne, severity: 2),
        ]

        for entry in entries {
            context.insert(entry)
        }
        try context.save()

        let vm = SymptomViewModel(modelContext: context)
        vm.reloadSupportingData()

        #expect(vm.yesterdaySymptomCount == 2)
        #expect(vm.suggestedSymptoms.first == .fatigue)
        #expect(vm.suggestedSymptoms.contains(.headache))
        #expect(vm.suggestedSymptoms.contains(.acne))
    }

    @Test("Copy yesterday uses cached supporting data")
    func copyYesterdaysSymptomsUsesCachedData() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))

        let entries = [
            SymptomEntry(
                date: yesterday.addingTimeInterval(8 * 3600),
                type: .fatigue,
                severity: 2,
                notes: "Low energy"
            ),
            SymptomEntry(date: yesterday.addingTimeInterval(9 * 3600), type: .bloating, severity: 4),
        ]

        for entry in entries {
            context.insert(entry)
        }
        try context.save()

        let vm = SymptomViewModel(modelContext: context)
        vm.reloadSupportingData()
        vm.copyYesterdaysSymptoms()

        #expect(vm.selectionCount == 2)
        #expect(vm.severity(for: .fatigue) == 2)
        #expect(vm.severity(for: .bloating) == 4)
        #expect(vm.symptomNotes[.fatigue] == "Low energy")
    }

    @Test("Saving symptoms refreshes cached suggestions")
    func saveSymptomsRefreshesCachedSuggestions() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let vm = SymptomViewModel(modelContext: context)

        vm.setSeverity(3, for: .fatigue)
        try vm.saveSymptoms()

        #expect(vm.selectionCount == 0)
        #expect(vm.fetchTodaysSymptoms().count == 1)
        #expect(vm.suggestedSymptoms.first == .fatigue)
    }

    @Test("Same-day symptom saves do not reset the current cycle count")
    func sameDaySymptomSaveDoesNotResetCurrentCycleCount() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let calendar = Calendar.current
        let cycleLogService = CycleLogService(modelContext: context)
        let cycleQueryService = CycleQueryService(modelContext: context)

        let cycleStart = try #require(calendar.date(byAdding: .day, value: -3, to: Date()))
        let normalizedCycleStart = calendar.startOfDay(for: cycleStart)
        let existingCycle = Cycle(startDate: normalizedCycleStart)
        context.insert(existingCycle)

        let initialPeriodEntry = CycleEntry(
            date: normalizedCycleStart,
            flowIntensity: .medium,
            isPeriodDay: true,
            cyclePhase: .menstrual
        )
        initialPeriodEntry.cycle = existingCycle
        context.insert(initialPeriodEntry)
        try context.save()

        let logDate = Date()
        let beforeDayCount = try #require(
            calendar.dateComponents(
                [.day],
                from: normalizedCycleStart,
                to: calendar.startOfDay(for: logDate)
            ).day
        ) + 1

        _ = try cycleLogService.logPeriodDay(
            date: logDate,
            flowIntensity: .light,
            notes: "Same cycle period day",
            existingCycles: [existingCycle],
            recentEntries: [initialPeriodEntry]
        )

        let preSymptomCycles = try cycleQueryService.fetchCycles()
        let preSymptomCurrentCycle = try #require(preSymptomCycles.last)
        let symptomViewModel = SymptomViewModel(modelContext: context)
        symptomViewModel.logDate = logDate
        symptomViewModel.setSeverity(3, for: .fatigue)
        try symptomViewModel.saveSymptoms()

        let postSymptomCycles = try cycleQueryService.fetchCycles()
        #expect(postSymptomCycles.count == 1)

        let postSymptomCurrentCycle = try #require(postSymptomCycles.last)
        #expect(postSymptomCurrentCycle.id == preSymptomCurrentCycle.id)
        #expect(calendar.isDate(postSymptomCurrentCycle.startDate, inSameDayAs: normalizedCycleStart))

        let afterDayCount = try #require(
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: postSymptomCurrentCycle.startDate),
                to: calendar.startOfDay(for: logDate)
            ).day
        ) + 1
        #expect(afterDayCount == beforeDayCount)

        let currentCycleEntries = try cycleQueryService.fetchCurrentCycleEntries(referenceDate: logDate)
        #expect(currentCycleEntries.contains(where: {
            calendar.isDate($0.date, inSameDayAs: logDate) && $0.isPeriodDay
        }))
    }
}
