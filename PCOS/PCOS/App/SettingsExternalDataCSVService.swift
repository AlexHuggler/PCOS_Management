import Foundation
import SwiftData
import os

enum SettingsExternalCSVSchema {
    enum Column: String, CaseIterable, Hashable, Sendable {
        case recordType = "record_type"
        case date
        case timestamp
        case flowIntensity = "flow_intensity"
        case symptomType = "symptom_type"
        case severity
        case glucoseValue = "glucose_value"
        case readingType = "reading_type"
        case mealContext = "meal_context"
        case supplementName = "supplement_name"
        case dosageMg = "dosage_mg"
        case timeTaken = "time_taken"
        case taken
        case brand
        case mealType = "meal_type"
        case mealDescription = "meal_description"
        case glycemicImpact = "glycemic_impact"
        case carbsGrams = "carbs_grams"
        case proteinGrams = "protein_grams"
        case fatGrams = "fat_grams"
        case weight
        case sleepHours = "sleep_hours"
        case activeMinutes = "active_minutes"
        case stressLevel = "stress_level"
        case energyLevel = "energy_level"
        case waterOz = "water_oz"
        case basalBodyTemperatureCelsius = "basal_body_temperature_celsius"
        case cervicalMucus = "cervical_mucus"
        case lhTestResult = "lh_test_result"
        case notes
    }

    enum RecordType: String, CaseIterable, Hashable, Sendable {
        case period
        case symptom
        case bloodSugar = "blood_sugar"
        case supplement
        case meal
        case dailyLog = "daily_log"
        case ovulationObservation = "ovulation_observation"
    }

    struct FormatRule: Identifiable, Hashable, Sendable {
        let key: String
        let defaultValue: String

        var id: String { key }
    }

    struct RecordDefinition: Identifiable, Hashable, Sendable {
        let type: RecordType
        let requiredFields: [Column]
        let optionalFields: [Column]
        let noteKey: String?
        let noteDefaultValue: String?

        var id: RecordType { type }

        var acceptedValueColumns: [Column] {
            ([.recordType] + requiredFields + optionalFields).reduce(into: [Column]()) { result, column in
                guard SettingsExternalCSVSchema.acceptedValues(for: column) != nil else {
                    return
                }

                if !result.contains(column) {
                    result.append(column)
                }
            }
        }
    }

    static let headerColumns = Column.allCases

    static let header = headerColumns.map(\.rawValue)

    static let legacyHeaderColumns = Column.allCases.filter {
        ![Column.basalBodyTemperatureCelsius, .cervicalMucus, .lhTestResult].contains($0)
    }

    static let legacyHeader = legacyHeaderColumns.map(\.rawValue)

    static let formatRules = [
        FormatRule(
            key: "date uses YYYY-MM-DD",
            defaultValue: "date uses YYYY-MM-DD"
        ),
        FormatRule(
            key: "timestamp uses ISO8601",
            defaultValue: "timestamp uses ISO8601"
        ),
        FormatRule(
            key: "time_taken uses HH:mm",
            defaultValue: "time_taken uses HH:mm"
        ),
        FormatRule(
            key: "taken uses true or false",
            defaultValue: "taken uses true or false"
        ),
        FormatRule(
            key: "severity, stress_level, and energy_level use 1-5",
            defaultValue: "severity, stress_level, and energy_level use 1-5"
        ),
    ]

    static let recordDefinitions = [
        RecordDefinition(
            type: .period,
            requiredFields: [.recordType, .date, .flowIntensity],
            optionalFields: [.notes],
            noteKey: nil,
            noteDefaultValue: nil
        ),
        RecordDefinition(
            type: .symptom,
            requiredFields: [.recordType, .date, .symptomType, .severity],
            optionalFields: [.notes],
            noteKey: nil,
            noteDefaultValue: nil
        ),
        RecordDefinition(
            type: .bloodSugar,
            requiredFields: [.recordType, .timestamp, .glucoseValue, .readingType],
            optionalFields: [.mealContext, .notes],
            noteKey: nil,
            noteDefaultValue: nil
        ),
        RecordDefinition(
            type: .supplement,
            requiredFields: [.recordType, .date, .supplementName, .timeTaken],
            optionalFields: [.dosageMg, .taken, .brand],
            noteKey: nil,
            noteDefaultValue: nil
        ),
        RecordDefinition(
            type: .meal,
            requiredFields: [.recordType, .timestamp, .mealType, .mealDescription, .glycemicImpact],
            optionalFields: [.carbsGrams, .proteinGrams, .fatGrams, .notes],
            noteKey: nil,
            noteDefaultValue: nil
        ),
        RecordDefinition(
            type: .dailyLog,
            requiredFields: [.recordType, .date],
            optionalFields: [.weight, .sleepHours, .activeMinutes, .stressLevel, .energyLevel, .waterOz],
            noteKey: "daily_log requires at least one of weight, sleep_hours, active_minutes, stress_level, energy_level, or water_oz.",
            noteDefaultValue: "daily_log requires at least one of weight, sleep_hours, active_minutes, stress_level, energy_level, or water_oz."
        ),
        RecordDefinition(
            type: .ovulationObservation,
            requiredFields: [.recordType, .date],
            optionalFields: [.basalBodyTemperatureCelsius, .cervicalMucus, .lhTestResult, .notes],
            noteKey: nil,
            noteDefaultValue: nil
        ),
    ]

