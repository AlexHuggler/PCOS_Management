import Foundation

struct SettingsDataBackupSource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case userExport = "user_export"
        case demoScenario = "demo_scenario"
    }

    var kind: Kind
    var scenarioID: String?

    static let userExport = SettingsDataBackupSource(kind: .userExport, scenarioID: nil)
}

struct SettingsDataRecordCounts: Codable, Equatable, Sendable {
    var cycles: Int = 0
    var cycleEntries: Int = 0
    var symptoms: Int = 0
    var bloodSugarReadings: Int = 0
    var supplements: Int = 0
    var meals: Int = 0
    var hairPhotos: Int = 0
    var dailyLogs: Int = 0
    var insights: Int = 0
    var pregnancyRecords: Int = 0
    var ovulationObservations: Int = 0
    var nutritionImports: Int = 0
    var mealScanFoodItems: Int = 0
    var mealScanNutritionSummaries: Int = 0
    var mealScanMetadata: Int = 0
    var healthKitImportedSamples: Int = 0

    var total: Int {
        cycles
            + cycleEntries
            + symptoms
            + bloodSugarReadings
            + supplements
            + meals
            + hairPhotos
            + dailyLogs
            + insights
            + pregnancyRecords
            + ovulationObservations
            + nutritionImports
            + mealScanFoodItems
            + mealScanNutritionSummaries
            + mealScanMetadata
            + healthKitImportedSamples
    }
}

struct SettingsDataBackupFile: Codable, Sendable {
    static let currentSchemaVersion = 5

    var schemaVersion: Int = currentSchemaVersion
    var exportedAt: Date
    var appVersion: String
    var source: SettingsDataBackupSource
    var records: SettingsDataBackupRecords
}

struct SettingsDataBackupRecords: Codable, Sendable {
    var cycles: [CycleRecord] = []
    var cycleEntries: [CycleEntryRecord] = []
    var symptoms: [SymptomEntryRecord] = []
    var bloodSugarReadings: [BloodSugarReadingRecord] = []
    var supplements: [SupplementLogRecord] = []
    var meals: [MealEntryRecord] = []
    var hairPhotos: [HairPhotoEntryRecord] = []
    var dailyLogs: [DailyLogRecord] = []
    var insights: [InsightRecord] = []
    var pregnancyRecords: [PregnancyRecordDTO] = []
    var ovulationObservations: [OvulationObservationRecord] = []
    var nutritionImports: [NutritionImportRecordDTO] = []
    var mealScanFoodItems: [MealScanFoodItemRecord] = []
    var mealScanNutritionSummaries: [MealScanNutritionSummaryRecord] = []
    var mealScanMetadata: [MealScanMetadataRecord] = []
    var healthKitImportedSamples: [HealthKitImportedSampleRecordDTO] = []

    var counts: SettingsDataRecordCounts {
        SettingsDataRecordCounts(
            cycles: cycles.count,
            cycleEntries: cycleEntries.count,
            symptoms: symptoms.count,
            bloodSugarReadings: bloodSugarReadings.count,
            supplements: supplements.count,
            meals: meals.count,
            hairPhotos: hairPhotos.count,
            dailyLogs: dailyLogs.count,
            insights: insights.count,
            pregnancyRecords: pregnancyRecords.count,
            ovulationObservations: ovulationObservations.count,
            nutritionImports: nutritionImports.count,
            mealScanFoodItems: mealScanFoodItems.count,
            mealScanNutritionSummaries: mealScanNutritionSummaries.count,
            mealScanMetadata: mealScanMetadata.count,
            healthKitImportedSamples: healthKitImportedSamples.count
        )
    }
}

extension SettingsDataBackupFile {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case appVersion
        case source
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        self.appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? "unknown"
        self.source = try container.decodeIfPresent(SettingsDataBackupSource.self, forKey: .source) ?? .userExport
        self.records = try container.decodeIfPresent(SettingsDataBackupRecords.self, forKey: .records) ?? SettingsDataBackupRecords()
    }
}

