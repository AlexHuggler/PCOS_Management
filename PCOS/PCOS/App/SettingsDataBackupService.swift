import Foundation
import SwiftData
import os

@MainActor
struct SettingsDataBackupService {
    typealias DataWriter = (_ data: Data, _ url: URL) throws -> Void

    private let modelContext: ModelContext
    private let dataWriter: DataWriter

    init(
        modelContext: ModelContext,
        dataWriter: @escaping DataWriter = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.modelContext = modelContext
        self.dataWriter = dataWriter
    }

    func generateJSONBackup(
        source: SettingsDataBackupSource = .userExport
    ) throws -> URL {
        let data = try generateJSONBackupData(source: source)
        let suffix = source.scenarioID.map { "_\($0)" } ?? ""
        let fileName = "CycleBalance_Backup\(suffix).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try dataWriter(data, url)
        return url
    }

    func generateJSONBackupData(
        source: SettingsDataBackupSource = .userExport
    ) throws -> Data {
        let backup = try makeBackup(source: source)
        let encoder = SettingsDataBackupCoding.makeEncoder()
        return try encoder.encode(backup)
    }

    func makeBackup(
        source: SettingsDataBackupSource = .userExport
    ) throws -> SettingsDataBackupFile {
        let records = try fetchRecords()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return SettingsDataBackupFile(
            exportedAt: Date(),
            appVersion: appVersion,
            source: source,
            records: records
        )
    }
}