    static func acceptedValues(for column: Column) -> [String]? {
        switch column {
        case .recordType:
            RecordType.allCases.map(\.rawValue)
        case .flowIntensity:
            FlowIntensity.allCases.map(\.rawValue)
        case .symptomType:
            SymptomType.allCases.map(\.rawValue)
        case .readingType:
            GlucoseReadingType.allCases.map(\.rawValue)
        case .mealType:
            MealType.allCases.map(\.rawValue)
        case .glycemicImpact:
            GlycemicImpact.allCases.map(\.rawValue)
        case .cervicalMucus:
            CervicalMucusType.allCases.map(\.rawValue)
        case .lhTestResult:
            LHTestResult.allCases.map(\.rawValue)
        case .taken:
            ["true", "false"]
        default:
            nil
        }
    }
}

@MainActor
struct SettingsExternalDataCSVService {
    typealias Column = SettingsExternalCSVSchema.Column
    typealias RecordType = SettingsExternalCSVSchema.RecordType

    enum ImportError: LocalizedError, Equatable {
        case invalidEncoding
        case malformedCSV(String)
        case invalidHeader(expected: [String], actual: [String])
        case invalidColumnCount(row: Int, expected: Int, actual: Int)
        case unsupportedRecordType(row: Int, value: String)
        case missingRequiredValue(row: Int, column: String)
        case invalidValue(row: Int, column: String, value: String, reason: String)
        case emptyDailyLogRow(row: Int)

        var errorDescription: String? {
            switch self {
            case .invalidEncoding:
                String(
                    localized: "Could not read the CSV file as UTF-8 text.",
                    comment: "Error shown when an external CSV file uses an unsupported encoding."
                )
            case .malformedCSV(let reason):
                String(
                    localized: "The CSV file is malformed: \(reason)",
                    comment: "Error shown when the CSV parser cannot understand the file structure."
                )
            case .invalidHeader(let expected, let actual):
                String(
                    localized: "CSV header mismatch. Expected: \(expected.joined(separator: ", ")). Received: \(actual.joined(separator: ", ")).",
                    comment: "Error shown when an imported external CSV file uses the wrong columns."
                )
            case .invalidColumnCount(let row, let expected, let actual):
                String(
                    localized: "Row \(row) has \(actual) columns, but \(expected) were expected.",
                    comment: "Error shown when an imported CSV row has too many or too few columns."
                )
            case .unsupportedRecordType(let row, let value):
                String(
                    localized: "Row \(row) has an unsupported record_type value: \(value)",
                    comment: "Error shown when an imported CSV row uses an unsupported record type."
                )
            case .missingRequiredValue(let row, let column):
                String(
                    localized: "Row \(row) is missing a required value for \(column).",
                    comment: "Error shown when an imported CSV row omits a required field."
                )
            case .invalidValue(let row, let column, let value, let reason):
                String(
                    localized: "Row \(row) has an invalid \(column) value '\(value)': \(reason)",
                    comment: "Error shown when an imported CSV row contains an invalid value."
                )
            case .emptyDailyLogRow(let row):
                String(
                    localized: "Row \(row) is a daily_log entry, but no daily log fields were provided.",
                    comment: "Error shown when an imported daily log row is missing all trackable metrics."
                )
            }
        }

        var importIssue: SettingsDataImportService.ImportIssue {
            switch self {
            case .invalidEncoding:
                SettingsDataImportService.ImportIssue(
                    location: nil,
                    reason: String(
                        localized: "Could not read the CSV file as UTF-8 text.",
                        comment: "Error shown when an external CSV file uses an unsupported encoding."
                    )
                )
            case .malformedCSV(let reason):
                SettingsDataImportService.ImportIssue(
                    location: nil,
                    reason: String(
                        localized: "The CSV file is malformed: \(reason)",
                        comment: "Error shown when the CSV parser cannot understand the file structure."
                    )
                )
            case .invalidHeader(let expected, let actual):
                SettingsDataImportService.ImportIssue(
                    location: nil,
                    reason: String(
                        localized: "CSV header mismatch. Expected: \(expected.joined(separator: ", ")). Received: \(actual.joined(separator: ", ")).",
                        comment: "Error shown when an imported external CSV file uses the wrong columns."
                    )
                )
            case .invalidColumnCount(let row, let expected, let actual):
                SettingsDataImportService.ImportIssue(
                    location: "row \(row)",
                    reason: "Expected \(expected) columns, found \(actual)."
                )
            case .unsupportedRecordType(let row, let value):
                SettingsDataImportService.ImportIssue(
                    location: "row \(row)",
                    reason: "Unsupported record_type '\(value)'."
                )
            case .missingRequiredValue(let row, let column):
                SettingsDataImportService.ImportIssue(
                    location: "row \(row)",
                    reason: "Missing required value for \(column)."
                )
            case .invalidValue(let row, let column, let value, let reason):
                SettingsDataImportService.ImportIssue(
                    location: "row \(row)",
                    reason: "Invalid \(column) value '\(value)'. \(reason)"
                )
            case .emptyDailyLogRow(let row):
                SettingsDataImportService.ImportIssue(
                    location: "row \(row)",
                    reason: "daily_log requires at least one metric value."
                )
            }
        }
    }

