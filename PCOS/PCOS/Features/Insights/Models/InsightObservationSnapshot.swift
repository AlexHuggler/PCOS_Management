import Foundation
import SwiftData

struct InsightObservationPoint: Identifiable {
    let date: Date
    let value: Double
    let recordCount: Int
    var id: Date { date }
}

struct InsightObservationSnapshot {
    let window: DateInterval
    let updatedAt: Date
    let symptoms: [InsightObservationPoint]
    let sleep: [InsightObservationPoint]
    let completedCycles: Int
    let sourceNames: [String]

    static var empty: Self {
        Self(window: InsightAnalysisPolicy.window(days: 14), updatedAt: Date(), symptoms: [], sleep: [], completedCycles: 0, sourceNames: [])
    }

    @MainActor
    static func load(context: ModelContext, now: Date = Date()) throws -> Self {
        let calendar = Calendar.current
        let symptoms = try context.fetch(FetchDescriptor<SymptomEntry>()).filter {
            InsightAnalysisPolicy.includes($0.date, days: 14, now: now)
        }
        let dailyLogs = try context.fetch(FetchDescriptor<DailyLog>()).filter {
            InsightAnalysisPolicy.includes($0.date, days: 14, now: now)
        }
        let sleep = dailyLogs.filter { $0.sleepHours != nil }
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).filter {
            !$0.isPredicted && ($0.lengthDays != nil || $0.manualCycleLengthOverrideDays != nil)
        }
        let imports = try context.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())
        let owners = try context.fetch(FetchDescriptor<HealthKitFieldOwnership>())
        let importedSleepIDs = Set(sleep.filter { log in
            owners.contains { $0.recordID == log.id && $0.field == "sleepHours" && !$0.isManual && $0.lastAppliedValue == log.sleepHours }
        }.map(\.id))
        let symptomByID = Dictionary(symptoms.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let contributingImports = imports.filter { sample in
            guard let id = sample.derivedRecordID else { return false }
            if sample.derivedRecordKind == .dailyLog {
                return sample.healthKitIdentifier == "HKCategoryTypeIdentifierSleepAnalysis"
                    && [1, 3, 4, 5].contains(sample.categoryValue ?? -1)
                    && importedSleepIDs.contains(id)
            }
            guard sample.derivedRecordKind == .symptomEntry, let symptom = symptomByID[id] else { return false }
            // Same fingerprint as HealthKitReconciler: manual edits are no longer
            // attributed to the original import as if it supplied the plotted value.
            let current = "\(symptom.date.timeIntervalSince1970)|\(symptom.symptomType)|\(symptom.severity)|\(symptom.notes ?? "")"
            return sample.lastAppliedFingerprint == current
        }
        let symptomPoints = InsightAnalysisPolicy.symptomObservations(symptoms: symptoms, dailyLogs: dailyLogs, now: now, calendar: calendar).map {
            InsightObservationPoint(date: $0.date, value: $0.value, recordCount: $0.recordCount)
        }
        let sleepPoints = Dictionary(grouping: sleep) { calendar.startOfDay(for: $0.date) }.map { date, entries in
            let values = entries.compactMap(\.sleepHours)
            return InsightObservationPoint(date: date, value: values.reduce(0, +) / Double(values.count), recordCount: values.count)
        }.sorted { $0.date < $1.date }
        return Self(window: InsightAnalysisPolicy.window(days: 14, now: now), updatedAt: now, symptoms: symptomPoints, sleep: sleepPoints, completedCycles: cycles.count, sourceNames: Array(Set(contributingImports.map(\.sourceLabel))).sorted())
    }
}
