import Foundation
import HealthKit
import SwiftData

/// A transaction stages raw changes, derived values, and cursors in one isolated context.
@MainActor
final class HealthKitReconciler {
    let context: ModelContext
    private let saveOverride: (() throws -> Void)?
    private let calendar: Calendar
    private var editableGeneratedCycleIDs = Set<UUID>()
    init(context: ModelContext, calendar: Calendar = .current, save: (() throws -> Void)? = nil) {
        self.context = context; self.calendar = calendar; self.saveOverride = save
        context.autosaveEnabled = false
    }

    func commit(_ batches: [HealthKitChangeBatch], now: Date) throws {
        do {
            editableGeneratedCycleIDs = []
            let cyclesBefore = try context.fetch(FetchDescriptor<Cycle>())
            for owner in try context.fetch(FetchDescriptor<HealthKitFieldOwnership>()) where owner.field == "__healthCycle" {
                guard let cycle = cyclesBefore.first(where: { $0.id == owner.recordID }) else { continue }
                if !owner.isManual, owner.lastAppliedFingerprint == generatedCycleFingerprint(cycle) {
                    editableGeneratedCycleIDs.insert(cycle.id)
                } else { owner.isManual = true }
            }
            var records = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
            var byUUID = Dictionary(records.map { ($0.sampleUUID, $0) }, uniquingKeysWith: { first, _ in first })
            for batch in batches {
                for uuid in batch.deletedUUIDs {
                    guard let record = byUUID[uuid], record.healthKitIdentifier == batch.identifier else { continue }
                    try removeDerived(record)
                    context.delete(record)
                    byUUID.removeValue(forKey: uuid)
                }
                for sample in batch.samples where sample.identifier == batch.identifier {
                    guard byUUID[sample.uuid] == nil else { continue }
                    let record = HealthKitImportedSampleRecord(sampleUUID: sample.uuid,
                        healthKitIdentifier: sample.identifier, sourceName: sample.source,
                        sourceBundleIdentifier: sample.sourceBundle, startDate: sample.start, endDate: sample.end,
                        valueDouble: sample.value, categoryValue: sample.categoryValue, importedAt: now)
                    context.insert(record); byUUID[sample.uuid] = record
                }
            }
            records = Array(byUUID.values).sorted {
                $0.startDate == $1.startDate ? $0.sampleUUID < $1.sampleUUID : $0.startDate < $1.startDate
            }
            try reconcileDaily(records)
            try reconcileGlucose(records)
            try reconcileNutrition(records, now: now)
            try reconcileCycleAndSymptoms(records)
            try reconcileGeneratedCycles()
            let cursors = try context.fetch(FetchDescriptor<HealthKitSyncCursor>())
            for batch in batches {
                let cursor = cursors.first { $0.identifier == batch.identifier }
                    ?? HealthKitSyncCursor(identifier: batch.identifier, windowStart: Self.initialStart(identifier: batch.identifier, now: now, calendar: calendar))
                if cursor.modelContext == nil { context.insert(cursor) }
                cursor.anchor = batch.anchor; cursor.committedAt = now
            }
            if let saveOverride { try saveOverride() } else { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }

    static func initialStart(identifier: String, now: Date, calendar: Calendar = .current) -> Date {
        let category = HealthKitDataTypeDescriptor.readDescriptors.first { $0.objectType?.identifier == identifier }?.category
        return calendar.date(byAdding: category == .cycle || category == .symptoms ? .month : .day,
                             value: category == .cycle || category == .symptoms ? -12 : -90, to: now) ?? now
    }

    static func sleepHours(_ intervals: [DateInterval]) -> Double {
        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return 0 }
        var seconds = 0.0
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else { seconds += current.duration; current = interval }
        }
        return (seconds + current.duration) / 3600
    }

