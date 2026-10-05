import Foundation
import HealthKit
import SwiftData
import Testing
@testable import PCOS

@MainActor
struct HealthKitReconciliationTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: DailyLog.self, HealthKitImportedSampleRecord.self, HealthKitSyncCursor.self,
                           HealthKitFieldOwnership.self, BloodSugarReading.self, NutritionImportRecord.self,
                           Cycle.self, CycleEntry.self, SymptomEntry.self, OvulationObservation.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func sample(_ uuid: String, value: Double = 60, date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> HealthKitSampleChange {
        HealthKitSampleChange(uuid: uuid, identifier: HKQuantityTypeIdentifier.bodyMass.rawValue,
                              start: date, end: date, value: value, categoryValue: nil,
                              source: "Test", sourceBundle: "test.source")
    }

    @Test func duplicateUUIDDoesNotDuplicateAndManualCorrectionSurvivesDeletion() throws {
        let store = try container()
        let context = ModelContext(store)
        let engine = HealthKitReconciler(context: context)
        let s = sample("same")
        try engine.commit([HealthKitChangeBatch(identifier: s.identifier, samples: [s, s], deletedUUIDs: [], anchor: Data([1]))], now: s.end)
        #expect(try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>()).count == 1)
        let log = try #require(context.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(log.weight == 60)
        log.weight = 65
        try context.save()
        try engine.commit([HealthKitChangeBatch(identifier: s.identifier, samples: [], deletedUUIDs: [s.uuid], anchor: Data([2]))], now: s.end)
        #expect(log.weight == 65)
        #expect(try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>()).isEmpty)
    }

    @Test func emptyBatchPreservesImportedValueAndDeletionClearsOwnedValue() throws {
        let store = try container(); let context = ModelContext(store)
        let engine = HealthKitReconciler(context: context); let s = sample("a")
        try engine.commit([.init(identifier: s.identifier, samples: [s], deletedUUIDs: [], anchor: Data([1]))], now: s.end)
        try engine.commit([.init(identifier: s.identifier, samples: [], deletedUUIDs: [], anchor: Data([2]))], now: s.end)
        let log = try #require(context.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(log.weight == 60)
        try engine.commit([.init(identifier: s.identifier, samples: [], deletedUUIDs: [s.uuid], anchor: Data([3]))], now: s.end)
        #expect(log.weight == nil)
    }

    @Test func legacyValueIsManualAndCanExplicitlyReturnToHealth() throws {
        let store = try container(); let context = ModelContext(store); let s = sample("a")
        let log = DailyLog(date: Calendar.current.startOfDay(for: s.start), weight: 70)
        context.insert(log); try context.save()
        try HealthKitReconciler(context: context).commit([.init(identifier: s.identifier, samples: [s], deletedUUIDs: [], anchor: Data())], now: s.end)
        #expect(log.weight == 70)
        try HealthKitFieldOwnership.useAppleHealth(log: log, field: "weight", context: context)
        #expect(log.weight == 60)
    }

    @Test func failedSaveDoesNotAdvanceCursor() throws {
        let store = try container(); let context = ModelContext(store); let s = sample("a")
        enum Failure: Error { case simulated }
        let engine = HealthKitReconciler(context: context, save: { throw Failure.simulated })
        #expect(throws: Failure.self) {
            try engine.commit([.init(identifier: s.identifier, samples: [s], deletedUUIDs: [], anchor: Data([1]))], now: s.end)
        }
        #expect(try context.fetch(FetchDescriptor<HealthKitSyncCursor>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }

    @Test func sleepUnionHandlesOverlapAndDSTElapsedTime() {
        let start = Date(timeIntervalSince1970: 1_730_610_000)
        let intervals = [DateInterval(start: start, duration: 9 * 3600),
                         DateInterval(start: start.addingTimeInterval(3600), duration: 6 * 3600)]
        #expect(HealthKitReconciler.sleepHours(intervals) == 9)
    }

    @Test func differentGlucoseUUIDsAtSameTimestampSurvive() throws {
        let store = try container(); let context = ModelContext(store)
        var a = sample("a", value: 100); a.identifier = HKQuantityTypeIdentifier.bloodGlucose.rawValue
        var b = a; b.uuid = "b"; b.value = 110
        try HealthKitReconciler(context: context).commit([.init(identifier: a.identifier, samples: [a,b], deletedUUIDs: [], anchor: Data())], now: a.end)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == 2)
    }
    @Test func nutritionLateNutrientAndDeletionReconcileOneStableRow() throws {
        let store = try container(); let context = ModelContext(store)
        let engine = HealthKitReconciler(context: context)
        var energy = sample("energy", value: 400)
        energy.identifier = HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue
        var protein = sample("protein", value: 20)
        protein.identifier = HKQuantityTypeIdentifier.dietaryProtein.rawValue
        try engine.commit([.init(identifier: energy.identifier, samples: [energy], deletedUUIDs: [], anchor: Data())], now: energy.end)
        let initialID = try #require(context.fetch(FetchDescriptor<NutritionImportRecord>()).first?.id)
        try engine.commit([.init(identifier: protein.identifier, samples: [protein], deletedUUIDs: [], anchor: Data())], now: energy.end)
        let rows = try context.fetch(FetchDescriptor<NutritionImportRecord>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == initialID)
        #expect(rows.first?.calories == 400)
        #expect(rows.first?.proteinGrams == 20)
        try engine.commit([.init(identifier: protein.identifier, samples: [], deletedUUIDs: [protein.uuid], anchor: Data())], now: energy.end)
        #expect(rows.first?.proteinGrams == nil)
        #expect(rows.first?.calories == 400)
    }

    @Test func separatedPeriodGroupsCreateRealCycleRelationships() throws {
        let store = try container(); let context = ModelContext(store)
        let engine = HealthKitReconciler(context: context)
        var a = sample("period1"); a.identifier = HKCategoryTypeIdentifier.menstrualFlow.rawValue
        a.value = nil; a.categoryValue = HKCategoryValueMenstrualFlow.medium.rawValue
        var b = a; b.uuid = "period2"
        b.start = Calendar.current.date(byAdding: .day, value: 30, to: a.start)!
        b.end = b.start
        let batch = HealthKitChangeBatch(identifier: a.identifier, samples: [a,b], deletedUUIDs: [], anchor: Data([1]))
        try engine.commit([batch], now: b.end)
        try engine.commit([batch], now: b.end)
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).sorted { $0.startDate < $1.startDate }
        let entries = try context.fetch(FetchDescriptor<CycleEntry>())
        #expect(cycles.count == 2)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.cycle != nil })
        #expect(cycles.first?.lengthDays == 30)
        try engine.commit([.init(identifier: b.identifier, samples: [], deletedUUIDs: [b.uuid], anchor: Data([2]))], now: b.end)
        let surviving = try context.fetch(FetchDescriptor<Cycle>())
        #expect(surviving.count == 1)
        #expect(surviving.first?.endDate == nil)
        #expect(surviving.first?.lengthDays == nil)
    }

    @Test func sleepUsesWakingDayAcrossFallDSTAndUnionsWatchStages() throws {
        let store = try container(); let context = ModelContext(store)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let start = calendar.date(from: DateComponents(year: 2024, month: 11, day: 2, hour: 22))!
        let end = calendar.date(from: DateComponents(year: 2024, month: 11, day: 3, hour: 7))!
        var sleep = sample("sleep"); sleep.identifier = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        sleep.start = start; sleep.end = end; sleep.value = nil
        sleep.categoryValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        var stage = sleep; stage.uuid = "stage"; stage.start = start.addingTimeInterval(3600)
        stage.categoryValue = HKCategoryValueSleepAnalysis.asleepCore.rawValue
        try HealthKitReconciler(context: context, calendar: calendar).commit([.init(identifier: sleep.identifier, samples: [sleep, stage], deletedUUIDs: [], anchor: Data())], now: end)
        let log = try #require(context.fetch(FetchDescriptor<DailyLog>()).first)
        #expect(calendar.component(.day, from: log.date) == 3)
        #expect(log.sleepHours == 10)
    }

    @Test func manualFlagProtectsSameValueCorrectionAndClear() throws {
        let store = try container(); let context = ModelContext(store); let a = sample("weight")
        let engine = HealthKitReconciler(context: context)
        try engine.commit([.init(identifier: a.identifier, samples: [a], deletedUUIDs: [], anchor: Data())], now: a.end)
        let log = try #require(context.fetch(FetchDescriptor<DailyLog>()).first)
        try HealthKitFieldOwnership.markManual(log: log, fields: ["weight"], context: context)
        log.weight = nil
        try context.save()
        var b = a; b.uuid = "weight2"; b.start = a.start.addingTimeInterval(60); b.end = b.start; b.value = 61
        try engine.commit([.init(identifier: a.identifier, samples: [b], deletedUUIDs: [], anchor: Data())], now: b.end)
        #expect(log.weight == nil)
    }

    @Test func initialWindowsAndDefaultReadTypesAreLimited() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cycleStart = HealthKitReconciler.initialStart(identifier: HKCategoryTypeIdentifier.menstrualFlow.rawValue, now: now)
        let glucoseStart = HealthKitReconciler.initialStart(identifier: HKQuantityTypeIdentifier.bloodGlucose.rawValue, now: now)
        #expect(Calendar.current.dateComponents([.month], from: cycleStart, to: now).month == 12)
        #expect(Calendar.current.dateComponents([.day], from: glucoseStart, to: now).day == 90)
        let ids = Set(HealthKitDataTypeDescriptor.defaultReadTypes.map(\.identifier))
        #expect(!ids.contains(HKQuantityTypeIdentifier.bodyMass.rawValue))
        #expect(!ids.contains(HKCategoryTypeIdentifier.sexualActivity.rawValue))
        #expect(!HealthKitDataTypeDescriptor.readDescriptors.contains { $0.id == "height" || $0.id == "workouts" || $0.id == "date_of_birth" })
    }

    @Test func preMidnightStagesBelongToSessionWakingDay() throws {
        let store = try container(); let context = ModelContext(store)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 22))!
        var first = sample("early"); first.identifier = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        first.start = start; first.end = start.addingTimeInterval(3600)
        first.categoryValue = HKCategoryValueSleepAnalysis.asleepCore.rawValue; first.value = nil
        var second = first; second.uuid = "late"; second.start = first.end.addingTimeInterval(600)
        second.end = start.addingTimeInterval(9 * 3600)
        try HealthKitReconciler(context: context, calendar: calendar).commit([.init(identifier: first.identifier, samples: [first,second], deletedUUIDs: [], anchor: Data())], now: second.end)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs.first.map { calendar.component(.day, from: $0.date) } == 2)
        #expect(abs((logs.first?.sleepHours ?? 0) - (9 - 1.0 / 6)) < 0.001)
    }

    @Test func newerFlowAndNoneReplaceImportedDayWithoutPhantomCycle() throws {
        let store = try container(); let context = ModelContext(store); let engine = HealthKitReconciler(context: context)
        var a = sample("flow1"); a.identifier = HKCategoryTypeIdentifier.menstrualFlow.rawValue
        a.value = nil; a.categoryValue = HKCategoryValueMenstrualFlow.light.rawValue
        try engine.commit([.init(identifier: a.identifier, samples: [a], deletedUUIDs: [], anchor: Data())], now: a.end)
        var b = a; b.uuid = "flow2"; b.start = a.start.addingTimeInterval(60); b.end = b.start
        b.categoryValue = HKCategoryValueMenstrualFlow.heavy.rawValue
        try engine.commit([.init(identifier: a.identifier, samples: [b], deletedUUIDs: [], anchor: Data())], now: b.end)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).first?.flowIntensity == .heavy)
        var c = b; c.uuid = "flow3"; c.start = b.start.addingTimeInterval(60); c.end = c.start
        c.categoryValue = HKCategoryValueMenstrualFlow.none.rawValue
        try engine.commit([.init(identifier: a.identifier, samples: [c], deletedUUIDs: [], anchor: Data())], now: c.end)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).first?.isPeriodDay == false)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).isEmpty)
        var d = c; d.uuid = "flow4"; d.start = c.start.addingTimeInterval(60); d.end = d.start
        d.categoryValue = HKCategoryValueMenstrualFlow.heavy.rawValue
        try engine.commit([.init(identifier: a.identifier, samples: [d], deletedUUIDs: [], anchor: Data())], now: d.end)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).first?.cycle != nil)
    }

    @Test func generatedCyclePregnancyClosureAndManualEditsSurviveDeletion() throws {
        let store = try container(); let context = ModelContext(store); let engine = HealthKitReconciler(context: context)
        var a = sample("flow"); a.identifier = HKCategoryTypeIdentifier.menstrualFlow.rawValue
        a.value = nil; a.categoryValue = HKCategoryValueMenstrualFlow.light.rawValue
        try engine.commit([.init(identifier: a.identifier, samples: [a], deletedUUIDs: [], anchor: Data())], now: a.end)
        let cycle = try #require(context.fetch(FetchDescriptor<Cycle>()).first)
        let closure = a.end.addingTimeInterval(10 * 86400)
        cycle.endDate = closure; cycle.endReason = .pregnancy; cycle.manualCycleLengthOverrideDays = 42
        try context.save()
        try engine.commit([.init(identifier: a.identifier, samples: [], deletedUUIDs: [a.uuid], anchor: Data())], now: closure)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(cycle.endDate == closure)
        #expect(cycle.endReason == .pregnancy)
        #expect(cycle.manualCycleLengthOverrideDays == 42)
    }

    @Test func legacyGlucoseClaimIsUniqueAndPreservesEditedLegacyRows() throws {
        let store = try container(); let context = ModelContext(store)
        var a = sample("glucose1", value: 100); a.identifier = HKQuantityTypeIdentifier.bloodGlucose.rawValue
        let old = BloodSugarReading(timestamp: a.start, glucoseValue: 100, readingType: .random, fromHealthKit: true)
        let edited = BloodSugarReading(timestamp: a.start, glucoseValue: 100, readingType: .beforeMeal, fromHealthKit: true, notes: "My correction")
        context.insert(old); context.insert(edited); try context.save()
        var b = a; b.uuid = "glucose2"
        try HealthKitReconciler(context: context).commit([.init(identifier: a.identifier, samples: [a,b], deletedUUIDs: [], anchor: Data())], now: a.end)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == 3)
        let provenance = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
        #expect(provenance.contains { $0.derivedRecordID == old.id })
        #expect(!provenance.contains { $0.derivedRecordID == edited.id })
    }

    @Test func failedReturnToHealthRollsBackManualValueAndOwnership() throws {
        let store = try container(); let context = ModelContext(store); let a = sample("weight")
        let log = DailyLog(date: Calendar.current.startOfDay(for: a.start), weight: 70)
        context.insert(log); try context.save()
        try HealthKitReconciler(context: context).commit([.init(identifier: a.identifier, samples: [a], deletedUUIDs: [], anchor: Data())], now: a.end)
        enum Failure: Error { case save }
        #expect(throws: Failure.self) {
            try HealthKitFieldOwnership.useAppleHealth(log: log, field: "weight", context: context, save: { throw Failure.save })
        }
        #expect(log.weight == 70)
        #expect(try context.fetch(FetchDescriptor<HealthKitFieldOwnership>()).first?.isManual == true)
    }

}