extension SettingsDataBackupRecords {
    private enum CodingKeys: String, CodingKey {
        case cycles
        case cycleEntries
        case symptoms
        case bloodSugarReadings
        case supplements
        case meals
        case hairPhotos
        case dailyLogs
        case insights
        case pregnancyRecords
        case ovulationObservations
        case nutritionImports
        case mealScanFoodItems
        case mealScanNutritionSummaries
        case mealScanMetadata
        case healthKitImportedSamples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.cycles = try container.decodeIfPresent([CycleRecord].self, forKey: .cycles) ?? []
        self.cycleEntries = try container.decodeIfPresent([CycleEntryRecord].self, forKey: .cycleEntries) ?? []
        self.symptoms = try container.decodeIfPresent([SymptomEntryRecord].self, forKey: .symptoms) ?? []
        self.bloodSugarReadings = try container.decodeIfPresent([BloodSugarReadingRecord].self, forKey: .bloodSugarReadings) ?? []
        self.supplements = try container.decodeIfPresent([SupplementLogRecord].self, forKey: .supplements) ?? []
        self.meals = try container.decodeIfPresent([MealEntryRecord].self, forKey: .meals) ?? []
        self.hairPhotos = try container.decodeIfPresent([HairPhotoEntryRecord].self, forKey: .hairPhotos) ?? []
        self.dailyLogs = try container.decodeIfPresent([DailyLogRecord].self, forKey: .dailyLogs) ?? []
        self.insights = try container.decodeIfPresent([InsightRecord].self, forKey: .insights) ?? []
        self.pregnancyRecords = try container.decodeIfPresent([PregnancyRecordDTO].self, forKey: .pregnancyRecords) ?? []
        self.ovulationObservations = try container.decodeIfPresent([OvulationObservationRecord].self, forKey: .ovulationObservations) ?? []
        self.nutritionImports = try container.decodeIfPresent([NutritionImportRecordDTO].self, forKey: .nutritionImports) ?? []
        self.mealScanFoodItems = try container.decodeIfPresent([MealScanFoodItemRecord].self, forKey: .mealScanFoodItems) ?? []
        self.mealScanNutritionSummaries = try container.decodeIfPresent([MealScanNutritionSummaryRecord].self, forKey: .mealScanNutritionSummaries) ?? []
        self.mealScanMetadata = try container.decodeIfPresent([MealScanMetadataRecord].self, forKey: .mealScanMetadata) ?? []
        self.healthKitImportedSamples = try container.decodeIfPresent([HealthKitImportedSampleRecordDTO].self, forKey: .healthKitImportedSamples) ?? []
    }
}

// MARK: - Record DTOs

struct CycleRecord: Codable, Sendable {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var lengthDays: Int?
    var isPredicted: Bool
    var manualCycleLengthOverrideDays: Int?
    var ovulationStatus: OvulationStatus?
    var endReason: CycleEndReason? = nil
}

struct CycleEntryRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var flowIntensity: FlowIntensity?
    var isPeriodDay: Bool
    var cyclePhase: CyclePhase?
    var notes: String?
    var createdAt: Date
    var cycleID: UUID?
}

struct SymptomEntryRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var category: SymptomCategory
    var symptomType: SymptomType
    var severity: Int
    var notes: String?
    var cycleEntryID: UUID?
}

struct BloodSugarReadingRecord: Codable, Sendable {
    var id: UUID
    var timestamp: Date
    var glucoseValue: Double
    var readingType: GlucoseReadingType
    var mealContext: String?
    var fromHealthKit: Bool
    var notes: String?
}

struct SupplementLogRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var supplementName: String
    var dosageMg: Double?
    /// Raw `DosageUnit`; nil in backups written before schema v6 and treated as milligrams.
    var dosageUnit: String?
    var timeTaken: Date
    var taken: Bool
    var brand: String?
}