    typealias FileWriter = (_ contents: String, _ url: URL) throws -> Void

    private struct CSVRow {
        let rowNumber: Int
        let values: [Column: String]

        func value(_ column: Column) -> String? {
            guard let rawValue = values[column] else {
                return nil
            }

            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private struct DayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    private struct PeriodRow {
        let date: Date
        let flowIntensity: FlowIntensity
        let notes: String?
    }

    private struct SymptomRow {
        let date: Date
        let symptomType: SymptomType
        let severity: Int
        let notes: String?
    }

    private struct BloodSugarRow {
        let timestamp: Date
        let glucoseValue: Double
        let readingType: GlucoseReadingType
        let mealContext: String?
        let notes: String?
    }

    private struct SupplementRow {
        let date: Date
        let supplementName: String
        let dosageMg: Double?
        let timeTaken: Date
        let taken: Bool
        let brand: String?
    }

    private struct MealRow {
        let timestamp: Date
        let mealType: MealType
        let mealDescription: String
        let glycemicImpact: GlycemicImpact
        let carbsGrams: Double?
        let proteinGrams: Double?
        let fatGrams: Double?
        let notes: String?
    }

    private struct DailyLogRow {
        let date: Date
        let weight: Double?
        let sleepHours: Double?
        let activeMinutes: Int?
        let stressLevel: Int?
        let energyLevel: Int?
        let waterOz: Int?
    }

    private struct OvulationObservationRow {
        let date: Date
        let basalBodyTemperatureCelsius: Double?
        let cervicalMucus: CervicalMucusType?
        let lhTestResult: LHTestResult?
        let notes: String?
    }

    private enum ParsedRecord {
        case period(PeriodRow)
        case symptom(SymptomRow)
        case bloodSugar(BloodSugarRow)
        case supplement(SupplementRow)
        case meal(MealRow)
        case dailyLog(DailyLogRow)
        case ovulationObservation(OvulationObservationRow)
    }

    private struct ParsedRows {
        let records: [ParsedRecord]
        let issues: [SettingsDataImportService.ImportIssue]
    }

    private struct SymptomKey: Hashable {
        let day: DayKey
        let symptomType: String
        let severity: Int
        let notes: String?
    }

    private struct BloodSugarKey: Hashable {
        let timestamp: Date
        let glucoseValue: Int64
        let readingType: String
        let mealContext: String?
        let notes: String?
    }

    private struct SupplementKey: Hashable {
        let day: DayKey
        let supplementName: String
        let dosageMg: Int64?
        let timeTaken: Date
        let taken: Bool
        let brand: String?
    }

    private struct MealKey: Hashable {
        let timestamp: Date
        let mealType: String
        let mealDescription: String
        let glycemicImpact: String
        let carbsGrams: Int64?
        let proteinGrams: Int64?
        let fatGrams: Int64?
        let notes: String?
    }

    private struct OvulationObservationKey: Hashable {
        let day: DayKey
        let basalBodyTemperatureCelsius: Int64?
        let cervicalMucus: String?
        let lhTestResult: String?
        let notes: String?
    }

    private let modelContext: ModelContext
    private let fileWriter: FileWriter

    init(
        modelContext: ModelContext,
        fileWriter: @escaping FileWriter = { contents, url in
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    ) {
        self.modelContext = modelContext
        self.fileWriter = fileWriter
    }

    func generateTemplate() throws -> URL {
        let templateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CycleBalance_ExternalImport_Template.csv")
        try fileWriter(generateTemplateContents(), templateURL)
        return templateURL
    }

    func generateTemplateContents() -> String {
        SettingsExternalCSVSchema.header.joined(separator: ",") + "\n"
    }

    func importCSV(from url: URL) throws -> SettingsDataImportService.ImportSummary {
        try importCSV(data: Data(contentsOf: url))
    }

    func importCSV(data: Data) throws -> SettingsDataImportService.ImportSummary {
        guard var contents = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidEncoding
        }

        if contents.hasPrefix("\u{FEFF}") {
            contents.removeFirst()
        }

        let rows = try CSVParser.parse(contents)
        let parsedRows = try parseRows(rows)
        return try apply(records: parsedRows.records, issues: parsedRows.issues)
    }

#if DEBUG
    static func uiTestFixture(named rawValue: String) -> Data? {
        switch rawValue {
        case "valid":
            let row = fixtureRow([
                .recordType: RecordType.symptom.rawValue,
                .date: "2026-03-10",
                .symptomType: SymptomType.cramps.rawValue,
                .severity: "4",
                .notes: "UI test fixture",
            ])
            return Data((SettingsExternalCSVSchema.header.joined(separator: ",") + "\n" + row + "\n").utf8)
        case "invalid":
            let row = fixtureRow([
                .recordType: RecordType.symptom.rawValue,
                .date: "2026-03-10",
                .symptomType: "unknown_symptom",
                .severity: "4",
            ])
            return Data((SettingsExternalCSVSchema.header.joined(separator: ",") + "\n" + row + "\n").utf8)
        default:
            return nil
        }
    }

    private static func fixtureRow(_ values: [Column: String]) -> String {
        SettingsExternalCSVSchema.headerColumns.map { values[$0] ?? "" }.joined(separator: ",")
    }
#endif
}

private extension SettingsExternalDataCSVService {
    private enum CSVParser {
        static func parse(_ contents: String) throws -> [[String]] {
            var rows: [[String]] = []
            var currentRow: [String] = []
            var currentField = ""
            var isInsideQuotes = false
            let characters = Array(contents)
            var index = 0

            while index < characters.count {
                let character = characters[index]

                if isInsideQuotes {
                    if character == "\"" {
                        if index + 1 < characters.count, characters[index + 1] == "\"" {
                            currentField.append("\"")
                            index += 1
                        } else {
                            isInsideQuotes = false
                        }
                    } else {
                        currentField.append(character)
                    }
                } else {
                    switch character {
                    case "\"":
                        isInsideQuotes = true
                    case ",":
                        currentRow.append(currentField)
                        currentField = ""
                    case "\n":
                        currentRow.append(currentField)
                        append(row: currentRow, to: &rows)
                        currentRow = []
                        currentField = ""
                    case "\r":
                        currentRow.append(currentField)
                        append(row: currentRow, to: &rows)
                        currentRow = []
                        currentField = ""

                        if index + 1 < characters.count, characters[index + 1] == "\n" {
                            index += 1
                        }
                    default:
                        currentField.append(character)
                    }
                }

                index += 1
            }

            if isInsideQuotes {
                throw ImportError.malformedCSV("A quoted field was not closed before the end of the file.")
            }

            if !currentRow.isEmpty || !currentField.isEmpty {
                currentRow.append(currentField)
                append(row: currentRow, to: &rows)
            }

            return rows
        }

