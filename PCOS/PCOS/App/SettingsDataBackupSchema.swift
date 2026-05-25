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
    }
}

struct SettingsDataBackupFile: Codable, Sendable {
    static let currentSchemaVersion = 2

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
            pregnancyRecords: pregnancyRecords.count
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
