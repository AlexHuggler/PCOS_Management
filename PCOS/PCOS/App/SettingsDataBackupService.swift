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
                    postMealFeedbackTimestamp: $0.postMealFeedbackTimestamp
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
            }
        )
    }
}
