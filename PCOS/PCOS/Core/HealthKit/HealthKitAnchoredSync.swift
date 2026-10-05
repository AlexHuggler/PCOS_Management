import Foundation
import HealthKit
import SwiftData

@MainActor
enum HealthKitCategorySelection {
    static let key = "healthkit.enabledCategories.v2"
    static var enabled: Set<HealthKitDataTypeDescriptor.Category> {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: key) else { return [.cycle, .symptoms] }
            return Set(raw.compactMap(HealthKitDataTypeDescriptor.Category.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: key) }
    }
    static var descriptors: [HealthKitDataTypeDescriptor] {
        HealthKitDataTypeDescriptor.readDescriptors.filter { enabled.contains($0.category) }
    }
}

@MainActor
final class HealthKitAnchoredSync {
    private let store: HKHealthStore
    init(store: HKHealthStore) { self.store = store }

    func sync(container: ModelContainer, now: Date) async throws -> HealthKitSyncResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let cursors = try context.fetch(FetchDescriptor<HealthKitSyncCursor>())
        var batches: [HealthKitChangeBatch] = []
        for descriptor in HealthKitCategorySelection.descriptors {
            guard let type = descriptor.objectType as? HKSampleType else { continue }
            let cursor = cursors.first { $0.identifier == type.identifier }
            let start = cursor?.windowStart ?? HealthKitReconciler.initialStart(identifier: type.identifier, now: now)
            let anchor: HKQueryAnchor?
            if let data = cursor?.anchor {
                anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            } else { anchor = nil }
            batches.append(try await fetch(type: type, start: start, anchor: anchor))
        }
        try Task.checkCancellation()
        try HealthKitReconciler(context: context).commit(batches, now: now)
        return HealthKitSyncResult(syncedAt: now, didUpdateDailyLog: batches.contains { !$0.samples.isEmpty || !$0.deletedUUIDs.isEmpty },
            insertedGlucoseCount: batches.filter { $0.identifier == HKQuantityTypeIdentifier.bloodGlucose.rawValue }.reduce(0) { $0 + $1.samples.count },
            insertedProvenanceCount: batches.reduce(0) { $0 + $1.samples.count })
    }

    private func fetch(type: HKSampleType, start: Date, anchor: HKQueryAnchor?) async throws -> HealthKitChangeBatch {
        let identifier = type.identifier
        let unitInfo = Self.unit(for: identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate),
                anchor: anchor, limit: HKObjectQueryNoLimit) { _, additions, deletions, next, error in
                if let error { continuation.resume(throwing: error); return }
                guard let next else {
                    continuation.resume(throwing: NSError(domain: "CycleBalance.HealthKit", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Apple Health did not return a sync cursor."]))
                    return
                }
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true)
                    let samples = (additions ?? []).map { sample in
                        let quantity = sample as? HKQuantitySample
                        let value = unitInfo.flatMap { unit, multiplier in quantity.map { $0.quantity.doubleValue(for: unit) * multiplier } }
                        return HealthKitSampleChange(uuid: sample.uuid.uuidString, identifier: identifier,
                            start: sample.startDate, end: sample.endDate, value: value,
                            categoryValue: (sample as? HKCategorySample)?.value,
                            source: sample.sourceRevision.source.name, sourceBundle: sample.sourceRevision.source.bundleIdentifier)
                    }
                    continuation.resume(returning: HealthKitChangeBatch(identifier: identifier, samples: samples,
                        deletedUUIDs: (deletions ?? []).map { $0.uuid.uuidString }, anchor: data))
                } catch { continuation.resume(throwing: error) }
            }
            store.execute(query)
        }
    }

    nonisolated private static func unit(for identifier: String) -> (HKUnit, Double)? {
        if let metric = HealthKitNutritionMetric.allCases.first(where: { $0.quantityIdentifier.rawValue == identifier }) {
            return (metric.unit, metric.storedValueMultiplier)
        }
        switch identifier {
        case HKQuantityTypeIdentifier.bodyMass.rawValue: return (.gramUnit(with: .kilo), 1)
        case HKQuantityTypeIdentifier.bloodGlucose.rawValue: return (HKUnit(from: "mg/dL"), 1)
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue: return (.minute(), 1)
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue, HKQuantityTypeIdentifier.heartRate.rawValue:
            return (.count().unitDivided(by: .minute()), 1)
        case HKQuantityTypeIdentifier.basalBodyTemperature.rawValue, HKQuantityTypeIdentifier.bodyTemperature.rawValue: return (.degreeCelsius(), 1)
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue: return (.kilocalorie(), 1)
        case HKQuantityTypeIdentifier.stepCount.rawValue: return (.count(), 1)
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue: return (.meter(), 1)
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue: return (.secondUnit(with: .milli), 1)
        case HKQuantityTypeIdentifier.electrodermalActivity.rawValue: return (.siemenUnit(with: .micro), 1)
        default: return nil
        }
    }
}