    private func reconcileDaily(_ records: [HealthKitImportedSampleRecord]) throws {
        let fields: [String: String] = [HKQuantityTypeIdentifier.bodyMass.rawValue: "weight",
            HKCategoryTypeIdentifier.sleepAnalysis.rawValue: "sleepHours",
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue: "activeMinutes",
            HKQuantityTypeIdentifier.restingHeartRate.rawValue: "restingHeartRateBPM"]
        var logs = try context.fetch(FetchDescriptor<DailyLog>())
        var owners = try context.fetch(FetchDescriptor<HealthKitFieldOwnership>())
        let samples = records.filter { fields[$0.healthKitIdentifier] != nil }
        // Sleep stages belong to the session's waking day, including stages ending before midnight.
        let sleepSamples = samples.filter { $0.healthKitIdentifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue }
        var wakingDays: [String: Date] = [:]
        var session: [HealthKitImportedSampleRecord] = []
        var sessionEnd: Date?
        func finishSession() {
            guard let end = sessionEnd else { return }
            for sample in session { wakingDays[sample.sampleUUID] = calendar.startOfDay(for: end) }
        }
        for sample in sleepSamples.sorted(by: { $0.startDate < $1.startDate }) {
            if let end = sessionEnd, sample.startDate.timeIntervalSince(end) > 3 * 3600 {
                finishSession(); session = []; sessionEnd = nil
            }
            session.append(sample)
            sessionEnd = max(sessionEnd ?? sample.startDate, sample.endDate ?? sample.startDate)
        }
        finishSession()
        let grouped = Dictionary(grouping: samples) { record in
            wakingDays[record.sampleUUID] ?? calendar.startOfDay(for: record.startDate)
        }
        let ownedDates = logs.filter { log in owners.contains { $0.recordID == log.id && fields.values.contains($0.field) } }.map(\.date)
        for day in Set(grouped.keys).union(ownedDates.map { calendar.startOfDay(for: $0) }) {
            let daySamples = grouped[day] ?? []
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: day) } ?? DailyLog(date: day)
            if log.modelContext == nil { context.insert(log); logs.append(log) }
            for (identifier, field) in fields {
                let candidates = daySamples.filter { $0.healthKitIdentifier == identifier }
                let value: Double?
                if field == "sleepHours" {
                    let asleep = candidates.filter { [1,3,4,5].contains($0.categoryValue ?? -1) }
                    value = asleep.isEmpty ? nil : Self.sleepHours(asleep.map { DateInterval(start: $0.startDate, end: max($0.startDate, $0.endDate ?? $0.startDate)) })
                } else if field == "activeMinutes" {
                    // A single source avoids counting parallel phone/watch/app estimates twice.
                    let sources = Dictionary(grouping: candidates, by: { $0.sourceBundleIdentifier ?? $0.sourceName })
                    value = sources.values.map { $0.compactMap(\.valueDouble).reduce(0,+) }.max().map { $0.rounded() }
                } else { value = candidates.last?.valueDouble }
                let existing = owners.first { $0.recordID == log.id && $0.field == field }
                guard value != nil || existing != nil else { continue }
                let current = HealthKitFieldOwnership.value(field: field, log: log)
                let owner = existing ?? HealthKitFieldOwnership(recordID: log.id, field: field)
                if existing == nil {
                    owner.isManual = current != nil
                    context.insert(owner); owners.append(owner)
                } else if current != owner.lastAppliedValue { owner.isManual = true }
                owner.healthValue = value
                if !owner.isManual {
                    HealthKitFieldOwnership.set(value, field: field, log: log)
                    owner.lastAppliedValue = value
                }
                for sample in candidates { sample.derivedRecordKind = .dailyLog; sample.derivedRecordID = log.id }
            }
        }
    }

    private func reconcileGlucose(_ records: [HealthKitImportedSampleRecord]) throws {
        let existing = try context.fetch(FetchDescriptor<BloodSugarReading>())
        var claimedIDs = Set(records.compactMap(\.derivedRecordID))
        for record in records where record.healthKitIdentifier == HKQuantityTypeIdentifier.bloodGlucose.rawValue {
            guard record.derivedRecordID == nil, let value = record.valueDouble else { continue }
            // Claim each exact legacy imported tuple at most once. A second same-time UUID stays distinct.
            let row = existing.first { $0.fromHealthKit && $0.timestamp == record.startDate && $0.glucoseValue == value && $0.readingType == .random && $0.mealContext == nil && $0.notes == nil && !claimedIDs.contains($0.id) }
                ?? BloodSugarReading(timestamp: record.startDate, glucoseValue: value, readingType: .random, fromHealthKit: true)
            if row.modelContext == nil { context.insert(row) }
            claimedIDs.insert(row.id)
            record.derivedRecordKind = .bloodSugarReading; record.derivedRecordID = row.id
            record.lastAppliedFingerprint = glucoseFingerprint(row)
        }
    }

    private func reconcileNutrition(_ records: [HealthKitImportedSampleRecord], now: Date) throws {
        let metrics = Dictionary(uniqueKeysWithValues: HealthKitNutritionMetric.allCases.map { ($0.quantityIdentifier.rawValue, $0) })
        let allImports = try context.fetch(FetchDescriptor<NutritionImportRecord>())
        // Fixed source + time buckets are stable as late nutrients arrive or samples are deleted.
        let groups = Dictionary(grouping: records.filter { metrics[$0.healthKitIdentifier] != nil }) {
            "hk2|\($0.sourceBundleIdentifier ?? $0.sourceName)|\(Int(floor($0.startDate.timeIntervalSince1970 / 1800)))"
        }
        for old in allImports where old.sourceKind == .healthKit && old.externalIdentifier?.hasPrefix("hk2|") == true {
            if groups[old.externalIdentifier ?? ""] == nil && !old.userReviewed { context.delete(old) }
        }
        var claimedLegacyIDs = Set<UUID>()
        for (key, samples) in groups.sorted(by: { $0.key < $1.key }) {
            let linkedIDs = Set(samples.compactMap(\.derivedRecordID))
            let legacy = allImports.first { linkedIDs.contains($0.id) && !claimedLegacyIDs.contains($0.id) && $0.externalIdentifier?.hasPrefix("hk2|") != true }
            let row = allImports.first { $0.externalIdentifier == key } ?? legacy
                ?? NutritionImportRecord(sourceKind: .healthKit, sourceName: samples.first?.sourceName,
                                         externalIdentifier: key, startDate: samples.map(\.startDate).min() ?? now)
            if row.modelContext == nil { context.insert(row) }
            claimedLegacyIDs.insert(row.id)
            guard !row.userReviewed else { continue }
            row.externalIdentifier = key
            var values: [HealthKitNutritionMetric: Double] = [:]
            for sample in samples { if let metric = metrics[sample.healthKitIdentifier], let value = sample.valueDouble { values[metric, default: 0] += value } }
            row.calories = values[.dietaryEnergy]; row.carbsGrams = values[.carbohydrates]
            row.proteinGrams = values[.protein]; row.fatGrams = values[.totalFat]
            row.saturatedFatGrams = values[.saturatedFat]; row.fiberGrams = values[.fiber]
            row.sugarGrams = values[.sugar]; row.sodiumMg = values[.sodium]
            row.cholesterolMg = values[.cholesterol]; row.potassiumMg = values[.potassium]
            row.calciumMg = values[.calcium]; row.ironMg = values[.iron]
            row.waterOz = values[.water].map { $0 / 29.5735 }; row.endDate = samples.compactMap(\.endDate).max()
            row.importedAt = now
            for sample in samples { sample.derivedRecordKind = .nutritionImport; sample.derivedRecordID = row.id }
        }
    }

    private func reconcileCycleAndSymptoms(_ records: [HealthKitImportedSampleRecord]) throws {
        let service = CycleLogService(modelContext: context, saveChanges: false)
        let symptomMap: [String: SymptomType] = [
            HKCategoryTypeIdentifier.abdominalCramps.rawValue: .cramps,
            HKCategoryTypeIdentifier.pelvicPain.rawValue: .pelvicPain,
            HKCategoryTypeIdentifier.fatigue.rawValue: .fatigue,
            HKCategoryTypeIdentifier.bloating.rawValue: .bloating,
            HKCategoryTypeIdentifier.acne.rawValue: .acne,
            HKCategoryTypeIdentifier.hairLoss.rawValue: .shedding,
            HKCategoryTypeIdentifier.headache.rawValue: .headache,
            HKCategoryTypeIdentifier.moodChanges.rawValue: .moodSwings,
            HKCategoryTypeIdentifier.appetiteChanges.rawValue: .cravings,
            HKCategoryTypeIdentifier.sleepChanges.rawValue: .fatigue]
        let latestCycleSamples = Dictionary(grouping: records.filter { $0.healthKitIdentifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue }, by: { calendar.startOfDay(for: $0.startDate) }).compactMapValues { $0.last?.sampleUUID }
        for record in records {
            if record.healthKitIdentifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue {
                guard latestCycleSamples[calendar.startOfDay(for: record.startDate)] == record.sampleUUID else { continue }
                let entries = try context.fetch(FetchDescriptor<CycleEntry>())
                if let old = entries.first(where: { calendar.isDate($0.date, inSameDayAs: record.startDate) }) {
                    // An existing entry without an exact imported fingerprint belongs to the user.
                    let ownership = records.first { $0.derivedRecordID == old.id && $0.lastAppliedFingerprint == cycleFingerprint(old) }
                    guard ownership != nil else { continue }
                    let flow = menstrualFlow(record.categoryValue)
                    old.flowIntensity = flow
                    old.isPeriodDay = flow != .none
                    if flow == .none { old.cyclePhase = nil }
                    if flow != .none, old.cycle == nil {
                        let cyclesBefore = try context.fetch(FetchDescriptor<Cycle>())
                        let eligible = cyclesBefore.filter { $0.startDate <= record.startDate }
                        _ = try service.logPeriodDay(date: record.startDate, flowIntensity: flow, notes: nil,
                            existingCycles: eligible, recentEntries: entries)
                        for cycle in try context.fetch(FetchDescriptor<Cycle>()) where !cyclesBefore.contains(where: { $0.id == cycle.id }) {
                            context.insert(HealthKitFieldOwnership(recordID: cycle.id, field: "__healthCycle"))
                            editableGeneratedCycleIDs.insert(cycle.id)
                        }
                    }
                    record.derivedRecordID = old.id; record.derivedRecordKind = .cycleEntry
                    record.lastAppliedFingerprint = cycleFingerprint(old)
                    continue
                }
                let flow: FlowIntensity
                switch record.categoryValue {
                case HKCategoryValueMenstrualFlow.light.rawValue: flow = .light
                case HKCategoryValueMenstrualFlow.medium.rawValue: flow = .medium
                case HKCategoryValueMenstrualFlow.heavy.rawValue: flow = .heavy
                case HKCategoryValueMenstrualFlow.none.rawValue: continue
                default: flow = .spotting
                }
                let cycles = try context.fetch(FetchDescriptor<Cycle>())
                let protectedIDs = Set(try context.fetch(FetchDescriptor<HealthKitFieldOwnership>()).filter { $0.field == "__healthCycle" && $0.isManual }.map(\.recordID))
                let eligibleCycles = cycles.filter { calendar.startOfDay(for: $0.startDate) <= calendar.startOfDay(for: record.startDate) && !protectedIDs.contains($0.id) }
                let eligibleEntries = entries.filter { $0.date <= record.startDate }
                let decision = service.evaluatePeriodTransition(startDate: record.startDate, existingCycles: eligibleCycles, recentEntries: eligibleEntries)
                let result = try service.logPeriodDay(date: record.startDate, flowIntensity: flow, notes: nil,
                    existingCycles: eligibleCycles, recentEntries: eligibleEntries, startingNewCycle: decision.requiresConfirmation)
                record.derivedRecordKind = .cycleEntry; record.derivedRecordID = result.primaryEntryID
                if let entry = try context.fetch(FetchDescriptor<CycleEntry>()).first(where: { $0.id == result.primaryEntryID }) {
                    record.lastAppliedFingerprint = cycleFingerprint(entry)
                }
                for cycle in try context.fetch(FetchDescriptor<Cycle>()) where !cycles.contains(where: { $0.id == cycle.id }) {
                    context.insert(HealthKitFieldOwnership(recordID: cycle.id, field: "__healthCycle"))
                    editableGeneratedCycleIDs.insert(cycle.id)
                }
            } else if let type = symptomMap[record.healthKitIdentifier], record.derivedRecordID == nil {
                guard let category = record.categoryValue, category != HKCategoryValueSeverity.notPresent.rawValue else { continue }
                let severity = category == HKCategoryValueSeverity.mild.rawValue ? 2 : category == HKCategoryValueSeverity.severe.rawValue ? 5 : 3
                let entry = SymptomEntry(date: record.startDate, type: type, severity: severity, notes: nil)
                context.insert(entry); record.derivedRecordKind = .symptomEntry; record.derivedRecordID = entry.id
                record.lastAppliedFingerprint = symptomFingerprint(entry)
            } else {
                try reconcileOvulation(record, records: records)
                if HealthKitDataTypeDescriptor.readDescriptors.first(where: { $0.objectType?.identifier == record.healthKitIdentifier })?.category == .reproductiveContext {
                    record.derivedRecordKind = .sensitiveContext
                }
            }
        }
    }

    private func reconcileOvulation(_ record: HealthKitImportedSampleRecord, records: [HealthKitImportedSampleRecord]) throws {
        let ids = [HKQuantityTypeIdentifier.basalBodyTemperature.rawValue,
                   HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue, HKCategoryTypeIdentifier.ovulationTestResult.rawValue]
        guard ids.contains(record.healthKitIdentifier) else { return }
        let observations = try context.fetch(FetchDescriptor<OvulationObservation>())
        let row = observations.first { calendar.isDate($0.date, inSameDayAs: record.startDate) }
            ?? OvulationObservation(date: calendar.startOfDay(for: record.startDate))
        let current = ovulationFieldFingerprint(row, identifier: record.healthKitIdentifier)
        let owned = records.contains { $0.derivedRecordID == row.id && $0.healthKitIdentifier == record.healthKitIdentifier && $0.lastAppliedFingerprint == current }
        let populated: Bool
        switch record.healthKitIdentifier {
        case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue: populated = row.basalBodyTemperatureCelsius != nil
        case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue: populated = row.cervicalMucus != nil
        default: populated = row.lhTestResult != nil
        }
        guard !populated || owned else { return }
        switch record.healthKitIdentifier {
        case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue: row.basalBodyTemperatureCelsius = record.valueDouble
        case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue:
            switch record.categoryValue {
            case HKCategoryValueCervicalMucusQuality.dry.rawValue: row.cervicalMucus = .dry
            case HKCategoryValueCervicalMucusQuality.sticky.rawValue: row.cervicalMucus = .sticky
            case HKCategoryValueCervicalMucusQuality.creamy.rawValue: row.cervicalMucus = .creamy
            case HKCategoryValueCervicalMucusQuality.watery.rawValue: row.cervicalMucus = .watery
            case HKCategoryValueCervicalMucusQuality.eggWhite.rawValue: row.cervicalMucus = .eggWhite
            default: return
            }
        default:
            switch record.categoryValue {
            case HKCategoryValueOvulationTestResult.negative.rawValue: row.lhTestResult = .negative
            case HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue: row.lhTestResult = .peak
            case HKCategoryValueOvulationTestResult.estrogenSurge.rawValue: row.lhTestResult = .high
            default: return
            }
        }
        if row.modelContext == nil { context.insert(row) }
        record.derivedRecordID = row.id; record.derivedRecordKind = .ovulationObservation
        record.lastAppliedFingerprint = ovulationFieldFingerprint(row, identifier: record.healthKitIdentifier)
    }

    private func reconcileGeneratedCycles() throws {
        let owners = try context.fetch(FetchDescriptor<HealthKitFieldOwnership>()).filter { $0.field == "__healthCycle" }
        let entries = try context.fetch(FetchDescriptor<CycleEntry>())
        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        var removedIDs = Set<UUID>()
        for owner in owners where editableGeneratedCycleIDs.contains(owner.recordID) && !owner.isManual {
            guard let cycle = cycles.first(where: { $0.id == owner.recordID }) else { continue }
            let children = entries.filter { $0.cycle?.id == cycle.id }
            if !children.contains(where: \.isPeriodDay) {
                for entry in children { entry.cycle = nil }
                removedIDs.insert(cycle.id)
                context.delete(cycle); context.delete(owner)
            }
        }
        let survivingCycles = cycles.filter { !removedIDs.contains($0.id) }
        for owner in owners where editableGeneratedCycleIDs.contains(owner.recordID) && !owner.isManual && !removedIDs.contains(owner.recordID) {
            guard let cycle = survivingCycles.first(where: { $0.id == owner.recordID }) else { continue }
            let bleedingChildren = entries.filter { $0.cycle?.id == cycle.id && $0.isPeriodDay }
            if let first = bleedingChildren.map(\.date).min() { cycle.startDate = calendar.startOfDay(for: first) }
        }
        for owner in owners where editableGeneratedCycleIDs.contains(owner.recordID) && !owner.isManual && !removedIDs.contains(owner.recordID) {
            guard let cycle = survivingCycles.first(where: { $0.id == owner.recordID }) else { continue }
            let next = survivingCycles.filter { $0.id != cycle.id && $0.startDate > cycle.startDate }.map(\.startDate).min()
            cycle.endDate = next
            cycle.lengthDays = next.map { calendar.dateComponents([.day], from: cycle.startDate, to: $0).day ?? 0 }
            owner.lastAppliedFingerprint = generatedCycleFingerprint(cycle)
        }
    }

    private func removeDerived(_ record: HealthKitImportedSampleRecord) throws {
        guard let id = record.derivedRecordID, let fingerprint = record.lastAppliedFingerprint else { return }
        switch record.derivedRecordKind {
        case .bloodSugarReading:
            if let row = try context.fetch(FetchDescriptor<BloodSugarReading>()).first(where: { $0.id == id }), glucoseFingerprint(row) == fingerprint { context.delete(row) }
        case .cycleEntry:
            if let row = try context.fetch(FetchDescriptor<CycleEntry>()).first(where: { $0.id == id }), cycleFingerprint(row) == fingerprint { context.delete(row) }
        case .symptomEntry:
            if let row = try context.fetch(FetchDescriptor<SymptomEntry>()).first(where: { $0.id == id }), symptomFingerprint(row) == fingerprint { context.delete(row) }
        case .ovulationObservation:
            if let row = try context.fetch(FetchDescriptor<OvulationObservation>()).first(where: { $0.id == id }), ovulationFieldFingerprint(row, identifier: record.healthKitIdentifier) == fingerprint {
                switch record.healthKitIdentifier {
                case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue: row.basalBodyTemperatureCelsius = nil
                case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue: row.cervicalMucus = nil
                default: row.lhTestResult = nil
                }
                if row.basalBodyTemperatureCelsius == nil && row.cervicalMucus == nil && row.lhTestResult == nil && row.notes == nil { context.delete(row) }
            }
        default: break // Daily fields and nutrition groups are recomputed from remaining contributions.
        }
    }

    private func menstrualFlow(_ value: Int?) -> FlowIntensity {
        switch value {
        case HKCategoryValueMenstrualFlow.light.rawValue: .light
        case HKCategoryValueMenstrualFlow.medium.rawValue: .medium
        case HKCategoryValueMenstrualFlow.heavy.rawValue: .heavy
        case HKCategoryValueMenstrualFlow.none.rawValue: .none
        default: .spotting
        }
    }

    private func generatedCycleFingerprint(_ cycle: Cycle) -> String {
        "\(cycle.startDate.timeIntervalSince1970)|\(String(describing: cycle.endDate))|\(String(describing: cycle.lengthDays))|\(String(describing: cycle.manualCycleLengthOverrideDays))|\(cycle.ovulationStatus)|\(String(describing: cycle.endReason))|\(cycle.isPredicted)"
    }

    private func glucoseFingerprint(_ row: BloodSugarReading) -> String {
        "\(row.timestamp.timeIntervalSince1970)|\(row.glucoseValue)|\(row.readingType)|\(row.mealContext ?? "")|\(row.notes ?? "")|\(row.fromHealthKit)"
    }
    private func cycleFingerprint(_ row: CycleEntry) -> String {
        "\(row.date.timeIntervalSince1970)|\(String(describing: row.flowIntensity))|\(row.isPeriodDay)|\(row.notes ?? "")"
    }
    private func symptomFingerprint(_ row: SymptomEntry) -> String {
        "\(row.date.timeIntervalSince1970)|\(row.symptomType)|\(row.severity)|\(row.notes ?? "")"
    }
    private func ovulationFieldFingerprint(_ row: OvulationObservation, identifier: String) -> String {
        let value: String
        switch identifier {
        case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue: value = String(describing: row.basalBodyTemperatureCelsius)
        case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue: value = String(describing: row.cervicalMucus)
        default: value = String(describing: row.lhTestResult)
        }
        return "\(row.date.timeIntervalSince1970)|\(value)|\(row.notes ?? "")"
    }
}
