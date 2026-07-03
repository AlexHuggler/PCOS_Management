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
    let insertedNutritionImportCount: Int
    let insertedProvenanceCount: Int
    let insertedCycleEntryCount: Int
    let insertedOvulationObservationCount: Int
    let insertedSymptomCount: Int

    init(
        syncedAt: Date,
        didUpdateDailyLog: Bool,
        insertedGlucoseCount: Int,
        insertedNutritionImportCount: Int = 0,
        insertedProvenanceCount: Int = 0,
        insertedCycleEntryCount: Int = 0,
        insertedOvulationObservationCount: Int = 0,
        insertedSymptomCount: Int = 0
    ) {
        self.syncedAt = syncedAt
        self.didUpdateDailyLog = didUpdateDailyLog
        self.insertedGlucoseCount = insertedGlucoseCount
        self.insertedNutritionImportCount = insertedNutritionImportCount
        self.insertedProvenanceCount = insertedProvenanceCount
        self.insertedCycleEntryCount = insertedCycleEntryCount
        self.insertedOvulationObservationCount = insertedOvulationObservationCount
        self.insertedSymptomCount = insertedSymptomCount
    }
}

enum HealthKitNutritionMetric: String, CaseIterable, Sendable {
    case dietaryEnergy
    case carbohydrates
    case protein
    case totalFat
    case saturatedFat
    case fiber
    case sugar
    case sodium
    case cholesterol
    case potassium
    case calcium
    case iron
    case water

    var quantityIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .dietaryEnergy:
            .dietaryEnergyConsumed
        case .carbohydrates:
            .dietaryCarbohydrates
        case .protein:
            .dietaryProtein
        case .totalFat:
            .dietaryFatTotal
        case .saturatedFat:
            .dietaryFatSaturated
        case .fiber:
            .dietaryFiber
        case .sugar:
            .dietarySugar
        case .sodium:
            .dietarySodium
        case .cholesterol:
            .dietaryCholesterol
        case .potassium:
            .dietaryPotassium
        case .calcium:
            .dietaryCalcium
        case .iron:
            .dietaryIron
        case .water:
            .dietaryWater
        }
    }

    var unit: HKUnit {
        switch self {
        case .dietaryEnergy:
            .kilocalorie()
        case .carbohydrates, .protein, .totalFat, .saturatedFat, .fiber, .sugar:
            .gram()
        case .sodium, .cholesterol, .potassium, .calcium, .iron:
            .gram()
        case .water:
            .literUnit(with: .milli)
        }
    }

    var storedValueMultiplier: Double {
        switch self {
        case .sodium, .cholesterol, .potassium, .calcium, .iron:
            1_000
        default:
            1
        }
    }

    var storedUnitLabel: String {
        switch self {
        case .dietaryEnergy:
            "kcal"
        case .sodium, .cholesterol, .potassium, .calcium, .iron:
            "mg"
        case .water:
            "mL"
        default:
            "g"
        }
    }
}

struct HealthKitNutritionSample: Sendable {
    var metric: HealthKitNutritionMetric
    var startDate: Date
    var endDate: Date
    var value: Double
    var sourceName: String
    var externalIdentifier: String
}

struct HealthKitCategorySamplePayload: Sendable {
    var healthKitIdentifier: String
    var startDate: Date
    var endDate: Date
    var value: Int
    var sourceName: String
    var sourceBundleIdentifier: String?
    var externalIdentifier: String
}

struct HealthKitQuantitySamplePayload: Sendable {
    var healthKitIdentifier: String
    var startDate: Date
    var endDate: Date
    var value: Double
    var unitLabel: String
    var sourceName: String
    var sourceBundleIdentifier: String?
    var externalIdentifier: String
}