struct MealEntryRecord: Codable, Sendable {
    var id: UUID
    var timestamp: Date
    var mealType: MealType
    var mealDescription: String
    var glycemicImpact: GlycemicImpact
    var photoData: Data?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var notes: String?
    var selectedTemplateID: String?
    var postMealSymptomSeverity: Int?
    var postMealSymptomNote: String?
    var postMealFeedbackTimestamp: Date?
    var nutritionImportID: UUID?
    var barcode: String?
    var sourceLabel: String?
    var calories: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var servingText: String?
    var mealSource: String?
    var photoLocalPath: String?
    var confidenceScore: Double?
    var userConfirmed: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

extension MealEntryRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case mealType
        case mealDescription
        case glycemicImpact
        case photoData
        case carbsGrams
        case proteinGrams
        case fatGrams
        case notes
        case selectedTemplateID
        case postMealSymptomSeverity
        case postMealSymptomNote
        case postMealFeedbackTimestamp
        case nutritionImportID
        case barcode
        case sourceLabel
        case calories
        case fiberGrams
        case sugarGrams
        case servingText
        case mealSource
        case photoLocalPath
        case confidenceScore
        case userConfirmed
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            timestamp: timestamp,
            mealType: try container.decode(MealType.self, forKey: .mealType),
            mealDescription: try container.decode(String.self, forKey: .mealDescription),
            glycemicImpact: try container.decode(GlycemicImpact.self, forKey: .glycemicImpact),
            photoData: try container.decodeIfPresent(Data.self, forKey: .photoData),
            carbsGrams: try container.decodeIfPresent(Double.self, forKey: .carbsGrams),
            proteinGrams: try container.decodeIfPresent(Double.self, forKey: .proteinGrams),
            fatGrams: try container.decodeIfPresent(Double.self, forKey: .fatGrams),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            selectedTemplateID: try container.decodeIfPresent(String.self, forKey: .selectedTemplateID),
            postMealSymptomSeverity: try container.decodeIfPresent(Int.self, forKey: .postMealSymptomSeverity),
            postMealSymptomNote: try container.decodeIfPresent(String.self, forKey: .postMealSymptomNote),
            postMealFeedbackTimestamp: try container.decodeIfPresent(Date.self, forKey: .postMealFeedbackTimestamp),
            nutritionImportID: try container.decodeIfPresent(UUID.self, forKey: .nutritionImportID),
            barcode: try container.decodeIfPresent(String.self, forKey: .barcode),
            sourceLabel: try container.decodeIfPresent(String.self, forKey: .sourceLabel),
            calories: try container.decodeIfPresent(Double.self, forKey: .calories),
            fiberGrams: try container.decodeIfPresent(Double.self, forKey: .fiberGrams),
            sugarGrams: try container.decodeIfPresent(Double.self, forKey: .sugarGrams),
            servingText: try container.decodeIfPresent(String.self, forKey: .servingText),
            mealSource: try container.decodeIfPresent(String.self, forKey: .mealSource),
            photoLocalPath: try container.decodeIfPresent(String.self, forKey: .photoLocalPath),
            confidenceScore: try container.decodeIfPresent(Double.self, forKey: .confidenceScore),
            userConfirmed: try container.decodeIfPresent(Bool.self, forKey: .userConfirmed) ?? false,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? timestamp,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? timestamp
        )
    }
}

struct MealScanFoodItemRecord: Codable, Sendable {
    var id: UUID
    var mealId: UUID
    var displayName: String
    var canonicalFoodId: String?
    var nutritionSource: NutritionDataSource
    var estimatedGrams: Double
    var estimatedVolumeMl: Double?
    var servingDescription: String?
    var caloriesKcal: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var netCarbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sugarGrams: Double
    var sodiumMg: Double
    var saturatedFatGrams: Double
    var confidenceScore: Double
    var detectionSource: String?
    var portionEstimationMethod: PortionEstimationMethod
    var wasUserEdited: Bool
    var wasPortionAdjusted: Bool?
    var warning: String?
    var createdAt: Date
    var updatedAt: Date
}

struct MealScanNutritionSummaryRecord: Codable, Sendable {
    var id: UUID
    var mealId: UUID
    var caloriesKcal: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var netCarbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sugarGrams: Double
    var sodiumMg: Double
    var saturatedFatGrams: Double
    var confidenceScore: Double
    var estimatedGlycemicImpact: GlycemicImpactLevel
    var nutritionSourceSummary: String
    var createdAt: Date
    var updatedAt: Date
}

struct MealScanMetadataRecord: Codable, Sendable {
    var id: UUID
    var mealId: UUID
    var originalPredictionJSON: String
    var finalUserConfirmedJSON: String
    var modelVersion: String
    var pipelineVersion: String
    var userConfirmed: Bool
    var hasUserEdits: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct HairPhotoEntryRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var photoType: HairPhotoType
    var photoData: Data
    var notes: String?
    var analysisResult: String?
}

