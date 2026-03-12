import Foundation
import HealthKit
import SwiftData
import os

protocol HealthKitSyncPerforming {
    func performFullSync(using modelContainer: ModelContainer, now: Date) async throws -> HealthKitSyncResult
}

struct HealthKitSyncResult: Sendable {
    let syncedAt: Date
    let didUpdateDailyLog: Bool
    let insertedGlucoseCount: Int
}

actor HealthKitSyncWorker: HealthKitSyncPerforming {
    typealias AvailabilityProvider = @Sendable () -> Bool
    typealias WeightFetcher = @Sendable (Date) async throws -> Double?
    typealias SleepHoursFetcher = @Sendable (Date) async throws -> Double?
    typealias ActiveMinutesFetcher = @Sendable (Date) async throws -> Int?
    typealias GlucoseReadingsFetcher = @Sendable (Date, Date) async throws -> [(date: Date, value: Double)]

    private let healthStore: HKHealthStore
    private let availabilityProvider: AvailabilityProvider

    private let weightFetcherOverride: WeightFetcher?
    private let sleepHoursFetcherOverride: SleepHoursFetcher?
    private let activeMinutesFetcherOverride: ActiveMinutesFetcher?
    private let glucoseReadingsFetcherOverride: GlucoseReadingsFetcher?

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        availabilityProvider: @escaping AvailabilityProvider = { HKHealthStore.isHealthDataAvailable() },
        weightFetcher: WeightFetcher? = nil,
        sleepHoursFetcher: SleepHoursFetcher? = nil,
        activeMinutesFetcher: ActiveMinutesFetcher? = nil,
        glucoseReadingsFetcher: GlucoseReadingsFetcher? = nil
    ) {
        self.healthStore = healthStore
        self.availabilityProvider = availabilityProvider
        self.weightFetcherOverride = weightFetcher
        self.sleepHoursFetcherOverride = sleepHoursFetcher
        self.activeMinutesFetcherOverride = activeMinutesFetcher
        self.glucoseReadingsFetcherOverride = glucoseReadingsFetcher
    }

    func performFullSync(using modelContainer: ModelContainer, now: Date) async throws -> HealthKitSyncResult {
        guard availabilityProvider() else {
            Logger.database.notice("HealthKit full sync skipped because HealthKit is unavailable")
            return HealthKitSyncResult(syncedAt: now, didUpdateDailyLog: false, insertedGlucoseCount: 0)
        }

        let workerContext = ModelContext(modelContainer)
        let calendar = Calendar.current
        let didUpdateDailyLog = try await syncDailyLog(date: now, modelContext: workerContext)

        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) else {
            return HealthKitSyncResult(
                syncedAt: now,
                didUpdateDailyLog: didUpdateDailyLog,
                insertedGlucoseCount: 0
            )
        }

        let insertedGlucoseCount = try await syncGlucoseReadings(
            from: sevenDaysAgo,
            to: now,
            modelContext: workerContext
        )

        return HealthKitSyncResult(
            syncedAt: now,
            didUpdateDailyLog: didUpdateDailyLog,
            insertedGlucoseCount: insertedGlucoseCount
        )
    }

    // MARK: - Sync Methods

    private func syncDailyLog(date: Date, modelContext: ModelContext) async throws -> Bool {
        let weight = try await resolveWeight(for: date)
        let sleepHours = try await resolveSleepHours(for: date)
        let activeMinutes = try await resolveActiveMinutes(for: date)

        guard weight != nil || sleepHours != nil || activeMinutes != nil else {
            return false
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return false
        }

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { log in
                log.date >= startOfDay && log.date < endOfDay
            }
        )

        let existingLogs = try modelContext.fetch(descriptor)

        if let existing = existingLogs.first {
            var didMutate = false
            if let weight {
                existing.weight = weight
                didMutate = true
            }
            if let sleepHours {
                existing.sleepHours = sleepHours
                didMutate = true
            }
            if let activeMinutes {
                existing.activeMinutes = activeMinutes
                didMutate = true
            }

            guard didMutate else {
                return false
            }

            try modelContext.save()
            Logger.database.info("Synced DailyLog for \(date.formatted(.dateTime.month().day()))")
            return true
        }

        let newLog = DailyLog(
            date: startOfDay,
            weight: weight,
            sleepHours: sleepHours,
            activeMinutes: activeMinutes
        )
        modelContext.insert(newLog)
        try modelContext.save()

        Logger.database.info("Synced DailyLog for \(date.formatted(.dateTime.month().day()))")
        return true
    }

    private func syncGlucoseReadings(
        from startDate: Date,
        to endDate: Date,
        modelContext: ModelContext
    ) async throws -> Int {
        let readings = try await resolveGlucoseReadings(from: startDate, to: endDate)
        guard !readings.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<BloodSugarReading>(
            predicate: #Predicate<BloodSugarReading> { reading in
                reading.fromHealthKit == true
                    && reading.timestamp >= startDate
                    && reading.timestamp < endDate
            }
        )
        let existingReadings = try modelContext.fetch(descriptor)

        let existingTimestamps = Set(existingReadings.map { reading in
            Int(reading.timestamp.timeIntervalSince1970)
        })

        var insertedCount = 0

        for reading in readings {
            let timestampKey = Int(reading.date.timeIntervalSince1970)
            guard !existingTimestamps.contains(timestampKey) else {
                continue
            }

            let bloodSugarReading = BloodSugarReading(
                timestamp: reading.date,
                glucoseValue: reading.value,
                readingType: .random,
                fromHealthKit: true
            )
            modelContext.insert(bloodSugarReading)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        Logger.database.info("Synced \(insertedCount) glucose reading(s) from HealthKit")
        return insertedCount
    }

    // MARK: - Fetch Resolution

    private func resolveWeight(for date: Date) async throws -> Double? {
        if let weightFetcherOverride {
            return try await weightFetcherOverride(date)
        }
        return try await fetchWeight(for: date)
    }

    private func resolveSleepHours(for date: Date) async throws -> Double? {
        if let sleepHoursFetcherOverride {
            return try await sleepHoursFetcherOverride(date)
        }
        return try await fetchSleepHours(for: date)
    }

    private func resolveActiveMinutes(for date: Date) async throws -> Int? {
        if let activeMinutesFetcherOverride {
            return try await activeMinutesFetcherOverride(date)
        }
        return try await fetchActiveMinutes(for: date)
    }

    private func resolveGlucoseReadings(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [(date: Date, value: Double)] {
        if let glucoseReadingsFetcherOverride {
            return try await glucoseReadingsFetcherOverride(startDate, endDate)
        }
        return try await fetchGlucoseReadings(from: startDate, to: endDate)
    }

    // MARK: - HealthKit Fetches

    private func fetchWeight(for date: Date) async throws -> Double? {
        guard availabilityProvider() else { return nil }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: kg)
            }
            healthStore.execute(query)
        }
    }

    private func fetchSleepHours(for date: Date) async throws -> Double? {
        guard availabilityProvider() else { return nil }
        guard let categoryType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let sleepWindowStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay),
              let sleepWindowEnd = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: sleepWindowStart,
            end: sleepWindowEnd,
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: categoryType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let categorySamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }

                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                ]

                let asleepSamples = categorySamples.filter { asleepValues.contains($0.value) }
                guard !asleepSamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalSeconds = asleepSamples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }

                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    private func fetchActiveMinutes(for date: Date) async throws -> Int? {
        guard availabilityProvider() else { return nil }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let totalSeconds = quantitySamples.reduce(0.0) { total, sample in
                    total + sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: max(Int(totalSeconds / 60.0), 0))
            }
            healthStore.execute(query)
        }
    }

    private func fetchGlucoseReadings(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [(date: Date, value: Double)] {
        guard availabilityProvider() else { return [] }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }

                let unit = HKUnit(from: "mg/dL")
                let readings = quantitySamples.map { sample in
                    (date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: readings)
            }
            healthStore.execute(query)
        }
    }
}