        private static func append(row: [String], to rows: inout [[String]]) {
            let isBlankRow = row.allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            if !isBlankRow {
                rows.append(row)
            }
        }
    }

    private func parseRows(_ rows: [[String]]) throws -> ParsedRows {
        let expectedHeader = SettingsExternalCSVSchema.header
        guard let header = rows.first else {
            throw ImportError.invalidHeader(expected: expectedHeader, actual: [])
        }

        let activeColumns: [Column]
        if header == expectedHeader {
            activeColumns = SettingsExternalCSVSchema.headerColumns
        } else if header == SettingsExternalCSVSchema.legacyHeader {
            activeColumns = SettingsExternalCSVSchema.legacyHeaderColumns
        } else {
            throw ImportError.invalidHeader(expected: expectedHeader, actual: header)
        }

        var records: [ParsedRecord] = []
        var issues: [SettingsDataImportService.ImportIssue] = []

        for (index, rowValues) in rows.enumerated().dropFirst() {
            let rowNumber = index + 1

            guard rowValues.count == activeColumns.count else {
                issues.append(
                    ImportError.invalidColumnCount(
                        row: rowNumber,
                        expected: activeColumns.count,
                        actual: rowValues.count
                    ).importIssue
                )
                continue
            }

            let row = CSVRow(
                rowNumber: rowNumber,
                values: Dictionary(uniqueKeysWithValues: zip(activeColumns, rowValues))
            )

            do {
                let recordTypeRawValue = try requiredValue(.recordType, in: row)
                guard let recordType = RecordType(rawValue: recordTypeRawValue) else {
                    throw ImportError.unsupportedRecordType(row: row.rowNumber, value: recordTypeRawValue)
                }

                let record: ParsedRecord
                switch recordType {
                case .period:
                    record = .period(try parsePeriodRow(row))
                case .symptom:
                    record = .symptom(try parseSymptomRow(row))
                case .bloodSugar:
                    record = .bloodSugar(try parseBloodSugarRow(row))
                case .supplement:
                    record = .supplement(try parseSupplementRow(row))
                case .meal:
                    record = .meal(try parseMealRow(row))
                case .dailyLog:
                    record = .dailyLog(try parseDailyLogRow(row))
                case .ovulationObservation:
                    record = .ovulationObservation(try parseOvulationObservationRow(row))
                }

                records.append(record)
            } catch let error as ImportError {
                issues.append(error.importIssue)
            }
        }

        return ParsedRows(records: records, issues: issues)
    }

    private func parsePeriodRow(_ row: CSVRow) throws -> PeriodRow {
        PeriodRow(
            date: try parseDate(column: .date, in: row),
            flowIntensity: try parseEnum(column: .flowIntensity, in: row, as: FlowIntensity.self),
            notes: cleanedText(row.value(.notes))
        )
    }

    private func parseSymptomRow(_ row: CSVRow) throws -> SymptomRow {
        let severity = try parseInt(column: .severity, in: row)
        guard (1...5).contains(severity) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: Column.severity.rawValue,
                value: String(severity),
                reason: "Expected a value between 1 and 5."
            )
        }

        return SymptomRow(
            date: try parseDate(column: .date, in: row),
            symptomType: try parseEnum(column: .symptomType, in: row, as: SymptomType.self),
            severity: severity,
            notes: cleanedText(row.value(.notes))
        )
    }

