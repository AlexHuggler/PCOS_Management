import Foundation
import SwiftData

enum HealthKitDerivedRecordKind: String, Codable, CaseIterable, Sendable {
    case dailyLog = "daily_log"
    case bloodSugarReading = "blood_sugar_reading"
    case nutritionImport = "nutrition_import"
    case cycleEntry = "cycle_entry"
    case ovulationObservation = "ovulation_observation"
    case symptomEntry = "symptom_entry"
    case sensitiveContext = "sensitive_context"
    case sourceOnly = "source_only"
}

@Model
final class HealthKitImportedSampleRecord {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<HealthKitImportedSampleRecord>([\.sampleUUID], [\.healthKitIdentifier], [\.sourceName], [\.startDate])
    #endif

    var id: UUID = UUID()
    var sampleUUID: String = ""
    var healthKitIdentifier: String = ""
    var sourceName: String = "Apple Health"
    var sourceBundleIdentifier: String?
    var startDate: Date = Date()
    var endDate: Date?
    var valueDouble: Double?
    var valueUnit: String?
    var categoryValue: Int?
    var derivedRecordKind: HealthKitDerivedRecordKind = HealthKitDerivedRecordKind.sourceOnly
    var derivedRecordID: UUID?
    var importedAt: Date = Date()
    var notes: String?

    init(
        id: UUID = UUID(),
        sampleUUID: String,
        healthKitIdentifier: String,
        sourceName: String = "Apple Health",
        sourceBundleIdentifier: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        valueDouble: Double? = nil,
        valueUnit: String? = nil,
        categoryValue: Int? = nil,
        derivedRecordKind: HealthKitDerivedRecordKind = .sourceOnly,
        derivedRecordID: UUID? = nil,
        importedAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.sampleUUID = sampleUUID
        self.healthKitIdentifier = healthKitIdentifier
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.valueDouble = valueDouble
        self.valueUnit = valueUnit
        self.categoryValue = categoryValue
        self.derivedRecordKind = derivedRecordKind
        self.derivedRecordID = derivedRecordID
        self.importedAt = importedAt
        self.notes = notes
    }

    var sourceLabel: String {
        sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Apple Health"
            : sourceName
    }
}