struct DailyLogRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var weight: Double?
    var sleepHours: Double?
    var activeMinutes: Int?
    var restingHeartRateBPM: Double?
    var stressLevel: Int?
    var energyLevel: Int?
    var waterOz: Int?
}

struct InsightRecord: Codable, Sendable {
    var id: UUID
    var generatedDate: Date
    var insightType: InsightType
    var title: String
    var content: String
    var scientificContent: String? = nil
    var confidence: Double
    var dataPointsUsed: Int
    var actionable: Bool
    var relatedSymptoms: [String]
    var phaseContext: CyclePhase?
    var recommendedActions: [String] = []
    var learnMoreTopic: String?
}

extension InsightRecord {
    private enum CodingKeys: String, CodingKey {
        case id
        case generatedDate
        case insightType
        case title
        case content
        case scientificContent
        case confidence
        case dataPointsUsed
        case actionable
        case relatedSymptoms
        case phaseContext
        case recommendedActions
        case learnMoreTopic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.generatedDate = try container.decode(Date.self, forKey: .generatedDate)
        self.insightType = try container.decode(InsightType.self, forKey: .insightType)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.scientificContent = try container.decodeIfPresent(String.self, forKey: .scientificContent)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
        self.dataPointsUsed = try container.decode(Int.self, forKey: .dataPointsUsed)
        self.actionable = try container.decode(Bool.self, forKey: .actionable)
        self.relatedSymptoms = try container.decode([String].self, forKey: .relatedSymptoms)
        self.phaseContext = try container.decodeIfPresent(CyclePhase.self, forKey: .phaseContext)
        self.recommendedActions = try container.decodeIfPresent([String].self, forKey: .recommendedActions) ?? []
        self.learnMoreTopic = try container.decodeIfPresent(String.self, forKey: .learnMoreTopic)
    }
}

struct PregnancyRecordDTO: Codable, Sendable {
    var id: UUID
    var startDate: Date
    var estimatedDueDate: Date?
    var endDate: Date?
    var endReason: PregnancyEndReason?
    var isActive: Bool
    var notes: String?
}

struct OvulationObservationRecord: Codable, Sendable {
    var id: UUID
    var date: Date
    var basalBodyTemperatureCelsius: Double?
    var cervicalMucus: CervicalMucusType?
    var lhTestResult: LHTestResult?
    var notes: String?
    var createdAt: Date
}

struct NutritionImportRecordDTO: Codable, Sendable {
    var id: UUID
    var sourceKind: NutritionImportSourceKind
    var sourceName: String?
    var externalIdentifier: String?
    var startDate: Date
    var endDate: Date?
    var barcode: String?
    var productName: String?
    var brandName: String?
    var servingText: String?
    var calories: Double?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var waterOz: Double?
    var sodiumMg: Double?
    var saturatedFatGrams: Double?
    var cholesterolMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var confidence: Double
    var completeness: Double
    var importedAt: Date
    var reviewStatus: NutritionImportReviewStatus
    var userReviewed: Bool
    var notes: String?
}

struct HealthKitImportedSampleRecordDTO: Codable, Sendable {
    var id: UUID
    var sampleUUID: String
    var healthKitIdentifier: String
    var sourceName: String
    var sourceBundleIdentifier: String?
    var startDate: Date
    var endDate: Date?
    var valueDouble: Double?
    var valueUnit: String?
    var categoryValue: Int?
    var derivedRecordKind: HealthKitDerivedRecordKind
    var derivedRecordID: UUID?
    var importedAt: Date
    var notes: String?
}

enum SettingsDataBackupCoding {
    private static func makeFractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func makeStandardFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = makeFractionalFormatter()
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let fractionalFormatter = makeFractionalFormatter()
            let standardFormatter = makeStandardFormatter()
            let container = try decoder.singleValueContainer()
            let rawDate = try container.decode(String.self)

            if let date = fractionalFormatter.date(from: rawDate) {
                return date
            }

            if let date = standardFormatter.date(from: rawDate) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawDate)"
            )
        }
        return decoder
    }
}

extension JSONEncoder {
    static var cycleBalanceBackup: JSONEncoder {
        SettingsDataBackupCoding.makeEncoder()
    }
}

extension JSONDecoder {
    static var cycleBalanceBackup: JSONDecoder {
        SettingsDataBackupCoding.makeDecoder()
    }
}