    private func parseBloodSugarRow(_ row: CSVRow) throws -> BloodSugarRow {
        BloodSugarRow(
            timestamp: try parseTimestamp(column: .timestamp, in: row),
            glucoseValue: try parseDouble(column: .glucoseValue, in: row),
            readingType: try parseEnum(column: .readingType, in: row, as: GlucoseReadingType.self),
            mealContext: cleanedText(row.value(.mealContext)),
            notes: cleanedText(row.value(.notes))
        )
    }

    private func parseSupplementRow(_ row: CSVRow) throws -> SupplementRow {
        let date = try parseDate(column: .date, in: row)

        return SupplementRow(
            date: date,
            supplementName: try requiredValue(.supplementName, in: row),
            dosageMg: try optionalDouble(column: .dosageMg, in: row),
            timeTaken: try parseTimeTaken(for: date, in: row),
            taken: try parseBool(column: .taken, in: row, defaultValue: true),
            brand: cleanedText(row.value(.brand))
        )
    }

    private func parseMealRow(_ row: CSVRow) throws -> MealRow {
        MealRow(
            timestamp: try parseTimestamp(column: .timestamp, in: row),
            mealType: try parseEnum(column: .mealType, in: row, as: MealType.self),
            mealDescription: try requiredValue(.mealDescription, in: row),
            glycemicImpact: try parseEnum(column: .glycemicImpact, in: row, as: GlycemicImpact.self),
            carbsGrams: try optionalDouble(column: .carbsGrams, in: row),
            proteinGrams: try optionalDouble(column: .proteinGrams, in: row),
            fatGrams: try optionalDouble(column: .fatGrams, in: row),
            notes: cleanedText(row.value(.notes))
        )
    }

    private func parseDailyLogRow(_ row: CSVRow) throws -> DailyLogRow {
        let dailyLog = DailyLogRow(
            date: try parseDate(column: .date, in: row),
            weight: try optionalDouble(column: .weight, in: row),
            sleepHours: try optionalDouble(column: .sleepHours, in: row),
            activeMinutes: try optionalInt(column: .activeMinutes, in: row),
            stressLevel: try optionalInt(column: .stressLevel, in: row),
            energyLevel: try optionalInt(column: .energyLevel, in: row),
            waterOz: try optionalInt(column: .waterOz, in: row)
        )

        guard
            dailyLog.weight != nil
                || dailyLog.sleepHours != nil
                || dailyLog.activeMinutes != nil
                || dailyLog.stressLevel != nil
                || dailyLog.energyLevel != nil
                || dailyLog.waterOz != nil
        else {
            throw ImportError.emptyDailyLogRow(row: row.rowNumber)
        }

        if let stressLevel = dailyLog.stressLevel, !(1...5).contains(stressLevel) {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: Column.stressLevel.rawValue,
                value: String(stressLevel),
                reason: "Expected a value between 1 and 5."
            )
        }

