import Foundation
import SwiftData
import os

@MainActor
struct SettingsDataImportService {
    enum ImportChannel: Equatable, Sendable {
        case jsonBackup(schemaVersion: Int, source: SettingsDataBackupSource)
        case externalCSV
    }

    struct ImportIssue: Equatable, Sendable {
        var location: String?
        var reason: String

        var message: String {
            guard let location, !location.isEmpty else {
                return reason
            }

            return "\(location): \(reason)"
        }
    }

    struct ImportChangeCounts: Equatable, Sendable {
        var inserted: Int = 0
        var updated: Int = 0
        var skipped: Int = 0
        var rejected: Int = 0

        var processed: Int {
            inserted + updated + skipped + rejected
        }

        var successful: Int {
            inserted + updated + skipped
        }
    }

    enum ImportError: LocalizedError, Equatable {
        case unsupportedSchemaVersion(expected: Int, actual: Int)
        case malformedBackup(String)
        case danglingCycleReference(UUID)
        case danglingCycleEntryReference(UUID)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let expected, let actual):
                String(
                    localized: "This backup uses schema v\(actual). This app currently supports v\(expected).",
                    comment: "Backup import error shown when the selected backup file uses a newer or older schema version."
                )
            case .malformedBackup(let reason):
                String(
                    localized: "Backup data is invalid: \(reason)",
                    comment: "Backup import error shown when the selected backup file is malformed."
                )
            case .danglingCycleReference(let cycleID):
                String(
                    localized: "Backup references missing cycle \(cycleID.uuidString).",
                    comment: "Backup import error shown when imported data references a missing cycle record."
                )
            case .danglingCycleEntryReference(let cycleEntryID):
                String(
                    localized: "Backup references missing cycle entry \(cycleEntryID.uuidString).",
                    comment: "Backup import error shown when imported data references a missing cycle entry record."
                )
            }
        }
    }

    struct ImportSummary: Equatable, Sendable {
        var importedAt: Date
        var channel: ImportChannel
        var counts: SettingsDataRecordCounts
        var changeCounts: ImportChangeCounts
        var issues: [ImportIssue] = []

        var schemaVersion: Int? {
            guard case let .jsonBackup(schemaVersion, _) = channel else {
                return nil
            }

            return schemaVersion
        }

        var backupSource: SettingsDataBackupSource? {
            guard case let .jsonBackup(_, source) = channel else {
                return nil
            }

            return source
        }

        var hasIssues: Bool {
            !issues.isEmpty
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importJSONBackup(
        from url: URL
    ) throws -> ImportSummary {
        let data = try Data(contentsOf: url)
        return try importJSONBackup(data: data)
    }

    func importJSONBackup(
        data: Data
    ) throws -> ImportSummary {
        let parsed = try lenientlyParseJSONBackup(data: data)

        guard parsed.records.counts.total > 0 || parsed.issues.isEmpty else {
            return ImportSummary(
                importedAt: Date(),
                channel: .jsonBackup(schemaVersion: parsed.schemaVersion, source: parsed.source),
                counts: parsed.records.counts,
                changeCounts: ImportChangeCounts(rejected: parsed.issues.count),
                issues: parsed.issues
            )
        }

        var summary = try replaceAll(with: parsed.backup)
        summary.issues = parsed.issues
        summary.changeCounts.rejected = parsed.issues.count
        return summary
    }

    func importBackupData(_ data: Data) throws -> ImportSummary {
        try importJSONBackup(data: data)
    }

    func replaceAll(
        with backup: SettingsDataBackupFile
    ) throws -> ImportSummary {
        guard (1...SettingsDataBackupFile.currentSchemaVersion).contains(backup.schemaVersion) else {
            throw ImportError.unsupportedSchemaVersion(
                expected: SettingsDataBackupFile.currentSchemaVersion,
                actual: backup.schemaVersion
            )
        }

        do {
            try validateReferences(in: backup.records)
            try clearAllTrackedModels()
            let counts = try importRecords(from: backup.records)
            try modelContext.save()

            Logger.database.info("Imported backup with \(counts.total) records (schema v\(backup.schemaVersion))")
            return ImportSummary(
                importedAt: Date(),
                channel: .jsonBackup(schemaVersion: backup.schemaVersion, source: backup.source),
                counts: counts,
                changeCounts: ImportChangeCounts(inserted: counts.total)
            )
        } catch let importError as ImportError {
            modelContext.rollback()
            throw importError
        } catch {
            modelContext.rollback()
            throw ImportError.malformedBackup(Self.malformedBackupReason(from: error))
        }
    }
}

#if DEBUG
extension SettingsDataImportService {
    static func uiTestFixture(named rawValue: String) -> Data? {
        switch rawValue {
        case "valid":
            let backup = SettingsDataBackupFile(
                exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                appVersion: "1.0.0",
                source: .userExport,
                records: SettingsDataBackupRecords(
                    cycles: [
                        CycleRecord(
                            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
                            startDate: Date(timeIntervalSince1970: 1_699_913_600),
                            endDate: Date(timeIntervalSince1970: 1_700_172_800),
                            lengthDays: 30,
                            isPredicted: false,
                            manualCycleLengthOverrideDays: nil,
                            ovulationStatus: .unknown
                        )
                    ]
                )
            )
            return try? SettingsDataBackupCoding.makeEncoder().encode(backup)
        case "invalid":
            let json = """
            {
              "appVersion":"1.0.0",
              "exportedAt":"2026-03-12T14:30:00Z",
              "records":{
                "bloodSugarReadings":[],
                "cycleEntries":[
                  {
                    "createdAt":"2026-03-10T12:00:00Z",
                    "cycleID":null,
                    "cyclePhase":"menstrual",
                    "date":"2026-03-10T12:00:00Z",
                    "flowIntensity":"invalid_flow",
                    "id":"22222222-2222-2222-2222-222222222222",
                    "isPeriodDay":true,
                    "notes":null
                  }
                ],
                "cycles":[],
                "dailyLogs":[],
                "hairPhotos":[],
                "insights":[],
                "meals":[],
                "supplements":[],
                "symptoms":[]
              },
              "schemaVersion":1,
              "source":{"kind":"user_export","scenarioID":null}
            }
            """
            return Data(json.utf8)
        case "unsupported_schema":
            let backup = SettingsDataBackupFile(
                schemaVersion: 99,
                exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
                appVersion: "1.0.0",
                source: .userExport,
                records: SettingsDataBackupRecords()
            )
            return try? SettingsDataBackupCoding.makeEncoder().encode(backup)
        default:
            return nil
        }
    }
}
#endif

private extension SettingsDataImportService {
    typealias JSONObject = [String: Any]

    struct Located<Record> {
        var location: String
        var value: Record
    }

    struct ParsedJSONBackup {
        var schemaVersion: Int
        var source: SettingsDataBackupSource
        var records: SettingsDataBackupRecords
        var issues: [ImportIssue]

        var backup: SettingsDataBackupFile {
            SettingsDataBackupFile(
                schemaVersion: schemaVersion,
                exportedAt: exportedAt,
                appVersion: appVersion,
                source: source,
                records: records
            )
        }

        private let exportedAt: Date
        private let appVersion: String

        init(
            schemaVersion: Int,
            exportedAt: Date,
            appVersion: String,
            source: SettingsDataBackupSource,
            records: SettingsDataBackupRecords,
            issues: [ImportIssue]
        ) {
            self.schemaVersion = schemaVersion
            self.exportedAt = exportedAt
            self.appVersion = appVersion
            self.source = source
            self.records = records
            self.issues = issues
        }
    }

    enum RecordValidationError: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let reason):
                reason
            }
        }
    }

    func lenientlyParseJSONBackup(data: Data) throws -> ParsedJSONBackup {
        let jsonObject: Any

        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ImportError.malformedBackup(Self.malformedBackupReason(from: error))
        }

        guard let root = jsonObject as? JSONObject else {
            throw ImportError.malformedBackup("root: expected JSON object")
        }

        let schemaVersion = intValue(root["schemaVersion"]) ?? 1
        guard (1...SettingsDataBackupFile.currentSchemaVersion).contains(schemaVersion) else {
            throw ImportError.unsupportedSchemaVersion(
                expected: SettingsDataBackupFile.currentSchemaVersion,
                actual: schemaVersion
            )
        }

        let exportedAt = (try? requiredDate(field: "exportedAt", in: root, location: "root")) ?? Date()
        let appVersion = stringValue(root["appVersion"]) ?? "unknown"
        let source = parseBackupSource(from: root["source"])

        let recordsObject: JSONObject
        if let rawRecords = root["records"] {
            guard let object = rawRecords as? JSONObject else {
                throw ImportError.malformedBackup("records: expected object")
            }
            recordsObject = object
        } else {
            recordsObject = [:]
        }

        var issues: [ImportIssue] = []

        let cycles = try decodeArray(recordsObject["cycles"], collection: "cycles", issues: &issues, decode: parseCycleRecord)
        let cycleEntries = try decodeArray(recordsObject["cycleEntries"], collection: "cycleEntries", issues: &issues, decode: parseCycleEntryRecord)
        let symptoms = try decodeArray(recordsObject["symptoms"], collection: "symptoms", issues: &issues, decode: parseSymptomRecord)
        let bloodSugarReadings = try decodeArray(recordsObject["bloodSugarReadings"], collection: "bloodSugarReadings", issues: &issues, decode: parseBloodSugarRecord)
        let supplements = try decodeArray(recordsObject["supplements"], collection: "supplements", issues: &issues, decode: parseSupplementRecord)
        let meals = try decodeArray(recordsObject["meals"], collection: "meals", issues: &issues, decode: parseMealRecord)
        let hairPhotos = try decodeArray(recordsObject["hairPhotos"], collection: "hairPhotos", issues: &issues, decode: parseHairPhotoRecord)
        let dailyLogs = try decodeArray(recordsObject["dailyLogs"], collection: "dailyLogs", issues: &issues, decode: parseDailyLogRecord)
        let insights = try decodeArray(recordsObject["insights"], collection: "insights", issues: &issues, decode: parseInsightRecord)
        let pregnancyRecords = try decodeArray(recordsObject["pregnancyRecords"], collection: "pregnancyRecords", issues: &issues, decode: parsePregnancyRecord)
        let ovulationObservations = try decodeArray(recordsObject["ovulationObservations"], collection: "ovulationObservations", issues: &issues, decode: parseOvulationObservationRecord)
        let nutritionImports = try decodeArray(recordsObject["nutritionImports"], collection: "nutritionImports", issues: &issues, decode: parseNutritionImportRecord)
        let mealScanFoodItems = try decodeArray(recordsObject["mealScanFoodItems"], collection: "mealScanFoodItems", issues: &issues, decode: parseMealScanFoodItemRecord)
        let mealScanNutritionSummaries = try decodeArray(recordsObject["mealScanNutritionSummaries"], collection: "mealScanNutritionSummaries", issues: &issues, decode: parseMealScanNutritionSummaryRecord)
        let mealScanMetadata = try decodeArray(recordsObject["mealScanMetadata"], collection: "mealScanMetadata", issues: &issues, decode: parseMealScanMetadataRecord)
        let healthKitImportedSamples = try decodeArray(recordsObject["healthKitImportedSamples"], collection: "healthKitImportedSamples", issues: &issues, decode: parseHealthKitImportedSampleRecord)

        let filtered = filterInvalidReferences(
            cycles: cycles,
            cycleEntries: cycleEntries,
            symptoms: symptoms
        )
        issues.append(contentsOf: filtered.issues)

        let records = SettingsDataBackupRecords(
            cycles: filtered.cycles.map(\.value),
            cycleEntries: filtered.cycleEntries.map(\.value),
            symptoms: filtered.symptoms.map(\.value),
            bloodSugarReadings: bloodSugarReadings.map(\.value),
            supplements: supplements.map(\.value),
            meals: meals.map(\.value),
            hairPhotos: hairPhotos.map(\.value),
            dailyLogs: dailyLogs.map(\.value),
            insights: insights.map(\.value),
            pregnancyRecords: pregnancyRecords.map(\.value),
            ovulationObservations: ovulationObservations.map(\.value),
            nutritionImports: nutritionImports.map(\.value),
            mealScanFoodItems: mealScanFoodItems.map(\.value),
            mealScanNutritionSummaries: mealScanNutritionSummaries.map(\.value),
            mealScanMetadata: mealScanMetadata.map(\.value),
            healthKitImportedSamples: healthKitImportedSamples.map(\.value)
        )

        return ParsedJSONBackup(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            appVersion: appVersion,
            source: source,
            records: records,
            issues: issues
        )
    }

    func parseBackupSource(from rawValue: Any?) -> SettingsDataBackupSource {
        guard let sourceObject = rawValue as? JSONObject else {
            return .userExport
        }

        let kind = SettingsDataBackupSource.Kind(rawValue: stringValue(sourceObject["kind"]) ?? "")
            ?? .userExport
        return SettingsDataBackupSource(
            kind: kind,
            scenarioID: stringValue(sourceObject["scenarioID"])
        )
    }

    func decodeArray<Record>(
        _ rawValue: Any?,
        collection: String,
        issues: inout [ImportIssue],
        decode: (JSONObject, String) throws -> Record
    ) throws -> [Located<Record>] {
        guard let rawValue else {
            return []
        }

        guard let array = rawValue as? [Any] else {
            throw ImportError.malformedBackup("records.\(collection): expected array")
        }

        var decoded: [Located<Record>] = []

        for (index, rawRecord) in array.enumerated() {
            let location = "\(collection)[\(index)]"

            guard let object = rawRecord as? JSONObject else {
                issues.append(ImportIssue(location: location, reason: "Expected an object."))
                continue
            }

            do {
                decoded.append(Located(location: location, value: try decode(object, location)))
            } catch let validationError as RecordValidationError {
                issues.append(ImportIssue(location: location, reason: validationError.errorDescription ?? "Invalid record."))
            } catch {
                issues.append(ImportIssue(location: location, reason: error.localizedDescription))
            }
        }

        return decoded
    }

    func filterInvalidReferences(
        cycles: [Located<CycleRecord>],
        cycleEntries: [Located<CycleEntryRecord>],
        symptoms: [Located<SymptomEntryRecord>]
    ) -> (
        cycles: [Located<CycleRecord>],
        cycleEntries: [Located<CycleEntryRecord>],
        symptoms: [Located<SymptomEntryRecord>],
        issues: [ImportIssue]
    ) {
        let cycleIDs = Set(cycles.map(\.value.id))

        var issues: [ImportIssue] = []
        var filteredCycleEntries: [Located<CycleEntryRecord>] = []
        for entry in cycleEntries {
            guard let cycleID = entry.value.cycleID else {
                filteredCycleEntries.append(entry)
                continue
            }

            guard cycleIDs.contains(cycleID) else {
                issues.append(
                    ImportIssue(
                        location: entry.location,
                        reason: "References missing or rejected cycle \(cycleID.uuidString)."
                    )
                )
                continue
            }

            filteredCycleEntries.append(entry)
        }

        let cycleEntryIDs = Set(filteredCycleEntries.map(\.value.id))
        var filteredSymptoms: [Located<SymptomEntryRecord>] = []
        for symptom in symptoms {
            guard let cycleEntryID = symptom.value.cycleEntryID else {
                filteredSymptoms.append(symptom)
                continue
            }

            guard cycleEntryIDs.contains(cycleEntryID) else {
                issues.append(
                    ImportIssue(
                        location: symptom.location,
                        reason: "References missing or rejected cycle entry \(cycleEntryID.uuidString)."
                    )
                )
                continue
            }

            filteredSymptoms.append(symptom)
        }

        return (cycles, filteredCycleEntries, filteredSymptoms, issues)
    }

    func parseCycleRecord(_ object: JSONObject, location: String) throws -> CycleRecord {
        CycleRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            startDate: try requiredDate(field: "startDate", in: object, location: location),
            endDate: try optionalDate(field: "endDate", in: object, location: location),
            lengthDays: try optionalInt(field: "lengthDays", in: object, location: location),
            isPredicted: try optionalBool(field: "isPredicted", in: object, location: location) ?? false,
            manualCycleLengthOverrideDays: try optionalInt(field: "manualCycleLengthOverrideDays", in: object, location: location),
            ovulationStatus: try optionalEnum(field: "ovulationStatus", in: object, location: location, as: OvulationStatus.self),
            endReason: try optionalEnum(field: "endReason", in: object, location: location, as: CycleEndReason.self)
        )
    }

    func parseCycleEntryRecord(_ object: JSONObject, location: String) throws -> CycleEntryRecord {
        let date = try requiredDate(field: "date", in: object, location: location)

        return CycleEntryRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: date,
            flowIntensity: try optionalEnum(field: "flowIntensity", in: object, location: location, as: FlowIntensity.self),
            isPeriodDay: try optionalBool(field: "isPeriodDay", in: object, location: location) ?? false,
            cyclePhase: try optionalEnum(field: "cyclePhase", in: object, location: location, as: CyclePhase.self),
            notes: try optionalString(field: "notes", in: object, location: location),
            createdAt: try optionalDate(field: "createdAt", in: object, location: location) ?? date,
            cycleID: try optionalUUID(field: "cycleID", in: object, location: location)
        )
    }

    func parseSymptomRecord(_ object: JSONObject, location: String) throws -> SymptomEntryRecord {
        let symptomType = try requiredEnum(field: "symptomType", in: object, location: location, as: SymptomType.self)
        let severity = try requiredInt(field: "severity", in: object, location: location)
        guard (1...5).contains(severity) else {
            throw RecordValidationError.invalid("Invalid severity. Expected a value between 1 and 5.")
        }

        return SymptomEntryRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: try requiredDate(field: "date", in: object, location: location),
            category: try optionalEnum(field: "category", in: object, location: location, as: SymptomCategory.self) ?? symptomType.category,
            symptomType: symptomType,
            severity: severity,
            notes: try optionalString(field: "notes", in: object, location: location),
            cycleEntryID: try optionalUUID(field: "cycleEntryID", in: object, location: location)
        )
    }

    func parseBloodSugarRecord(_ object: JSONObject, location: String) throws -> BloodSugarReadingRecord {
        BloodSugarReadingRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            timestamp: try requiredDate(field: "timestamp", in: object, location: location),
            glucoseValue: try requiredDouble(field: "glucoseValue", in: object, location: location),
            readingType: try requiredEnum(field: "readingType", in: object, location: location, as: GlucoseReadingType.self),
            mealContext: try optionalString(field: "mealContext", in: object, location: location),
            fromHealthKit: try optionalBool(field: "fromHealthKit", in: object, location: location) ?? false,
            notes: try optionalString(field: "notes", in: object, location: location)
        )
    }

    func parseSupplementRecord(_ object: JSONObject, location: String) throws -> SupplementLogRecord {
        SupplementLogRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: try requiredDate(field: "date", in: object, location: location),
            supplementName: try requiredString(field: "supplementName", in: object, location: location),
            dosageMg: try optionalDouble(field: "dosageMg", in: object, location: location),
            timeTaken: try requiredDate(field: "timeTaken", in: object, location: location),
            taken: try optionalBool(field: "taken", in: object, location: location) ?? true,
            brand: try optionalString(field: "brand", in: object, location: location)
        )
    }

    func parseMealRecord(_ object: JSONObject, location: String) throws -> MealEntryRecord {
        let timestamp = try requiredDate(field: "timestamp", in: object, location: location)
        return MealEntryRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            timestamp: timestamp,
            mealType: try requiredEnum(field: "mealType", in: object, location: location, as: MealType.self),
            mealDescription: try requiredString(field: "mealDescription", in: object, location: location),
            glycemicImpact: try requiredEnum(field: "glycemicImpact", in: object, location: location, as: GlycemicImpact.self),
            photoData: try optionalData(field: "photoData", in: object, location: location),
            carbsGrams: try optionalDouble(field: "carbsGrams", in: object, location: location),
            proteinGrams: try optionalDouble(field: "proteinGrams", in: object, location: location),
            fatGrams: try optionalDouble(field: "fatGrams", in: object, location: location),
            notes: try optionalString(field: "notes", in: object, location: location),
            selectedTemplateID: try optionalString(field: "selectedTemplateID", in: object, location: location),
            postMealSymptomSeverity: try optionalInt(field: "postMealSymptomSeverity", in: object, location: location),
            postMealSymptomNote: try optionalString(field: "postMealSymptomNote", in: object, location: location),
            postMealFeedbackTimestamp: try optionalDate(field: "postMealFeedbackTimestamp", in: object, location: location),
            nutritionImportID: try optionalUUID(field: "nutritionImportID", in: object, location: location),
            barcode: try optionalString(field: "barcode", in: object, location: location),
            sourceLabel: try optionalString(field: "sourceLabel", in: object, location: location),
            calories: try optionalDouble(field: "calories", in: object, location: location),
            fiberGrams: try optionalDouble(field: "fiberGrams", in: object, location: location),
            sugarGrams: try optionalDouble(field: "sugarGrams", in: object, location: location),
            servingText: try optionalString(field: "servingText", in: object, location: location),
            mealSource: try optionalString(field: "mealSource", in: object, location: location),
            photoLocalPath: try optionalString(field: "photoLocalPath", in: object, location: location),
            confidenceScore: try optionalDouble(field: "confidenceScore", in: object, location: location),
            userConfirmed: try optionalBool(field: "userConfirmed", in: object, location: location) ?? false,
            createdAt: try optionalDate(field: "createdAt", in: object, location: location) ?? timestamp,
            updatedAt: try optionalDate(field: "updatedAt", in: object, location: location) ?? timestamp
        )
    }

    func parseHairPhotoRecord(_ object: JSONObject, location: String) throws -> HairPhotoEntryRecord {
        HairPhotoEntryRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: try requiredDate(field: "date", in: object, location: location),
            photoType: try requiredEnum(field: "photoType", in: object, location: location, as: HairPhotoType.self),
            photoData: try requiredData(field: "photoData", in: object, location: location),
            notes: try optionalString(field: "notes", in: object, location: location),
            analysisResult: try optionalString(field: "analysisResult", in: object, location: location)
        )
    }

    func parseDailyLogRecord(_ object: JSONObject, location: String) throws -> DailyLogRecord {
        let stressLevel = try optionalInt(field: "stressLevel", in: object, location: location)
        if let stressLevel, !(1...5).contains(stressLevel) {
            throw RecordValidationError.invalid("Invalid stressLevel. Expected a value between 1 and 5.")
        }

        let energyLevel = try optionalInt(field: "energyLevel", in: object, location: location)
        if let energyLevel, !(1...5).contains(energyLevel) {
            throw RecordValidationError.invalid("Invalid energyLevel. Expected a value between 1 and 5.")
        }

        return DailyLogRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: try requiredDate(field: "date", in: object, location: location),
            weight: try optionalDouble(field: "weight", in: object, location: location),
            sleepHours: try optionalDouble(field: "sleepHours", in: object, location: location),
            activeMinutes: try optionalInt(field: "activeMinutes", in: object, location: location),
            restingHeartRateBPM: try optionalDouble(field: "restingHeartRateBPM", in: object, location: location),
            stressLevel: stressLevel,
            energyLevel: energyLevel,
            waterOz: try optionalInt(field: "waterOz", in: object, location: location)
        )
    }

    func parseInsightRecord(_ object: JSONObject, location: String) throws -> InsightRecord {
        InsightRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            generatedDate: try requiredDate(field: "generatedDate", in: object, location: location),
            insightType: try requiredEnum(field: "insightType", in: object, location: location, as: InsightType.self),
            title: try requiredString(field: "title", in: object, location: location),
            content: try requiredString(field: "content", in: object, location: location),
            scientificContent: try optionalString(field: "scientificContent", in: object, location: location),
            confidence: try optionalDouble(field: "confidence", in: object, location: location) ?? 0,
            dataPointsUsed: try optionalInt(field: "dataPointsUsed", in: object, location: location) ?? 0,
            actionable: try optionalBool(field: "actionable", in: object, location: location) ?? true,
            relatedSymptoms: try optionalStringArray(field: "relatedSymptoms", in: object, location: location) ?? [],
            phaseContext: try optionalEnum(field: "phaseContext", in: object, location: location, as: CyclePhase.self),
            recommendedActions: try optionalStringArray(field: "recommendedActions", in: object, location: location) ?? [],
            learnMoreTopic: try optionalString(field: "learnMoreTopic", in: object, location: location)
        )
    }

    func parsePregnancyRecord(_ object: JSONObject, location: String) throws -> PregnancyRecordDTO {
        PregnancyRecordDTO(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            startDate: try requiredDate(field: "startDate", in: object, location: location),
            estimatedDueDate: try optionalDate(field: "estimatedDueDate", in: object, location: location),
            endDate: try optionalDate(field: "endDate", in: object, location: location),
            endReason: try optionalEnum(field: "endReason", in: object, location: location, as: PregnancyEndReason.self),
            isActive: try optionalBool(field: "isActive", in: object, location: location) ?? true,
            notes: try optionalString(field: "notes", in: object, location: location)
        )
    }

    func parseOvulationObservationRecord(_ object: JSONObject, location: String) throws -> OvulationObservationRecord {
        let date = try requiredDate(field: "date", in: object, location: location)
        return OvulationObservationRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            date: date,
            basalBodyTemperatureCelsius: try optionalDouble(field: "basalBodyTemperatureCelsius", in: object, location: location),
            cervicalMucus: try optionalEnum(field: "cervicalMucus", in: object, location: location, as: CervicalMucusType.self),
            lhTestResult: try optionalEnum(field: "lhTestResult", in: object, location: location, as: LHTestResult.self),
            notes: try optionalString(field: "notes", in: object, location: location),
            createdAt: try optionalDate(field: "createdAt", in: object, location: location) ?? date
        )
    }

    func parseNutritionImportRecord(_ object: JSONObject, location: String) throws -> NutritionImportRecordDTO {
        let startDate = try requiredDate(field: "startDate", in: object, location: location)
        let importedAt = try optionalDate(field: "importedAt", in: object, location: location) ?? startDate
        let reviewStatus = try optionalEnum(
            field: "reviewStatus",
            in: object,
            location: location,
            as: NutritionImportReviewStatus.self
        ) ?? .needsReview
        return NutritionImportRecordDTO(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            sourceKind: try optionalEnum(
                field: "sourceKind",
                in: object,
                location: location,
                as: NutritionImportSourceKind.self
            ) ?? .manualReview,
            sourceName: try optionalString(field: "sourceName", in: object, location: location),
            externalIdentifier: try optionalString(field: "externalIdentifier", in: object, location: location),
            startDate: startDate,
            endDate: try optionalDate(field: "endDate", in: object, location: location),
            barcode: try optionalString(field: "barcode", in: object, location: location),
            productName: try optionalString(field: "productName", in: object, location: location),
            brandName: try optionalString(field: "brandName", in: object, location: location),
            servingText: try optionalString(field: "servingText", in: object, location: location),
            calories: try optionalDouble(field: "calories", in: object, location: location),
            carbsGrams: try optionalDouble(field: "carbsGrams", in: object, location: location),
            proteinGrams: try optionalDouble(field: "proteinGrams", in: object, location: location),
            fatGrams: try optionalDouble(field: "fatGrams", in: object, location: location),
            fiberGrams: try optionalDouble(field: "fiberGrams", in: object, location: location),
            sugarGrams: try optionalDouble(field: "sugarGrams", in: object, location: location),
            waterOz: try optionalDouble(field: "waterOz", in: object, location: location),
            sodiumMg: try optionalDouble(field: "sodiumMg", in: object, location: location),
            saturatedFatGrams: try optionalDouble(field: "saturatedFatGrams", in: object, location: location),
            cholesterolMg: try optionalDouble(field: "cholesterolMg", in: object, location: location),
            potassiumMg: try optionalDouble(field: "potassiumMg", in: object, location: location),
            calciumMg: try optionalDouble(field: "calciumMg", in: object, location: location),
            ironMg: try optionalDouble(field: "ironMg", in: object, location: location),
            confidence: try optionalDouble(field: "confidence", in: object, location: location) ?? 0,
            completeness: try optionalDouble(field: "completeness", in: object, location: location) ?? 0,
            importedAt: importedAt,
            reviewStatus: reviewStatus,
            userReviewed: try optionalBool(field: "userReviewed", in: object, location: location) ?? (reviewStatus == .reviewed),
            notes: try optionalString(field: "notes", in: object, location: location)
        )
    }

    func parseHealthKitImportedSampleRecord(_ object: JSONObject, location: String) throws -> HealthKitImportedSampleRecordDTO {
        let startDate = try requiredDate(field: "startDate", in: object, location: location)
        return HealthKitImportedSampleRecordDTO(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            sampleUUID: try requiredString(field: "sampleUUID", in: object, location: location),
            healthKitIdentifier: try requiredString(field: "healthKitIdentifier", in: object, location: location),
            sourceName: try optionalString(field: "sourceName", in: object, location: location) ?? "Apple Health",
            sourceBundleIdentifier: try optionalString(field: "sourceBundleIdentifier", in: object, location: location),
            startDate: startDate,
            endDate: try optionalDate(field: "endDate", in: object, location: location),
            valueDouble: try optionalDouble(field: "valueDouble", in: object, location: location),
            valueUnit: try optionalString(field: "valueUnit", in: object, location: location),
            categoryValue: try optionalInt(field: "categoryValue", in: object, location: location),
            derivedRecordKind: try optionalEnum(field: "derivedRecordKind", in: object, location: location, as: HealthKitDerivedRecordKind.self) ?? .sourceOnly,
            derivedRecordID: try optionalUUID(field: "derivedRecordID", in: object, location: location),
            importedAt: try optionalDate(field: "importedAt", in: object, location: location) ?? startDate,
            notes: try optionalString(field: "notes", in: object, location: location)
        )
    }

    func parseMealScanFoodItemRecord(_ object: JSONObject, location: String) throws -> MealScanFoodItemRecord {
        let createdAt = try optionalDate(field: "createdAt", in: object, location: location) ?? Date()
        return MealScanFoodItemRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            mealId: try requiredUUID(field: "mealId", in: object, location: location),
            displayName: try requiredString(field: "displayName", in: object, location: location),
            canonicalFoodId: try optionalString(field: "canonicalFoodId", in: object, location: location),
            nutritionSource: try optionalEnum(field: "nutritionSource", in: object, location: location, as: NutritionDataSource.self) ?? .appFixture,
            estimatedGrams: try optionalDouble(field: "estimatedGrams", in: object, location: location) ?? 0,
            estimatedVolumeMl: try optionalDouble(field: "estimatedVolumeMl", in: object, location: location),
            servingDescription: try optionalString(field: "servingDescription", in: object, location: location),
            caloriesKcal: try optionalDouble(field: "caloriesKcal", in: object, location: location) ?? 0,
            proteinGrams: try optionalDouble(field: "proteinGrams", in: object, location: location) ?? 0,
            carbsGrams: try optionalDouble(field: "carbsGrams", in: object, location: location) ?? 0,
            netCarbsGrams: try optionalDouble(field: "netCarbsGrams", in: object, location: location) ?? 0,
            fatGrams: try optionalDouble(field: "fatGrams", in: object, location: location) ?? 0,
            fiberGrams: try optionalDouble(field: "fiberGrams", in: object, location: location) ?? 0,
            sugarGrams: try optionalDouble(field: "sugarGrams", in: object, location: location) ?? 0,
            sodiumMg: try optionalDouble(field: "sodiumMg", in: object, location: location) ?? 0,
            saturatedFatGrams: try optionalDouble(field: "saturatedFatGrams", in: object, location: location) ?? 0,
            confidenceScore: try optionalDouble(field: "confidenceScore", in: object, location: location) ?? 0,
            detectionSource: try optionalString(field: "detectionSource", in: object, location: location),
            portionEstimationMethod: try optionalEnum(field: "portionEstimationMethod", in: object, location: location, as: PortionEstimationMethod.self) ?? .manualUserInput,
            wasUserEdited: try optionalBool(field: "wasUserEdited", in: object, location: location) ?? false,
            wasPortionAdjusted: try optionalBool(field: "wasPortionAdjusted", in: object, location: location),
            warning: try optionalString(field: "warning", in: object, location: location),
            createdAt: createdAt,
            updatedAt: try optionalDate(field: "updatedAt", in: object, location: location) ?? createdAt
        )
    }

    func parseMealScanNutritionSummaryRecord(_ object: JSONObject, location: String) throws -> MealScanNutritionSummaryRecord {
        let createdAt = try optionalDate(field: "createdAt", in: object, location: location) ?? Date()
        return MealScanNutritionSummaryRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            mealId: try requiredUUID(field: "mealId", in: object, location: location),
            caloriesKcal: try optionalDouble(field: "caloriesKcal", in: object, location: location) ?? 0,
            proteinGrams: try optionalDouble(field: "proteinGrams", in: object, location: location) ?? 0,
            carbsGrams: try optionalDouble(field: "carbsGrams", in: object, location: location) ?? 0,
            netCarbsGrams: try optionalDouble(field: "netCarbsGrams", in: object, location: location) ?? 0,
            fatGrams: try optionalDouble(field: "fatGrams", in: object, location: location) ?? 0,
            fiberGrams: try optionalDouble(field: "fiberGrams", in: object, location: location) ?? 0,
            sugarGrams: try optionalDouble(field: "sugarGrams", in: object, location: location) ?? 0,
            sodiumMg: try optionalDouble(field: "sodiumMg", in: object, location: location) ?? 0,
            saturatedFatGrams: try optionalDouble(field: "saturatedFatGrams", in: object, location: location) ?? 0,
            confidenceScore: try optionalDouble(field: "confidenceScore", in: object, location: location) ?? 0,
            estimatedGlycemicImpact: try optionalEnum(field: "estimatedGlycemicImpact", in: object, location: location, as: GlycemicImpactLevel.self) ?? .unknown,
            nutritionSourceSummary: try optionalString(field: "nutritionSourceSummary", in: object, location: location) ?? "local fixture",
            createdAt: createdAt,
            updatedAt: try optionalDate(field: "updatedAt", in: object, location: location) ?? createdAt
        )
    }

    func parseMealScanMetadataRecord(_ object: JSONObject, location: String) throws -> MealScanMetadataRecord {
        let createdAt = try optionalDate(field: "createdAt", in: object, location: location) ?? Date()
        return MealScanMetadataRecord(
            id: try optionalUUID(field: "id", in: object, location: location) ?? UUID(),
            mealId: try requiredUUID(field: "mealId", in: object, location: location),
            originalPredictionJSON: try optionalString(field: "originalPredictionJSON", in: object, location: location) ?? "{}",
            finalUserConfirmedJSON: try optionalString(field: "finalUserConfirmedJSON", in: object, location: location) ?? "{}",
            modelVersion: try optionalString(field: "modelVersion", in: object, location: location) ?? "unknown",
            pipelineVersion: try optionalString(field: "pipelineVersion", in: object, location: location) ?? "unknown",
            userConfirmed: try optionalBool(field: "userConfirmed", in: object, location: location) ?? false,
            hasUserEdits: try optionalBool(field: "hasUserEdits", in: object, location: location) ?? false,
            createdAt: createdAt,
            updatedAt: try optionalDate(field: "updatedAt", in: object, location: location) ?? createdAt
        )
    }

    func rawValue(for field: String, in object: JSONObject) -> Any? {
        guard let rawValue = object[field], !(rawValue is NSNull) else {
            return nil
        }

        return rawValue
    }

    func requiredString(field: String, in object: JSONObject, location: String) throws -> String {
        guard let value = try optionalString(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalString(field: String, in object: JSONObject, location: String) throws -> String? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let string = rawValue as? String else {
            throw RecordValidationError.invalid("Invalid \(field). Expected text.")
        }

        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requiredDate(field: String, in object: JSONObject, location: String) throws -> Date {
        guard let value = try optionalDate(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalDate(field: String, in object: JSONObject, location: String) throws -> Date? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let string = rawValue as? String else {
            throw RecordValidationError.invalid("Invalid \(field). Expected an ISO8601 timestamp.")
        }

        if let date = Self.fractionalISO8601Formatter.date(from: string)
            ?? Self.standardISO8601Formatter.date(from: string) {
            return date
        }

        throw RecordValidationError.invalid("Invalid \(field). Expected an ISO8601 timestamp.")
    }

    func requiredUUID(field: String, in object: JSONObject, location: String) throws -> UUID {
        guard let value = try optionalUUID(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalUUID(field: String, in object: JSONObject, location: String) throws -> UUID? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let string = rawValue as? String, let uuid = UUID(uuidString: string) else {
            throw RecordValidationError.invalid("Invalid \(field). Expected a UUID string.")
        }

        return uuid
    }

    func requiredInt(field: String, in object: JSONObject, location: String) throws -> Int {
        guard let value = try optionalInt(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalInt(field: String, in object: JSONObject, location: String) throws -> Int? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let number = nonBooleanNumber(from: rawValue) else {
            throw RecordValidationError.invalid("Invalid \(field). Expected an integer.")
        }

        let doubleValue = number.doubleValue
        guard doubleValue.rounded() == doubleValue else {
            throw RecordValidationError.invalid("Invalid \(field). Expected an integer.")
        }

        return number.intValue
    }

    func requiredDouble(field: String, in object: JSONObject, location: String) throws -> Double {
        guard let value = try optionalDouble(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalDouble(field: String, in object: JSONObject, location: String) throws -> Double? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let number = nonBooleanNumber(from: rawValue) else {
            throw RecordValidationError.invalid("Invalid \(field). Expected a number.")
        }

        return number.doubleValue
    }

    func optionalBool(field: String, in object: JSONObject, location: String) throws -> Bool? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let value = rawValue as? Bool else {
            throw RecordValidationError.invalid("Invalid \(field). Expected true or false.")
        }

        return value
    }

    func requiredData(field: String, in object: JSONObject, location: String) throws -> Data {
        guard let value = try optionalData(field: field, in: object, location: location) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalData(field: String, in object: JSONObject, location: String) throws -> Data? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let string = rawValue as? String, let data = Data(base64Encoded: string) else {
            throw RecordValidationError.invalid("Invalid \(field). Expected base64-encoded data.")
        }

        return data
    }

    func optionalStringArray(field: String, in object: JSONObject, location: String) throws -> [String]? {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let rawArray = rawValue as? [Any] else {
            throw RecordValidationError.invalid("Invalid \(field). Expected an array of strings.")
        }

        var values: [String] = []
        for rawItem in rawArray {
            guard let string = rawItem as? String else {
                throw RecordValidationError.invalid("Invalid \(field). Expected an array of strings.")
            }
            values.append(string)
        }

        return values
    }

    func requiredEnum<T: RawRepresentable>(
        field: String,
        in object: JSONObject,
        location: String,
        as type: T.Type
    ) throws -> T where T.RawValue == String {
        guard let value = try optionalEnum(field: field, in: object, location: location, as: type) else {
            throw RecordValidationError.invalid("Missing required \(field).")
        }
        return value
    }

    func optionalEnum<T: RawRepresentable>(
        field: String,
        in object: JSONObject,
        location: String,
        as type: T.Type
    ) throws -> T? where T.RawValue == String {
        guard let rawValue = rawValue(for: field, in: object) else {
            return nil
        }

        guard let string = rawValue as? String, let value = T(rawValue: string) else {
            throw RecordValidationError.invalid("Invalid \(field). Expected one of the app enum raw values.")
        }

        return value
    }

    func nonBooleanNumber(from rawValue: Any) -> NSNumber? {
        guard let number = rawValue as? NSNumber else {
            return nil
        }

        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }

        return number
    }

    static func malformedBackupReason(from error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .dataCorrupted(let context):
            return "\(codingPathDescription(context.codingPath)): \(normalizedDecodingDescription(context.debugDescription))"
        case .keyNotFound(let key, let context):
            return "\(codingPathDescription(context.codingPath + [key])): missing required field"
        case .typeMismatch(_, let context):
            return "\(codingPathDescription(context.codingPath)): \(normalizedDecodingDescription(context.debugDescription))"
        case .valueNotFound(_, let context):
            return "\(codingPathDescription(context.codingPath)): \(normalizedDecodingDescription(context.debugDescription))"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func codingPathDescription(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return "root"
        }

        return codingPath.reduce(into: "") { path, key in
            if let index = key.intValue ?? indexValue(from: key.stringValue) {
                path += "[\(index)]"
            } else if path.isEmpty {
                path = key.stringValue
            } else {
                path += ".\(key.stringValue)"
            }
        }
    }

    static func indexValue(from stringValue: String) -> Int? {
        guard stringValue.hasPrefix("Index ") else {
            return nil
        }

        return Int(stringValue.dropFirst("Index ".count))
    }

    static func normalizedDecodingDescription(_ description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)

        switch trimmed {
        case "Attempted to decode UUID from invalid UUID string.":
            return "invalid UUID string"
        default:
            return trimmed.isEmpty ? "invalid value" : trimmed
        }
    }

    static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standardISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func intValue(_ rawValue: Any?) -> Int? {
        guard let rawValue else {
            return nil
        }

        guard let number = nonBooleanNumber(from: rawValue) else {
            return nil
        }

        let doubleValue = number.doubleValue
        guard doubleValue.rounded() == doubleValue else {
            return nil
        }

        return number.intValue
    }

    func stringValue(_ rawValue: Any?) -> String? {
        guard let rawValue = rawValue, let string = rawValue as? String else {
            return nil
        }

        return string
    }

    func validateReferences(in records: SettingsDataBackupRecords) throws {
        let cycleIDs = Set(records.cycles.map(\.id))
        let cycleEntryIDs = Set(records.cycleEntries.map(\.id))

        for entry in records.cycleEntries {
            if let cycleID = entry.cycleID, !cycleIDs.contains(cycleID) {
                throw ImportError.danglingCycleReference(cycleID)
            }
        }

        for symptom in records.symptoms {
            if let cycleEntryID = symptom.cycleEntryID, !cycleEntryIDs.contains(cycleEntryID) {
                throw ImportError.danglingCycleEntryReference(cycleEntryID)
            }
        }
    }

    func clearAllTrackedModels() throws {
        try deleteAll(CycleEntry.self)
        try deleteAll(Cycle.self)
        try deleteAll(OvulationObservation.self)
        try deleteAll(SymptomEntry.self)
        try deleteAll(Insight.self)
        try deleteAll(BloodSugarReading.self)
        try deleteAll(SupplementLog.self)
        try deleteAll(MealScanRepeatCacheRecord.self)
        try deleteAll(MealEntry.self)
        try deleteAll(MealScanFoodItem.self)
        try deleteAll(MealScanNutritionSummary.self)
        try deleteAll(MealScanMetadata.self)
        try deleteAll(NutritionImportRecord.self)
        try deleteAll(HealthKitImportedSampleRecord.self)
        try deleteAll(HairPhotoEntry.self)
        try deleteAll(DailyLog.self)
        try deleteAll(PregnancyRecord.self)
    }

    func deleteAll<Model: PersistentModel>(_: Model.Type) throws {
        for model in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(model)
        }
    }

    func importRecords(from records: SettingsDataBackupRecords) throws -> SettingsDataRecordCounts {
        var cyclesByID: [UUID: Cycle] = [:]
        var cycleEntriesByID: [UUID: CycleEntry] = [:]

        for record in records.cycles {
            let cycle = Cycle(
                id: record.id,
                startDate: record.startDate,
                endDate: record.endDate,
                lengthDays: record.lengthDays,
                isPredicted: record.isPredicted,
                manualCycleLengthOverrideDays: record.manualCycleLengthOverrideDays,
                ovulationStatus: record.ovulationStatus ?? .unknown,
                endReason: record.endReason
            )
            modelContext.insert(cycle)
            cyclesByID[cycle.id] = cycle
        }

        for record in records.cycleEntries {
            let cycleEntry = CycleEntry(
                id: record.id,
                date: record.date,
                flowIntensity: record.flowIntensity,
                isPeriodDay: record.isPeriodDay,
                cyclePhase: record.cyclePhase,
                notes: record.notes,
                createdAt: record.createdAt
            )

            if let cycleID = record.cycleID {
                guard let cycle = cyclesByID[cycleID] else {
                    throw ImportError.danglingCycleReference(cycleID)
                }
                cycleEntry.cycle = cycle
            }

            modelContext.insert(cycleEntry)
            cycleEntriesByID[cycleEntry.id] = cycleEntry
        }

        for record in records.symptoms {
            let symptom = SymptomEntry(
                id: record.id,
                date: record.date,
                type: record.symptomType,
                severity: record.severity,
                notes: record.notes
            )
            symptom.category = record.category

            if let cycleEntryID = record.cycleEntryID {
                guard let cycleEntry = cycleEntriesByID[cycleEntryID] else {
                    throw ImportError.danglingCycleEntryReference(cycleEntryID)
                }
                symptom.cycleEntry = cycleEntry
            }

            modelContext.insert(symptom)
        }

        for record in records.bloodSugarReadings {
            modelContext.insert(
                BloodSugarReading(
                    id: record.id,
                    timestamp: record.timestamp,
                    glucoseValue: record.glucoseValue,
                    readingType: record.readingType,
                    mealContext: record.mealContext,
                    fromHealthKit: record.fromHealthKit,
                    notes: record.notes
                )
            )
        }

        for record in records.supplements {
            modelContext.insert(
                SupplementLog(
                    id: record.id,
                    date: record.date,
                    supplementName: record.supplementName,
                    dosageMg: record.dosageMg,
                    timeTaken: record.timeTaken,
                    taken: record.taken,
                    brand: record.brand
                )
            )
        }

        for record in records.meals {
            modelContext.insert(
                MealEntry(
                    id: record.id,
                    timestamp: record.timestamp,
                    mealType: record.mealType,
                    mealDescription: record.mealDescription,
                    glycemicImpact: record.glycemicImpact,
                    photoData: record.photoData,
                    carbsGrams: record.carbsGrams,
                    proteinGrams: record.proteinGrams,
                    fatGrams: record.fatGrams,
                    notes: record.notes,
                    selectedTemplateID: record.selectedTemplateID,
                    postMealSymptomSeverity: record.postMealSymptomSeverity,
                    postMealSymptomNote: record.postMealSymptomNote,
                    postMealFeedbackTimestamp: record.postMealFeedbackTimestamp,
                    nutritionImportID: record.nutritionImportID,
                    barcode: record.barcode,
                    sourceLabel: record.sourceLabel,
                    calories: record.calories,
                    fiberGrams: record.fiberGrams,
                    sugarGrams: record.sugarGrams,
                    servingText: record.servingText,
                    mealSource: record.mealSource,
                    photoLocalPath: record.photoLocalPath,
                    confidenceScore: record.confidenceScore,
                    userConfirmed: record.userConfirmed,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            )
        }

        for record in records.hairPhotos {
            modelContext.insert(
                HairPhotoEntry(
                    id: record.id,
                    date: record.date,
                    photoType: record.photoType,
                    photoData: record.photoData,
                    notes: record.notes,
                    analysisResult: record.analysisResult
                )
            )
        }

        for record in records.dailyLogs {
            modelContext.insert(
                DailyLog(
                    id: record.id,
                    date: record.date,
                    weight: record.weight,
                    sleepHours: record.sleepHours,
                    activeMinutes: record.activeMinutes,
                    restingHeartRateBPM: record.restingHeartRateBPM,
                    stressLevel: record.stressLevel,
                    energyLevel: record.energyLevel,
                    waterOz: record.waterOz
                )
            )
        }

        for record in records.insights {
            modelContext.insert(
                Insight(
                    id: record.id,
                    generatedDate: record.generatedDate,
                    insightType: record.insightType,
                    title: record.title,
                    content: record.content,
                    scientificContent: record.scientificContent,
                    confidence: record.confidence,
                    dataPointsUsed: record.dataPointsUsed,
                    actionable: record.actionable,
                    relatedSymptoms: record.relatedSymptoms,
                    phaseContext: record.phaseContext,
                    recommendedActions: record.recommendedActions,
                    learnMoreTopic: record.learnMoreTopic
                )
            )
        }

        for record in records.pregnancyRecords {
            modelContext.insert(
                PregnancyRecord(
                    id: record.id,
                    startDate: record.startDate,
                    estimatedDueDate: record.estimatedDueDate,
                    endDate: record.endDate,
                    endReason: record.endReason,
                    isActive: record.isActive,
                    notes: record.notes
                )
            )
        }

        for record in records.ovulationObservations {
            modelContext.insert(
                OvulationObservation(
                    id: record.id,
                    date: record.date,
                    basalBodyTemperatureCelsius: record.basalBodyTemperatureCelsius,
                    cervicalMucus: record.cervicalMucus,
                    lhTestResult: record.lhTestResult,
                    notes: record.notes,
                    createdAt: record.createdAt
                )
            )
        }

        for record in records.nutritionImports {
            modelContext.insert(
                NutritionImportRecord(
                    id: record.id,
                    sourceKind: record.sourceKind,
                    sourceName: record.sourceName,
                    externalIdentifier: record.externalIdentifier,
                    startDate: record.startDate,
                    endDate: record.endDate,
                    barcode: record.barcode,
                    productName: record.productName,
                    brandName: record.brandName,
                    servingText: record.servingText,
                    calories: record.calories,
                    carbsGrams: record.carbsGrams,
                    proteinGrams: record.proteinGrams,
                    fatGrams: record.fatGrams,
                    fiberGrams: record.fiberGrams,
                    sugarGrams: record.sugarGrams,
                    waterOz: record.waterOz,
                    sodiumMg: record.sodiumMg,
                    saturatedFatGrams: record.saturatedFatGrams,
                    cholesterolMg: record.cholesterolMg,
                    potassiumMg: record.potassiumMg,
                    calciumMg: record.calciumMg,
                    ironMg: record.ironMg,
                    confidence: record.confidence,
                    completeness: record.completeness,
                    importedAt: record.importedAt,
                    reviewStatus: record.reviewStatus,
                    userReviewed: record.userReviewed,
                    notes: record.notes
                )
            )
        }

        for record in records.mealScanFoodItems {
            modelContext.insert(
                MealScanFoodItem(
                    id: record.id,
                    mealId: record.mealId,
                    displayName: record.displayName,
                    canonicalFoodId: record.canonicalFoodId,
                    nutritionSource: record.nutritionSource,
                    estimatedGrams: record.estimatedGrams,
                    estimatedVolumeMl: record.estimatedVolumeMl,
                    servingDescription: record.servingDescription,
                    nutrition: NutritionSnapshot(
                        caloriesKcal: record.caloriesKcal,
                        proteinGrams: record.proteinGrams,
                        carbsGrams: record.carbsGrams,
                        netCarbsGrams: record.netCarbsGrams,
                        fatGrams: record.fatGrams,
                        fiberGrams: record.fiberGrams,
                        sugarGrams: record.sugarGrams,
                        sodiumMg: record.sodiumMg,
                        saturatedFatGrams: record.saturatedFatGrams
                    ),
                    confidenceScore: record.confidenceScore,
                    detectionSource: record.detectionSource,
                    portionEstimationMethod: record.portionEstimationMethod,
                    wasUserEdited: record.wasUserEdited,
                    wasPortionAdjusted: record.wasPortionAdjusted ?? false,
                    warning: record.warning,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            )
        }

        for record in records.mealScanNutritionSummaries {
            modelContext.insert(
                MealScanNutritionSummary(
                    id: record.id,
                    mealId: record.mealId,
                    nutrition: NutritionSnapshot(
                        caloriesKcal: record.caloriesKcal,
                        proteinGrams: record.proteinGrams,
                        carbsGrams: record.carbsGrams,
                        netCarbsGrams: record.netCarbsGrams,
                        fatGrams: record.fatGrams,
                        fiberGrams: record.fiberGrams,
                        sugarGrams: record.sugarGrams,
                        sodiumMg: record.sodiumMg,
                        saturatedFatGrams: record.saturatedFatGrams
                    ),
                    confidenceScore: record.confidenceScore,
                    estimatedGlycemicImpact: record.estimatedGlycemicImpact,
                    nutritionSourceSummary: record.nutritionSourceSummary,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            )
        }

        for record in records.mealScanMetadata {
            modelContext.insert(
                MealScanMetadata(
                    id: record.id,
                    mealId: record.mealId,
                    originalPredictionJSON: record.originalPredictionJSON,
                    finalUserConfirmedJSON: record.finalUserConfirmedJSON,
                    modelVersion: record.modelVersion,
                    pipelineVersion: record.pipelineVersion,
                    userConfirmed: record.userConfirmed,
                    hasUserEdits: record.hasUserEdits,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            )
        }

        for record in records.healthKitImportedSamples {
            modelContext.insert(
                HealthKitImportedSampleRecord(
                    id: record.id,
                    sampleUUID: record.sampleUUID,
                    healthKitIdentifier: record.healthKitIdentifier,
                    sourceName: record.sourceName,
                    sourceBundleIdentifier: record.sourceBundleIdentifier,
                    startDate: record.startDate,
                    endDate: record.endDate,
                    valueDouble: record.valueDouble,
                    valueUnit: record.valueUnit,
                    categoryValue: record.categoryValue,
                    derivedRecordKind: record.derivedRecordKind,
                    derivedRecordID: record.derivedRecordID,
                    importedAt: record.importedAt,
                    notes: record.notes
                )
            )
        }

        return records.counts
    }
}