private extension SettingsDataBackupService {
    func fetchRecords() throws -> SettingsDataBackupRecords {
        let cycles = try modelContext.fetch(FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate)]))
        let cycleEntries = try modelContext.fetch(FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)]))
        let symptoms = try modelContext.fetch(FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.date)]))
        let bloodSugarReadings = try modelContext.fetch(FetchDescriptor<BloodSugarReading>(sortBy: [SortDescriptor(\.timestamp)]))
        let supplements = try modelContext.fetch(FetchDescriptor<SupplementLog>(sortBy: [SortDescriptor(\.date)]))
        let meals = try modelContext.fetch(FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp)]))
        let hairPhotos = try modelContext.fetch(FetchDescriptor<HairPhotoEntry>(sortBy: [SortDescriptor(\.date)]))
        let dailyLogs = try modelContext.fetch(FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date)]))
        let insights = try modelContext.fetch(FetchDescriptor<Insight>(sortBy: [SortDescriptor(\.generatedDate)]))
        let pregnancies = try modelContext.fetch(FetchDescriptor<PregnancyRecord>(sortBy: [SortDescriptor(\.startDate)]))
        let ovulationObservations = try modelContext.fetch(FetchDescriptor<OvulationObservation>(sortBy: [SortDescriptor(\.date)]))
        let nutritionImports = try modelContext.fetch(FetchDescriptor<NutritionImportRecord>(sortBy: [SortDescriptor(\.startDate)]))
        let mealScanFoodItems = try modelContext.fetch(FetchDescriptor<MealScanFoodItem>(sortBy: [SortDescriptor(\.createdAt)]))
        let mealScanNutritionSummaries = try modelContext.fetch(FetchDescriptor<MealScanNutritionSummary>(sortBy: [SortDescriptor(\.createdAt)]))
        let mealScanMetadata = try modelContext.fetch(FetchDescriptor<MealScanMetadata>(sortBy: [SortDescriptor(\.createdAt)]))
        let healthKitImportedSamples = try modelContext.fetch(FetchDescriptor<HealthKitImportedSampleRecord>(sortBy: [SortDescriptor(\.startDate)]))

        Logger.database.info(
            "Preparing JSON backup with \(cycles.count) cycles, \(cycleEntries.count) entries, \(symptoms.count) symptoms"
        )

        return SettingsDataBackupRecords(
            cycles: cycles.map {
                CycleRecord(
                    id: $0.id,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    lengthDays: $0.lengthDays,
                    isPredicted: $0.isPredicted,
                    manualCycleLengthOverrideDays: $0.manualCycleLengthOverrideDays,
                    ovulationStatus: $0.ovulationStatus,
                    endReason: $0.endReason
                )
            },
            cycleEntries: cycleEntries.map {
                CycleEntryRecord(
                    id: $0.id,
                    date: $0.date,
                    flowIntensity: $0.flowIntensity,
                    isPeriodDay: $0.isPeriodDay,
                    cyclePhase: $0.cyclePhase,
                    notes: $0.notes,
                    createdAt: $0.createdAt,
                    cycleID: $0.cycle?.id
                )
            },
            symptoms: symptoms.map {
                SymptomEntryRecord(
                    id: $0.id,
                    date: $0.date,
                    category: $0.category,
                    symptomType: $0.symptomType,
                    severity: $0.severity,
                    notes: $0.notes,
                    cycleEntryID: $0.cycleEntry?.id
                )
            },
            bloodSugarReadings: bloodSugarReadings.map {
                BloodSugarReadingRecord(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    glucoseValue: $0.glucoseValue,
                    readingType: $0.readingType,
                    mealContext: $0.mealContext,
                    fromHealthKit: $0.fromHealthKit,
                    notes: $0.notes
                )
            },
            supplements: supplements.map {
                SupplementLogRecord(
                    id: $0.id,
                    date: $0.date,
                    supplementName: $0.supplementName,
                    dosageMg: $0.dosageMg,
                    timeTaken: $0.timeTaken,
                    taken: $0.taken,
                    brand: $0.brand
                )
            },
            meals: meals.map {
                MealEntryRecord(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    mealType: $0.mealType,
                    mealDescription: $0.mealDescription,
                    glycemicImpact: $0.glycemicImpact,
                    photoData: $0.photoData,
                    carbsGrams: $0.carbsGrams,
                    proteinGrams: $0.proteinGrams,
                    fatGrams: $0.fatGrams,
                    notes: $0.notes,
                    selectedTemplateID: $0.selectedTemplateID,
                    postMealSymptomSeverity: $0.postMealSymptomSeverity,
                    postMealSymptomNote: $0.postMealSymptomNote,
                    postMealFeedbackTimestamp: $0.postMealFeedbackTimestamp,
                    nutritionImportID: $0.nutritionImportID,
                    barcode: $0.barcode,
                    sourceLabel: $0.sourceLabel,
                    calories: $0.calories,
                    fiberGrams: $0.fiberGrams,
                    sugarGrams: $0.sugarGrams,
                    servingText: $0.servingText,
                    mealSource: $0.mealSource,
                    photoLocalPath: $0.photoLocalPath,
                    confidenceScore: $0.confidenceScore,
                    userConfirmed: $0.userConfirmed,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            hairPhotos: hairPhotos.map {
                HairPhotoEntryRecord(
                    id: $0.id,
                    date: $0.date,
                    photoType: $0.photoType,
                    photoData: $0.photoData,
                    notes: $0.notes,
                    analysisResult: $0.analysisResult
                )
            },
            dailyLogs: dailyLogs.map {
                DailyLogRecord(
                    id: $0.id,
                    date: $0.date,
                    weight: $0.weight,
                    sleepHours: $0.sleepHours,
                    activeMinutes: $0.activeMinutes,
                    restingHeartRateBPM: $0.restingHeartRateBPM,
                    stressLevel: $0.stressLevel,
                    energyLevel: $0.energyLevel,
                    waterOz: $0.waterOz
                )
            },
            insights: insights.map {
                InsightRecord(
                    id: $0.id,
                    generatedDate: $0.generatedDate,
                    insightType: $0.insightType,
                    title: $0.title,
                    content: $0.content,
                    scientificContent: $0.scientificContent,
                    confidence: $0.confidence,
                    dataPointsUsed: $0.dataPointsUsed,
                    actionable: $0.actionable,
                    relatedSymptoms: $0.relatedSymptoms,
                    phaseContext: $0.phaseContext,
                    recommendedActions: $0.recommendedActions,
                    learnMoreTopic: $0.learnMoreTopic
                )
            },
            pregnancyRecords: pregnancies.map {
                PregnancyRecordDTO(
                    id: $0.id,
                    startDate: $0.startDate,
                    estimatedDueDate: $0.estimatedDueDate,
                    endDate: $0.endDate,
                    endReason: $0.endReason,
                    isActive: $0.isActive,
                    notes: $0.notes
                )
            },
            ovulationObservations: ovulationObservations.map {
                OvulationObservationRecord(
                    id: $0.id,
                    date: $0.date,
                    basalBodyTemperatureCelsius: $0.basalBodyTemperatureCelsius,
                    cervicalMucus: $0.cervicalMucus,
                    lhTestResult: $0.lhTestResult,
                    notes: $0.notes,
                    createdAt: $0.createdAt
                )
            },
            nutritionImports: nutritionImports.map {
                NutritionImportRecordDTO(
                    id: $0.id,
                    sourceKind: $0.sourceKind,
                    sourceName: $0.sourceName,
                    externalIdentifier: $0.externalIdentifier,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    barcode: $0.barcode,
                    productName: $0.productName,
                    brandName: $0.brandName,
                    servingText: $0.servingText,
                    calories: $0.calories,
                    carbsGrams: $0.carbsGrams,
                    proteinGrams: $0.proteinGrams,
                    fatGrams: $0.fatGrams,
                    fiberGrams: $0.fiberGrams,
                    sugarGrams: $0.sugarGrams,
                    waterOz: $0.waterOz,
                    sodiumMg: $0.sodiumMg,
                    saturatedFatGrams: $0.saturatedFatGrams,
                    cholesterolMg: $0.cholesterolMg,
                    potassiumMg: $0.potassiumMg,
                    calciumMg: $0.calciumMg,
                    ironMg: $0.ironMg,
                    confidence: $0.confidence,
                    completeness: $0.completeness,
                    importedAt: $0.importedAt,
                    reviewStatus: $0.reviewStatus,
                    userReviewed: $0.userReviewed,
                    notes: $0.notes
                )
            },
            mealScanFoodItems: mealScanFoodItems.map {
                MealScanFoodItemRecord(
                    id: $0.id,
                    mealId: $0.mealId,
                    displayName: $0.displayName,
                    canonicalFoodId: $0.canonicalFoodId,
                    nutritionSource: $0.nutritionSource,
                    estimatedGrams: $0.estimatedGrams,
                    estimatedVolumeMl: $0.estimatedVolumeMl,
                    servingDescription: $0.servingDescription,
                    caloriesKcal: $0.caloriesKcal,
                    proteinGrams: $0.proteinGrams,
                    carbsGrams: $0.carbsGrams,
                    netCarbsGrams: $0.netCarbsGrams,
                    fatGrams: $0.fatGrams,
                    fiberGrams: $0.fiberGrams,
                    sugarGrams: $0.sugarGrams,
                    sodiumMg: $0.sodiumMg,
                    saturatedFatGrams: $0.saturatedFatGrams,
                    confidenceScore: $0.confidenceScore,
                    detectionSource: $0.detectionSource,
                    portionEstimationMethod: $0.portionEstimationMethod,
                    wasUserEdited: $0.wasUserEdited,
                    wasPortionAdjusted: $0.wasPortionAdjusted,
                    warning: $0.warning,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            mealScanNutritionSummaries: mealScanNutritionSummaries.map {
                MealScanNutritionSummaryRecord(
                    id: $0.id,
                    mealId: $0.mealId,
                    caloriesKcal: $0.caloriesKcal,
                    proteinGrams: $0.proteinGrams,
                    carbsGrams: $0.carbsGrams,
                    netCarbsGrams: $0.netCarbsGrams,
                    fatGrams: $0.fatGrams,
                    fiberGrams: $0.fiberGrams,
                    sugarGrams: $0.sugarGrams,
                    sodiumMg: $0.sodiumMg,
                    saturatedFatGrams: $0.saturatedFatGrams,
                    confidenceScore: $0.confidenceScore,
                    estimatedGlycemicImpact: $0.estimatedGlycemicImpact,
                    nutritionSourceSummary: $0.nutritionSourceSummary,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            mealScanMetadata: mealScanMetadata.map {
                MealScanMetadataRecord(
                    id: $0.id,
                    mealId: $0.mealId,
                    originalPredictionJSON: $0.originalPredictionJSON,
                    finalUserConfirmedJSON: $0.finalUserConfirmedJSON,
                    modelVersion: $0.modelVersion,
                    pipelineVersion: $0.pipelineVersion,
                    userConfirmed: $0.userConfirmed,
                    hasUserEdits: $0.hasUserEdits,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            healthKitImportedSamples: healthKitImportedSamples.map {
                HealthKitImportedSampleRecordDTO(
                    id: $0.id,
                    sampleUUID: $0.sampleUUID,
                    healthKitIdentifier: $0.healthKitIdentifier,
                    sourceName: $0.sourceName,
                    sourceBundleIdentifier: $0.sourceBundleIdentifier,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    valueDouble: $0.valueDouble,
                    valueUnit: $0.valueUnit,
                    categoryValue: $0.categoryValue,
                    derivedRecordKind: $0.derivedRecordKind,
                    derivedRecordID: $0.derivedRecordID,
                    importedAt: $0.importedAt,
                    notes: $0.notes
                )
            }
        )
    }
}

extension SettingsDataBackupService {
    func makeBackupFile(source: SettingsDataBackupSource = .userExport) throws -> SettingsDataBackupFile {
        try makeBackup(source: source)
    }
}