        if let energyLevel = dailyLog.energyLevel, !(1...5).contains(energyLevel) {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: Column.energyLevel.rawValue,
                value: String(energyLevel),
                reason: "Expected a value between 1 and 5."
            )
        }

        return dailyLog
    }

    private func parseOvulationObservationRow(_ row: CSVRow) throws -> OvulationObservationRow {
        OvulationObservationRow(
            date: try parseDate(column: .date, in: row),
            basalBodyTemperatureCelsius: try optionalDouble(column: .basalBodyTemperatureCelsius, in: row),
            cervicalMucus: try optionalEnum(column: .cervicalMucus, in: row, as: CervicalMucusType.self),
            lhTestResult: try optionalEnum(column: .lhTestResult, in: row, as: LHTestResult.self),
            notes: cleanedText(row.value(.notes))
        )
    }

    private func requiredValue(_ column: Column, in row: CSVRow) throws -> String {
        guard let value = row.value(column) else {
            throw ImportError.missingRequiredValue(row: row.rowNumber, column: column.rawValue)
        }

        return value
    }

    private func parseDate(column: Column, in row: CSVRow) throws -> Date {
        let rawValue = try requiredValue(column, in: row)
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)

        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected YYYY-MM-DD."
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let date = calendar.date(from: components) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected a valid calendar date."
            )
        }

        return date
    }

    private func parseTimestamp(column: Column, in row: CSVRow) throws -> Date {
        let rawValue = try requiredValue(column, in: row)
        if let date = Self.fractionalISO8601Formatter.date(from: rawValue)
            ?? Self.standardISO8601Formatter.date(from: rawValue) {
            return date
        }

        throw ImportError.invalidValue(
            row: row.rowNumber,
            column: column.rawValue,
            value: rawValue,
            reason: "Expected an ISO8601 timestamp."
        )
    }

    private func parseTimeTaken(for date: Date, in row: CSVRow) throws -> Date {
        let rawValue = try requiredValue(.timeTaken, in: row)
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)

        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: Column.timeTaken.rawValue,
                value: rawValue,
                reason: "Expected HH:mm."
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute

        guard let combinedDate = calendar.date(from: components) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: Column.timeTaken.rawValue,
                value: rawValue,
                reason: "Expected a valid time."
            )
        }

        return combinedDate
    }

    private func parseBool(column: Column, in row: CSVRow, defaultValue: Bool? = nil) throws -> Bool {
        guard let rawValue = row.value(column) else {
            if let defaultValue {
                return defaultValue
            }

            throw ImportError.missingRequiredValue(row: row.rowNumber, column: column.rawValue)
        }

        switch rawValue.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected true or false."
            )
        }
    }

    private func parseInt(column: Column, in row: CSVRow) throws -> Int {
        let rawValue = try requiredValue(column, in: row)
        guard let value = Int(rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected an integer."
            )
        }

        return value
    }

    private func optionalInt(column: Column, in row: CSVRow) throws -> Int? {
        guard let rawValue = row.value(column) else {
            return nil
        }

        guard let value = Int(rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected an integer."
            )
        }

        return value
    }

    private func parseDouble(column: Column, in row: CSVRow) throws -> Double {
        let rawValue = try requiredValue(column, in: row)
        guard let value = Double(rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected a number."
            )
        }

        return value
    }

    private func optionalDouble(column: Column, in row: CSVRow) throws -> Double? {
        guard let rawValue = row.value(column) else {
            return nil
        }

        guard let value = Double(rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected a number."
            )
        }

        return value
    }

    private func parseEnum<T: RawRepresentable>(column: Column, in row: CSVRow, as type: T.Type) throws -> T where T.RawValue == String {
        let rawValue = try requiredValue(column, in: row)
        guard let value = T(rawValue: rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected one of the app enum raw values."
            )
        }

        return value
    }

    private func optionalEnum<T: RawRepresentable>(column: Column, in row: CSVRow, as type: T.Type) throws -> T? where T.RawValue == String {
        guard let rawValue = row.value(column) else {
            return nil
        }

        guard let value = T(rawValue: rawValue) else {
            throw ImportError.invalidValue(
                row: row.rowNumber,
                column: column.rawValue,
                value: rawValue,
                reason: "Expected one of the app enum raw values."
            )
        }

        return value
    }

    private func apply(
        records: [ParsedRecord],
        issues: [SettingsDataImportService.ImportIssue]
    ) throws -> SettingsDataImportService.ImportSummary {
        var counts = SettingsDataRecordCounts()
        var changeCounts = SettingsDataImportService.ImportChangeCounts()

        do {
            try applyPeriods(
                records.compactMap {
                    guard case let .period(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applySymptoms(
                records.compactMap {
                    guard case let .symptom(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applyBloodSugar(
                records.compactMap {
                    guard case let .bloodSugar(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applySupplements(
                records.compactMap {
                    guard case let .supplement(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applyMeals(
                records.compactMap {
                    guard case let .meal(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applyDailyLogs(
                records.compactMap {
                    guard case let .dailyLog(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try applyOvulationObservations(
                records.compactMap {
                    guard case let .ovulationObservation(row) = $0 else { return nil }
                    return row
                },
                counts: &counts,
                changeCounts: &changeCounts
            )

            try modelContext.save()
            Logger.database.info(
                "Imported external CSV with inserted=\(changeCounts.inserted), updated=\(changeCounts.updated), skipped=\(changeCounts.skipped), rejected=\(issues.count)"
            )

            changeCounts.rejected = issues.count

            return SettingsDataImportService.ImportSummary(
                importedAt: Date(),
                channel: .externalCSV,
                counts: counts,
                changeCounts: changeCounts,
                issues: issues
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func applyPeriods(
        _ rows: [PeriodRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let entryDescriptor = FetchDescriptor<CycleEntry>(sortBy: [SortDescriptor(\.date)])
        var recentEntries = try modelContext.fetch(entryDescriptor)
        var existingPeriodDays = Set(recentEntries.filter(\.isPeriodDay).map { dayKey(for: $0.date) })

        let cycleDescriptor = FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.startDate)])
        var existingCycles = try modelContext.fetch(cycleDescriptor)

        let cycleLogService = CycleLogService(modelContext: modelContext)
        for row in rows.sorted(by: { lhs, rhs in
            if lhs.date == rhs.date {
                return (lhs.notes ?? "") < (rhs.notes ?? "")
            }
            return lhs.date < rhs.date
        }) {
            let key = dayKey(for: row.date)
            guard !existingPeriodDays.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            let entry = try cycleLogService.stagePeriodDay(
                date: row.date,
                flowIntensity: row.flowIntensity,
                notes: row.notes,
                existingCycles: existingCycles,
                recentEntries: recentEntries
            )

            recentEntries.append(entry)
            recentEntries.sort { $0.date < $1.date }
            existingPeriodDays.insert(key)

            if let cycle = entry.cycle, !existingCycles.contains(where: { $0 === cycle }) {
                existingCycles.append(cycle)
                existingCycles.sort { $0.startDate < $1.startDate }
            }

            counts.cycleEntries += 1
            changeCounts.inserted += 1
        }
    }

    private func applySymptoms(
        _ rows: [SymptomRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<SymptomEntry>(sortBy: [SortDescriptor(\.date)])
        let existingSymptoms = try modelContext.fetch(descriptor)
        var existingKeys = Set(existingSymptoms.map(symptomKey(for:)))

        for row in rows {
            let key = symptomKey(for: row)
            guard !existingKeys.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            let symptom = SymptomEntry(
                date: row.date,
                type: row.symptomType,
                severity: row.severity,
                notes: row.notes
            )
            modelContext.insert(symptom)
            existingKeys.insert(key)
            counts.symptoms += 1
            changeCounts.inserted += 1
        }
    }

    private func applyBloodSugar(
        _ rows: [BloodSugarRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<BloodSugarReading>(sortBy: [SortDescriptor(\.timestamp)])
        let existingReadings = try modelContext.fetch(descriptor)
        var existingKeys = Set(existingReadings.map(bloodSugarKey(for:)))

        for row in rows {
            let key = bloodSugarKey(for: row)
            guard !existingKeys.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            modelContext.insert(
                BloodSugarReading(
                    timestamp: row.timestamp,
                    glucoseValue: row.glucoseValue,
                    readingType: row.readingType,
                    mealContext: row.mealContext,
                    fromHealthKit: false,
                    notes: row.notes
                )
            )
            existingKeys.insert(key)
            counts.bloodSugarReadings += 1
            changeCounts.inserted += 1
        }
    }

    private func applySupplements(
        _ rows: [SupplementRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<SupplementLog>(sortBy: [SortDescriptor(\.date)])
        let existingLogs = try modelContext.fetch(descriptor)
        var existingKeys = Set(existingLogs.map(supplementKey(for:)))

        for row in rows {
            let key = supplementKey(for: row)
            guard !existingKeys.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            modelContext.insert(
                SupplementLog(
                    date: row.date,
                    supplementName: row.supplementName,
                    dosageMg: row.dosageMg,
                    timeTaken: row.timeTaken,
                    taken: row.taken,
                    brand: row.brand
                )
            )
            existingKeys.insert(key)
            counts.supplements += 1
            changeCounts.inserted += 1
        }
    }

    private func applyMeals(
        _ rows: [MealRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp)])
        let existingMeals = try modelContext.fetch(descriptor)
        var existingKeys = Set(existingMeals.map(mealKey(for:)))

        for row in rows {
            let key = mealKey(for: row)
            guard !existingKeys.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            modelContext.insert(
                MealEntry(
                    timestamp: row.timestamp,
                    mealType: row.mealType,
                    mealDescription: row.mealDescription,
                    glycemicImpact: row.glycemicImpact,
                    carbsGrams: row.carbsGrams,
                    proteinGrams: row.proteinGrams,
                    fatGrams: row.fatGrams,
                    notes: row.notes
                )
            )
            existingKeys.insert(key)
            counts.meals += 1
            changeCounts.inserted += 1
        }
    }

    private func applyDailyLogs(
        _ rows: [DailyLogRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<DailyLog>(sortBy: [SortDescriptor(\.date)])
        let existingLogs = try modelContext.fetch(descriptor)
        var logsByDay: [DayKey: DailyLog] = [:]
        for log in existingLogs {
            logsByDay[dayKey(for: log.date)] = log
        }

        for row in rows {
            let key = dayKey(for: row.date)
            if let existingLog = logsByDay[key] {
                let didChange = update(existingLog, with: row)
                if didChange {
                    counts.dailyLogs += 1
                    changeCounts.updated += 1
                } else {
                    changeCounts.skipped += 1
                }
            } else {
                let log = DailyLog(
                    date: row.date,
                    weight: row.weight,
                    sleepHours: row.sleepHours,
                    activeMinutes: row.activeMinutes,
                    stressLevel: row.stressLevel,
                    energyLevel: row.energyLevel,
                    waterOz: row.waterOz
                )
                modelContext.insert(log)
                logsByDay[key] = log
                counts.dailyLogs += 1
                changeCounts.inserted += 1
            }
        }
    }

    private func applyOvulationObservations(
        _ rows: [OvulationObservationRow],
        counts: inout SettingsDataRecordCounts,
        changeCounts: inout SettingsDataImportService.ImportChangeCounts
    ) throws {
        guard !rows.isEmpty else { return }

        let descriptor = FetchDescriptor<OvulationObservation>(sortBy: [SortDescriptor(\.date)])
        let existingObservations = try modelContext.fetch(descriptor)
        var existingKeys = Set(existingObservations.map(ovulationObservationKey(for:)))

        for row in rows {
            let key = ovulationObservationKey(for: row)
            guard !existingKeys.contains(key) else {
                changeCounts.skipped += 1
                continue
            }

            modelContext.insert(
                OvulationObservation(
                    date: row.date,
                    basalBodyTemperatureCelsius: row.basalBodyTemperatureCelsius,
                    cervicalMucus: row.cervicalMucus,
                    lhTestResult: row.lhTestResult,
                    notes: row.notes
                )
            )
            existingKeys.insert(key)
            counts.ovulationObservations += 1
            changeCounts.inserted += 1
        }
    }

    private func update(_ existingLog: DailyLog, with row: DailyLogRow) -> Bool {
        var didChange = false

        if let weight = row.weight, existingLog.weight != weight {
            existingLog.weight = weight
            didChange = true
        }

        if let sleepHours = row.sleepHours, existingLog.sleepHours != sleepHours {
            existingLog.sleepHours = sleepHours
            didChange = true
        }

        if let activeMinutes = row.activeMinutes, existingLog.activeMinutes != activeMinutes {
            existingLog.activeMinutes = activeMinutes
            didChange = true
        }

        if let stressLevel = row.stressLevel, existingLog.stressLevel != stressLevel {
            existingLog.stressLevel = stressLevel
            didChange = true
        }

        if let energyLevel = row.energyLevel, existingLog.energyLevel != energyLevel {
            existingLog.energyLevel = energyLevel
            didChange = true
        }

        if let waterOz = row.waterOz, existingLog.waterOz != waterOz {
            existingLog.waterOz = waterOz
            didChange = true
        }

        return didChange
    }

    private func dayKey(for date: Date) -> DayKey {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    private func symptomKey(for symptom: SymptomEntry) -> SymptomKey {
        SymptomKey(
            day: dayKey(for: symptom.date),
            symptomType: symptom.symptomType.rawValue,
            severity: symptom.severity,
            notes: dedupeText(symptom.notes)
        )
    }

    private func symptomKey(for row: SymptomRow) -> SymptomKey {
        SymptomKey(
            day: dayKey(for: row.date),
            symptomType: row.symptomType.rawValue,
            severity: row.severity,
            notes: dedupeText(row.notes)
        )
    }

    private func bloodSugarKey(for reading: BloodSugarReading) -> BloodSugarKey {
        BloodSugarKey(
            timestamp: reading.timestamp,
            glucoseValue: scaledNumberKey(reading.glucoseValue),
            readingType: reading.readingType.rawValue,
            mealContext: dedupeText(reading.mealContext),
            notes: dedupeText(reading.notes)
        )
    }

    private func bloodSugarKey(for row: BloodSugarRow) -> BloodSugarKey {
        BloodSugarKey(
            timestamp: row.timestamp,
            glucoseValue: scaledNumberKey(row.glucoseValue),
            readingType: row.readingType.rawValue,
            mealContext: dedupeText(row.mealContext),
            notes: dedupeText(row.notes)
        )
    }

    private func supplementKey(for log: SupplementLog) -> SupplementKey {
        SupplementKey(
            day: dayKey(for: log.date),
            supplementName: dedupeText(log.supplementName) ?? "",
            dosageMg: log.dosageMg.map(scaledNumberKey),
            timeTaken: log.timeTaken,
            taken: log.taken,
            brand: dedupeText(log.brand)
        )
    }

    private func supplementKey(for row: SupplementRow) -> SupplementKey {
        SupplementKey(
            day: dayKey(for: row.date),
            supplementName: dedupeText(row.supplementName) ?? "",
            dosageMg: row.dosageMg.map(scaledNumberKey),
            timeTaken: row.timeTaken,
            taken: row.taken,
            brand: dedupeText(row.brand)
        )
    }

    private func mealKey(for meal: MealEntry) -> MealKey {
        MealKey(
            timestamp: meal.timestamp,
            mealType: meal.mealType.rawValue,
            mealDescription: dedupeText(meal.mealDescription) ?? "",
            glycemicImpact: meal.glycemicImpact.rawValue,
            carbsGrams: meal.carbsGrams.map(scaledNumberKey),
            proteinGrams: meal.proteinGrams.map(scaledNumberKey),
            fatGrams: meal.fatGrams.map(scaledNumberKey),
            notes: dedupeText(meal.notes)
        )
    }

    private func mealKey(for row: MealRow) -> MealKey {
        MealKey(
            timestamp: row.timestamp,
            mealType: row.mealType.rawValue,
            mealDescription: dedupeText(row.mealDescription) ?? "",
            glycemicImpact: row.glycemicImpact.rawValue,
            carbsGrams: row.carbsGrams.map(scaledNumberKey),
            proteinGrams: row.proteinGrams.map(scaledNumberKey),
            fatGrams: row.fatGrams.map(scaledNumberKey),
            notes: dedupeText(row.notes)
        )
    }

    private func ovulationObservationKey(for observation: OvulationObservation) -> OvulationObservationKey {
        OvulationObservationKey(
            day: dayKey(for: observation.date),
            basalBodyTemperatureCelsius: observation.basalBodyTemperatureCelsius.map(scaledNumberKey),
            cervicalMucus: observation.cervicalMucus?.rawValue,
            lhTestResult: observation.lhTestResult?.rawValue,
            notes: dedupeText(observation.notes)
        )
    }

    private func ovulationObservationKey(for row: OvulationObservationRow) -> OvulationObservationKey {
        OvulationObservationKey(
            day: dayKey(for: row.date),
            basalBodyTemperatureCelsius: row.basalBodyTemperatureCelsius.map(scaledNumberKey),
            cervicalMucus: row.cervicalMucus?.rawValue,
            lhTestResult: row.lhTestResult?.rawValue,
            notes: dedupeText(row.notes)
        )
    }

    private func cleanedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dedupeText(_ value: String?) -> String? {
        guard let cleaned = cleanedText(value) else {
            return nil
        }

        let collapsed = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsed.lowercased()
    }

    private func scaledNumberKey(_ value: Double) -> Int64 {
        Int64((value * 1_000).rounded())
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
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
}