private actor HealthSyncGate {
    private var calls = 0
    private var blocked: CheckedContinuation<Void, Never>?
    func enter() async {
        calls += 1
        if calls == 1 { await withCheckedContinuation { blocked = $0 } }
    }
    func waitUntilEntered() async {
        while blocked == nil { await Task.yield() }
    }
    func release() { blocked?.resume(); blocked = nil }
    func count() -> Int { calls }
}

@MainActor
struct HealthKitSyncLifecycleTests {
    @Test func overlappingUpdateDrainsAnotherPassAndInvalidatesInsights() async throws {
        let container = try TestHelpers.makeModelContainer()
        let gate = HealthSyncGate()
        let previousRefresh = InsightRefreshCoordinator.needsRefresh()
        defer { if !previousRefresh { InsightRefreshCoordinator.clear() } }
        InsightRefreshCoordinator.clear()
        let manager = HealthKitManager(availabilityProvider: { true }, syncOperation: { _, now in
            await gate.enter()
            return HealthKitSyncResult(syncedAt: now, didUpdateDailyLog: true, insertedGlucoseCount: 0)
        })
        manager.enabledCategories = [.cycle]
        let first = Task { await manager.performFullSync(modelContext: container.mainContext) }
        await gate.waitUntilEntered()
        let second = Task { await manager.performFullSync(modelContext: container.mainContext) }
        await Task.yield()
        await gate.release()
        await first.value; await second.value
        #expect(await gate.count() == 2)
        #expect(InsightRefreshCoordinator.needsRefresh())
        #expect(!manager.isSyncing)
    }

    @Test func suspendedSyncCannotPublishSuccessOrReenableCategories() async throws {
        let container = try TestHelpers.makeModelContainer(); let gate = HealthSyncGate()
        let previous = HealthKitCategorySelection.enabled
        defer { HealthKitCategorySelection.enabled = previous }
        let manager = HealthKitManager(availabilityProvider: { true }, syncOperation: { _, now in
            await gate.enter()
            return HealthKitSyncResult(syncedAt: now, didUpdateDailyLog: true, insertedGlucoseCount: 0)
        })
        manager.enabledCategories = [.cycle]
        let before = manager.lastSyncDate
        let task = Task { await manager.performFullSync(modelContext: container.mainContext) }
        await gate.waitUntilEntered()
        manager.suspendSync(disableCategories: true)
        await gate.release(); await task.value
        #expect(manager.enabledCategories.isEmpty)
        #expect(manager.lastSyncDate == before)
        #expect(!manager.isSyncing)
    }
}