actor HealthKitSyncWorker: HealthKitSyncPerforming {
    typealias AvailabilityProvider = @Sendable () -> Bool
    typealias WeightFetcher = @Sendable (Date) async throws -> Double?
    typealias SleepHoursFetcher = @Sendable (Date) async throws -> Double?
    typealias ActiveMinutesFetcher = @Sendable (Date) async throws -> Int?
    typealias RestingHeartRateFetcher = @Sendable (Date) async throws -> Double?
    typealias GlucoseReadingsFetcher = @Sendable (Date, Date) async throws -> [(date: Date, value: Double)]
    typealias NutritionSamplesFetcher = @Sendable (Date, Date) async throws -> [HealthKitNutritionSample]
    typealias CategorySamplesFetcher = @Sendable (Date, Date) async throws -> [HealthKitCategorySamplePayload]
    typealias ExtendedQuantitySamplesFetcher = @Sendable (Date, Date) async throws -> [HealthKitQuantitySamplePayload]

    private let healthStore: HKHealthStore
    private let availabilityProvider: AvailabilityProvider

    private let weightFetcherOverride: WeightFetcher?
    private let sleepHoursFetcherOverride: SleepHoursFetcher?
    private let activeMinutesFetcherOverride: ActiveMinutesFetcher?
    private let restingHeartRateFetcherOverride: RestingHeartRateFetcher?
    private let glucoseReadingsFetcherOverride: GlucoseReadingsFetcher?
    private let nutritionSamplesFetcherOverride: NutritionSamplesFetcher?
    private let categorySamplesFetcherOverride: CategorySamplesFetcher?
    private let extendedQuantitySamplesFetcherOverride: ExtendedQuantitySamplesFetcher?

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        availabilityProvider: @escaping AvailabilityProvider = { HKHealthStore.isHealthDataAvailable() },
        weightFetcher: WeightFetcher? = nil,
        sleepHoursFetcher: SleepHoursFetcher? = nil,
        activeMinutesFetcher: ActiveMinutesFetcher? = nil,
        restingHeartRateFetcher: RestingHeartRateFetcher? = nil,
        glucoseReadingsFetcher: GlucoseReadingsFetcher? = nil,
        nutritionSamplesFetcher: NutritionSamplesFetcher? = nil,
        categorySamplesFetcher: CategorySamplesFetcher? = nil,
        extendedQuantitySamplesFetcher: ExtendedQuantitySamplesFetcher? = nil
    ) {
        self.healthStore = healthStore
        self.availabilityProvider = availabilityProvider
        self.weightFetcherOverride = weightFetcher
        self.sleepHoursFetcherOverride = sleepHoursFetcher
        self.activeMinutesFetcherOverride = activeMinutesFetcher
        self.restingHeartRateFetcherOverride = restingHeartRateFetcher
        self.glucoseReadingsFetcherOverride = glucoseReadingsFetcher
        self.nutritionSamplesFetcherOverride = nutritionSamplesFetcher
        self.categorySamplesFetcherOverride = categorySamplesFetcher
        self.extendedQuantitySamplesFetcherOverride = extendedQuantitySamplesFetcher
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
        let insertedNutritionImportCount = try await syncNutritionImports(
            from: sevenDaysAgo,
            to: now,
            modelContext: workerContext
        )
        let categorySamples: [HealthKitCategorySamplePayload]
        do {
            categorySamples = try await resolveCategorySamples(from: sevenDaysAgo, to: now)
        } catch {
            categorySamples = []
            Logger.database.notice("HealthKit category context fetch skipped: \(error.localizedDescription)")
        }

        let quantitySamples: [HealthKitQuantitySamplePayload]
        do {
            quantitySamples = try await resolveExtendedQuantitySamples(from: sevenDaysAgo, to: now)
        } catch {
            quantitySamples = []
            Logger.database.notice("HealthKit extended quantity context fetch skipped: \(error.localizedDescription)")
        }
        let ovulationResult = try syncOvulationContext(
            categorySamples: categorySamples,
            quantitySamples: quantitySamples,
            importedAt: now,
            modelContext: workerContext
        )
        let insertedCycleEntryCount = try syncCycleEntries(
            categorySamples: categorySamples,
            importedAt: now,
            modelContext: workerContext
        )
        let insertedSymptomCount = try syncSymptoms(
            categorySamples: categorySamples,
            importedAt: now,
            modelContext: workerContext
        )
        let sourceOnlyProvenanceCount = try syncSourceOnlyContext(
            categorySamples: categorySamples,
            quantitySamples: quantitySamples,
            importedAt: now,
            modelContext: workerContext
        )

        return HealthKitSyncResult(
            syncedAt: now,
            didUpdateDailyLog: didUpdateDailyLog,
            insertedGlucoseCount: insertedGlucoseCount,
            insertedNutritionImportCount: insertedNutritionImportCount,
            insertedProvenanceCount: ovulationResult.provenanceCount + sourceOnlyProvenanceCount,
            insertedCycleEntryCount: insertedCycleEntryCount,
            insertedOvulationObservationCount: ovulationResult.observationCount,
            insertedSymptomCount: insertedSymptomCount
        )
    }

    // MARK: - Sync Methods

    private func syncDailyLog(date: Date, modelContext: ModelContext) async throws -> Bool {
        let weight = try await resolveWeight(for: date)
        let sleepHours = try await resolveSleepHours(for: date)
        let activeMinutes = try await resolveActiveMinutes(for: date)
        let restingHeartRate: Double?
        do {
            restingHeartRate = try await resolveRestingHeartRate(for: date)
        } catch {
            restingHeartRate = nil
            Logger.database.notice("HealthKit resting heart rate fetch skipped: \(error.localizedDescription)")
        }

        guard weight != nil || sleepHours != nil || activeMinutes != nil || restingHeartRate != nil else {
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
            if let restingHeartRate {
                existing.restingHeartRateBPM = restingHeartRate
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
            activeMinutes: activeMinutes,
            restingHeartRateBPM: restingHeartRate
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

    private func syncNutritionImports(
        from startDate: Date,
        to endDate: Date,
        modelContext: ModelContext
    ) async throws -> Int {
        let samples = try await resolveNutritionSamples(from: startDate, to: endDate)
        guard !samples.isEmpty else { return 0 }

        let groups = groupedNutritionSamples(samples)
        let existingImports = try modelContext.fetch(FetchDescriptor<NutritionImportRecord>())
            .filter { record in
                record.sourceKind == .healthKit
                    && record.startDate >= startDate
                    && record.startDate < endDate
            }
        let existingIdentifiers = Set(existingImports.compactMap(\.externalIdentifier))

        var insertedCount = 0
        for group in groups {
            let externalIdentifier = group.samples
                .map(\.externalIdentifier)
                .sorted()
                .joined(separator: "|")
            guard !externalIdentifier.isEmpty, !existingIdentifiers.contains(externalIdentifier) else {
                continue
            }

            let values = group.valuesByMetric
            let completeness = FoodProductCandidate.estimatedCompleteness(
                productName: nil,
                calories: values[.dietaryEnergy],
                carbsGrams: values[.carbohydrates],
                proteinGrams: values[.protein],
                fatGrams: values[.totalFat],
                fiberGrams: values[.fiber],
                sugarGrams: values[.sugar]
            )
            let nutritionImport = NutritionImportRecord(
                sourceKind: .healthKit,
                sourceName: group.sourceName,
                externalIdentifier: externalIdentifier,
                startDate: group.startDate,
                endDate: group.endDate,
                productName: nil,
                calories: values[.dietaryEnergy],
                carbsGrams: values[.carbohydrates],
                proteinGrams: values[.protein],
                fatGrams: values[.totalFat],
                fiberGrams: values[.fiber],
                sugarGrams: values[.sugar],
                waterOz: values[.water].map { $0 / 29.5735 },
                sodiumMg: values[.sodium],
                saturatedFatGrams: values[.saturatedFat],
                cholesterolMg: values[.cholesterol],
                potassiumMg: values[.potassium],
                calciumMg: values[.calcium],
                ironMg: values[.iron],
                confidence: 0.72,
                completeness: completeness,
                importedAt: endDate,
                reviewStatus: .needsReview,
                userReviewed: false,
                notes: "Imported from Apple Health nutrition samples."
            )
            modelContext.insert(nutritionImport)
            for sample in group.samples {
                insertProvenanceIfNeeded(
                    sampleUUID: sample.externalIdentifier,
                    healthKitIdentifier: sample.metric.quantityIdentifier.rawValue,
                    sourceName: sample.sourceName,
                    sourceBundleIdentifier: nil,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    valueDouble: sample.value,
                    valueUnit: sample.metric.storedUnitLabel,
                    categoryValue: nil,
                    derivedRecordKind: .nutritionImport,
                    derivedRecordID: nutritionImport.id,
                    importedAt: endDate,
                    modelContext: modelContext
                )
            }
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        Logger.database.info("Synced \(insertedCount) nutrition import(s) from HealthKit")
        return insertedCount
    }

    private struct OvulationSyncResult {
        var observationCount: Int
        var provenanceCount: Int
    }

    private func syncOvulationContext(
        categorySamples: [HealthKitCategorySamplePayload],
        quantitySamples: [HealthKitQuantitySamplePayload],
        importedAt: Date,
        modelContext: ModelContext
    ) throws -> OvulationSyncResult {
        var insertedOrUpdatedObservationIDs = Set<UUID>()
        var provenanceCount = 0

        let basalSamples = quantitySamples.filter { $0.healthKitIdentifier == HKQuantityTypeIdentifier.basalBodyTemperature.rawValue }
        for sample in basalSamples {
            let observation = try upsertOvulationObservation(on: sample.startDate, modelContext: modelContext)
            observation.basalBodyTemperatureCelsius = sample.value
            observation.notes = sourceNote(existing: observation.notes, sourceName: sample.sourceName)
            insertedOrUpdatedObservationIDs.insert(observation.id)
            if insertQuantityProvenance(sample, kind: .ovulationObservation, derivedRecordID: observation.id, importedAt: importedAt, modelContext: modelContext) {
                provenanceCount += 1
            }
        }

        for sample in categorySamples {
            guard let mapping = ovulationMapping(for: sample) else { continue }
            let observation = try upsertOvulationObservation(on: sample.startDate, modelContext: modelContext)
            switch mapping {
            case .cervicalMucus(let mucus):
                observation.cervicalMucus = mucus
            case .lhTest(let result):
                observation.lhTestResult = result
            case .progesteroneContext:
                break
            }
            observation.notes = sourceNote(existing: observation.notes, sourceName: sample.sourceName)
            insertedOrUpdatedObservationIDs.insert(observation.id)
            if insertCategoryProvenance(sample, kind: .ovulationObservation, derivedRecordID: observation.id, importedAt: importedAt, modelContext: modelContext) {
                provenanceCount += 1
            }
        }

        if !insertedOrUpdatedObservationIDs.isEmpty || provenanceCount > 0 {
            try modelContext.save()
        }

        return OvulationSyncResult(
            observationCount: insertedOrUpdatedObservationIDs.count,
            provenanceCount: provenanceCount
        )
    }

    private func syncCycleEntries(
        categorySamples: [HealthKitCategorySamplePayload],
        importedAt: Date,
        modelContext: ModelContext
    ) throws -> Int {
        let menstrualSamples = categorySamples.filter {
            $0.healthKitIdentifier == HKCategoryTypeIdentifier.menstrualFlow.rawValue
        }
        guard !menstrualSamples.isEmpty else { return 0 }

        var touchedIDs = Set<UUID>()
        for sample in menstrualSamples {
            let flow = flowIntensity(forMenstrualValue: sample.value)
            let entry = try upsertCycleEntry(on: sample.startDate, modelContext: modelContext)
            entry.isPeriodDay = flow != .none
            entry.flowIntensity = flow
            entry.notes = sourceNote(existing: entry.notes, sourceName: sample.sourceName)
            touchedIDs.insert(entry.id)
            insertCategoryProvenance(sample, kind: .cycleEntry, derivedRecordID: entry.id, importedAt: importedAt, modelContext: modelContext)
        }

        if !touchedIDs.isEmpty {
            try modelContext.save()
        }

        return touchedIDs.count
    }

    private func syncSymptoms(
        categorySamples: [HealthKitCategorySamplePayload],
        importedAt: Date,
        modelContext: ModelContext
    ) throws -> Int {
        var insertedCount = 0
        for sample in categorySamples {
            guard let symptomType = symptomType(forHealthKitIdentifier: sample.healthKitIdentifier),
                  let severity = symptomSeverity(for: sample) else {
                continue
            }
            guard !hasProvenance(sampleUUID: sample.externalIdentifier, modelContext: modelContext) else {
                continue
            }

            let entry = SymptomEntry(
                date: sample.startDate,
                type: symptomType,
                severity: severity,
                notes: "Imported from \(sample.sourceName) via Apple Health."
            )
            modelContext.insert(entry)
            insertCategoryProvenance(sample, kind: .symptomEntry, derivedRecordID: entry.id, importedAt: importedAt, modelContext: modelContext)
            insertedCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        return insertedCount
    }

    private func syncSourceOnlyContext(
        categorySamples: [HealthKitCategorySamplePayload],
        quantitySamples: [HealthKitQuantitySamplePayload],
        importedAt: Date,
        modelContext: ModelContext
    ) throws -> Int {
        let sourceOnlyCategoryIdentifiers: Set<String> = [
            HKCategoryTypeIdentifier.pregnancy.rawValue,
            HKCategoryTypeIdentifier.pregnancyTestResult.rawValue,
            HKCategoryTypeIdentifier.lactation.rawValue,
            HKCategoryTypeIdentifier.sexualActivity.rawValue,
        ]
        let sourceOnlyQuantityIdentifiers: Set<String> = [
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            HKQuantityTypeIdentifier.stepCount.rawValue,
            HKQuantityTypeIdentifier.bodyTemperature.rawValue,
            HKQuantityTypeIdentifier.heartRate.rawValue,
            HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue,
            HKQuantityTypeIdentifier.electrodermalActivity.rawValue,
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
        ]

        var insertedCount = 0
        for sample in categorySamples where sourceOnlyCategoryIdentifiers.contains(sample.healthKitIdentifier) {
            if insertCategoryProvenance(sample, kind: .sensitiveContext, derivedRecordID: nil, importedAt: importedAt, modelContext: modelContext) {
                insertedCount += 1
            }
        }

        for sample in quantitySamples where sourceOnlyQuantityIdentifiers.contains(sample.healthKitIdentifier) {
            if insertQuantityProvenance(sample, kind: .sourceOnly, derivedRecordID: nil, importedAt: importedAt, modelContext: modelContext) {
                insertedCount += 1
            }
        }

        if insertedCount > 0 {
            try modelContext.save()
        }

        return insertedCount
    }

    private enum OvulationMapping {
        case cervicalMucus(CervicalMucusType)
        case lhTest(LHTestResult)
        case progesteroneContext
    }

    private func ovulationMapping(for sample: HealthKitCategorySamplePayload) -> OvulationMapping? {
        switch sample.healthKitIdentifier {
        case HKCategoryTypeIdentifier.cervicalMucusQuality.rawValue:
            switch sample.value {
            case HKCategoryValueCervicalMucusQuality.dry.rawValue:
                return .cervicalMucus(.dry)
            case HKCategoryValueCervicalMucusQuality.sticky.rawValue:
                return .cervicalMucus(.sticky)
            case HKCategoryValueCervicalMucusQuality.creamy.rawValue:
                return .cervicalMucus(.creamy)
            case HKCategoryValueCervicalMucusQuality.watery.rawValue:
                return .cervicalMucus(.watery)
            case HKCategoryValueCervicalMucusQuality.eggWhite.rawValue:
                return .cervicalMucus(.eggWhite)
            default:
                return nil
            }
        case HKCategoryTypeIdentifier.ovulationTestResult.rawValue:
            switch sample.value {
            case HKCategoryValueOvulationTestResult.negative.rawValue:
                return .lhTest(.negative)
            case HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue:
                return .lhTest(.peak)
            case HKCategoryValueOvulationTestResult.estrogenSurge.rawValue:
                return .lhTest(.high)
            default:
                return nil
            }
        case HKCategoryTypeIdentifier.progesteroneTestResult.rawValue:
            return .progesteroneContext
        default:
            return nil
        }
    }

    private func flowIntensity(forMenstrualValue value: Int) -> FlowIntensity {
        switch value {
        case HKCategoryValueMenstrualFlow.light.rawValue:
            .light
        case HKCategoryValueMenstrualFlow.medium.rawValue:
            .medium
        case HKCategoryValueMenstrualFlow.heavy.rawValue:
            .heavy
        case HKCategoryValueMenstrualFlow.none.rawValue:
            .none
        default:
            .spotting
        }
    }

    private func symptomType(forHealthKitIdentifier identifier: String) -> SymptomType? {
        switch identifier {
        case HKCategoryTypeIdentifier.abdominalCramps.rawValue:
            .cramps
        case HKCategoryTypeIdentifier.pelvicPain.rawValue:
            .pelvicPain
        case HKCategoryTypeIdentifier.fatigue.rawValue:
            .fatigue
        case HKCategoryTypeIdentifier.bloating.rawValue:
            .bloating
        case HKCategoryTypeIdentifier.acne.rawValue:
            .acne
        case HKCategoryTypeIdentifier.hairLoss.rawValue:
            .shedding
        case HKCategoryTypeIdentifier.headache.rawValue:
            .headache
        case HKCategoryTypeIdentifier.moodChanges.rawValue:
            .moodSwings
        case HKCategoryTypeIdentifier.appetiteChanges.rawValue:
            .cravings
        case HKCategoryTypeIdentifier.sleepChanges.rawValue:
            .fatigue
        default:
            nil
        }
    }

    private func symptomSeverity(for sample: HealthKitCategorySamplePayload) -> Int? {
        switch sample.value {
        case HKCategoryValueSeverity.notPresent.rawValue, HKCategoryValuePresence.notPresent.rawValue:
            return nil
        case HKCategoryValueSeverity.mild.rawValue:
            return 2
        case HKCategoryValueSeverity.moderate.rawValue:
            return 3
        case HKCategoryValueSeverity.severe.rawValue:
            return 5
        default:
            return 3
        }
    }

    private func upsertCycleEntry(on date: Date, modelContext: ModelContext) throws -> CycleEntry {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let descriptor = FetchDescriptor<CycleEntry>(
            predicate: #Predicate<CycleEntry> { entry in
                entry.date >= startOfDay && entry.date < endOfDay
            }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let entry = CycleEntry(date: startOfDay)
        modelContext.insert(entry)
        return entry
    }

    private func upsertOvulationObservation(on date: Date, modelContext: ModelContext) throws -> OvulationObservation {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let descriptor = FetchDescriptor<OvulationObservation>(
            predicate: #Predicate<OvulationObservation> { observation in
                observation.date >= startOfDay && observation.date < endOfDay
            }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let observation = OvulationObservation(date: startOfDay)
        modelContext.insert(observation)
        return observation
    }

    @discardableResult
    private func insertCategoryProvenance(
        _ sample: HealthKitCategorySamplePayload,
        kind: HealthKitDerivedRecordKind,
        derivedRecordID: UUID?,
        importedAt: Date,
        modelContext: ModelContext
    ) -> Bool {
        insertProvenanceIfNeeded(
            sampleUUID: sample.externalIdentifier,
            healthKitIdentifier: sample.healthKitIdentifier,
            sourceName: sample.sourceName,
            sourceBundleIdentifier: sample.sourceBundleIdentifier,
            startDate: sample.startDate,
            endDate: sample.endDate,
            valueDouble: nil,
            valueUnit: nil,
            categoryValue: sample.value,
            derivedRecordKind: kind,
            derivedRecordID: derivedRecordID,
            importedAt: importedAt,
            modelContext: modelContext
        )
    }

    @discardableResult
    private func insertQuantityProvenance(
        _ sample: HealthKitQuantitySamplePayload,
        kind: HealthKitDerivedRecordKind,
        derivedRecordID: UUID?,
        importedAt: Date,
        modelContext: ModelContext
    ) -> Bool {
        insertProvenanceIfNeeded(
            sampleUUID: sample.externalIdentifier,
            healthKitIdentifier: sample.healthKitIdentifier,
            sourceName: sample.sourceName,
            sourceBundleIdentifier: sample.sourceBundleIdentifier,
            startDate: sample.startDate,
            endDate: sample.endDate,
            valueDouble: sample.value,
            valueUnit: sample.unitLabel,
            categoryValue: nil,
            derivedRecordKind: kind,
            derivedRecordID: derivedRecordID,
            importedAt: importedAt,
            modelContext: modelContext
        )
    }

    @discardableResult
    private func insertProvenanceIfNeeded(
        sampleUUID: String,
        healthKitIdentifier: String,
        sourceName: String,
        sourceBundleIdentifier: String?,
        startDate: Date,
        endDate: Date?,
        valueDouble: Double?,
        valueUnit: String?,
        categoryValue: Int?,
        derivedRecordKind: HealthKitDerivedRecordKind,
        derivedRecordID: UUID?,
        importedAt: Date,
        modelContext: ModelContext
    ) -> Bool {
        guard !sampleUUID.isEmpty, !hasProvenance(sampleUUID: sampleUUID, modelContext: modelContext) else {
            return false
        }

        modelContext.insert(
            HealthKitImportedSampleRecord(
                sampleUUID: sampleUUID,
                healthKitIdentifier: healthKitIdentifier,
                sourceName: sourceName,
                sourceBundleIdentifier: sourceBundleIdentifier,
                startDate: startDate,
                endDate: endDate,
                valueDouble: valueDouble,
                valueUnit: valueUnit,
                categoryValue: categoryValue,
                derivedRecordKind: derivedRecordKind,
                derivedRecordID: derivedRecordID,
                importedAt: importedAt,
                notes: "From \(sourceName) via Apple Health."
            )
        )
        return true
    }

    private func hasProvenance(sampleUUID: String, modelContext: ModelContext) -> Bool {
        guard !sampleUUID.isEmpty else { return false }
        let descriptor = FetchDescriptor<HealthKitImportedSampleRecord>(
            predicate: #Predicate<HealthKitImportedSampleRecord> { record in
                record.sampleUUID == sampleUUID
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    private func sourceNote(existing: String?, sourceName: String) -> String {
        let sourceText = "Imported from \(sourceName) via Apple Health."
        guard let existing, !existing.localizedCaseInsensitiveContains(sourceText) else {
            return existing ?? sourceText
        }
        return "\(existing)\n\(sourceText)"
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

    private func resolveRestingHeartRate(for date: Date) async throws -> Double? {
        if let restingHeartRateFetcherOverride {
            return try await restingHeartRateFetcherOverride(date)
        }
        return try await fetchRestingHeartRate(for: date)
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

    private func resolveNutritionSamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitNutritionSample] {
        if let nutritionSamplesFetcherOverride {
            return try await nutritionSamplesFetcherOverride(startDate, endDate)
        }
        return try await fetchNutritionSamples(from: startDate, to: endDate)
    }

    private func resolveCategorySamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitCategorySamplePayload] {
        if let categorySamplesFetcherOverride {
            return try await categorySamplesFetcherOverride(startDate, endDate)
        }
        return try await fetchCategorySamples(from: startDate, to: endDate)
    }

    private func resolveExtendedQuantitySamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitQuantitySamplePayload] {
        if let extendedQuantitySamplesFetcherOverride {
            return try await extendedQuantitySamplesFetcherOverride(startDate, endDate)
        }
        return try await fetchExtendedQuantitySamples(from: startDate, to: endDate)
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
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
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

                let totalMinutes = quantitySamples.reduce(0.0) { total, sample in
                    total + sample.quantity.doubleValue(for: .minute())
                }
                continuation.resume(returning: max(Int(totalMinutes.rounded()), 0))
            }
            healthStore.execute(query)
        }
    }

    private func fetchRestingHeartRate(for date: Date) async throws -> Double? {
        guard availabilityProvider() else { return nil }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
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

                let bpmUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
                let bpm = sample.quantity.doubleValue(for: bpmUnit)
                continuation.resume(returning: bpm)
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

    private struct NutritionSampleGroup {
        var sourceName: String
        var startDate: Date
        var endDate: Date
        var samples: [HealthKitNutritionSample]

        var valuesByMetric: [HealthKitNutritionMetric: Double] {
            samples.reduce(into: [:]) { result, sample in
                result[sample.metric, default: 0] += sample.value
            }
        }
    }

    private func groupedNutritionSamples(_ samples: [HealthKitNutritionSample]) -> [NutritionSampleGroup] {
        let sortedSamples = samples.sorted {
            if $0.sourceName == $1.sourceName {
                $0.startDate < $1.startDate
            } else {
                $0.sourceName < $1.sourceName
            }
        }

        var groups: [NutritionSampleGroup] = []
        for sample in sortedSamples {
            if var currentGroup = groups.popLast() {
                let isSameSource = currentGroup.sourceName == sample.sourceName
                let isCloseWindow = sample.startDate.timeIntervalSince(currentGroup.startDate) <= 1_800
                if isSameSource && isCloseWindow {
                    currentGroup.endDate = max(currentGroup.endDate, sample.endDate)
                    currentGroup.samples.append(sample)
                    groups.append(currentGroup)
                    continue
                }

                groups.append(currentGroup)
            }

            groups.append(
                NutritionSampleGroup(
                    sourceName: sample.sourceName,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    samples: [sample]
                )
            )
        }

        return groups.sorted { $0.startDate < $1.startDate }
    }

    private func fetchNutritionSamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitNutritionSample] {
        guard availabilityProvider() else { return [] }

        var allSamples: [HealthKitNutritionSample] = []
        for metric in HealthKitNutritionMetric.allCases {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: metric.quantityIdentifier) else {
                continue
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

            let metricSamples: [HealthKitNutritionSample] = try await withCheckedThrowingContinuation { continuation in
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

                    let mapped = quantitySamples.map { sample in
                        HealthKitNutritionSample(
                            metric: metric,
                            startDate: sample.startDate,
                            endDate: sample.endDate,
                            value: sample.quantity.doubleValue(for: metric.unit) * metric.storedValueMultiplier,
                            sourceName: sample.sourceRevision.source.name,
                            externalIdentifier: sample.uuid.uuidString
                        )
                    }
                    continuation.resume(returning: mapped)
                }
                healthStore.execute(query)
            }
            allSamples.append(contentsOf: metricSamples)
        }

        return allSamples
    }

    private func fetchCategorySamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitCategorySamplePayload] {
        guard availabilityProvider() else { return [] }

        let categoryDescriptors = HealthKitDataTypeDescriptor.readDescriptors.compactMap { descriptor -> HKCategoryTypeIdentifier? in
            if case .category(let identifier) = descriptor.objectKind,
               identifier != .sleepAnalysis {
                return identifier
            }
            return nil
        }

        var allSamples: [HealthKitCategorySamplePayload] = []
        for identifier in categoryDescriptors {
            guard let categoryType = HKObjectType.categoryType(forIdentifier: identifier) else {
                continue
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

            let samplesForType: [HealthKitCategorySamplePayload] = try await withCheckedThrowingContinuation { continuation in
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
                        continuation.resume(returning: [])
                        return
                    }

                    let mapped = categorySamples.map { sample in
                        HealthKitCategorySamplePayload(
                            healthKitIdentifier: identifier.rawValue,
                            startDate: sample.startDate,
                            endDate: sample.endDate,
                            value: sample.value,
                            sourceName: sample.sourceRevision.source.name,
                            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                            externalIdentifier: sample.uuid.uuidString
                        )
                    }
                    continuation.resume(returning: mapped)
                }
                healthStore.execute(query)
            }
            allSamples.append(contentsOf: samplesForType)
        }

        return allSamples
    }

    private func fetchExtendedQuantitySamples(
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HealthKitQuantitySamplePayload] {
        guard availabilityProvider() else { return [] }

        let quantityTypes: [(HKQuantityTypeIdentifier, HKUnit, String)] = [
            (.activeEnergyBurned, .kilocalorie(), "kcal"),
            (.stepCount, .count(), "count"),
            (.basalBodyTemperature, .degreeCelsius(), "degC"),
            (.bodyTemperature, .degreeCelsius(), "degC"),
            (.heartRate, HKUnit.count().unitDivided(by: HKUnit.minute()), "bpm"),
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli), "ms"),
            (.electrodermalActivity, .siemenUnit(with: .micro), "uS"),
            (.appleExerciseTime, .minute(), "min"),
            (.distanceWalkingRunning, .meter(), "m"),
        ]

        var allSamples: [HealthKitQuantitySamplePayload] = []
        for (identifier, unit, label) in quantityTypes {
            guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
                continue
            }

            let predicate = HKQuery.predicateForSamples(
                withStart: startDate,
                end: endDate,
                options: .strictStartDate
            )

            let samplesForType: [HealthKitQuantitySamplePayload] = try await withCheckedThrowingContinuation { continuation in
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

                    let mapped = quantitySamples.map { sample in
                        HealthKitQuantitySamplePayload(
                            healthKitIdentifier: identifier.rawValue,
                            startDate: sample.startDate,
                            endDate: sample.endDate,
                            value: sample.quantity.doubleValue(for: unit),
                            unitLabel: label,
                            sourceName: sample.sourceRevision.source.name,
                            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                            externalIdentifier: sample.uuid.uuidString
                        )
                    }
                    continuation.resume(returning: mapped)
                }
                healthStore.execute(query)
            }
            allSamples.append(contentsOf: samplesForType)
        }

        return allSamples
    }
}
