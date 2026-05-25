import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Settings External Data CSV Service", .serialized)
@MainActor
struct SettingsExternalDataCSVServiceTests {
    private let columns = SettingsExternalCSVSchema.header

    @Test("generateTemplateContents returns the fixed header row only")
    func generateTemplateContentsReturnsHeaderOnly() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = SettingsExternalDataCSVService(modelContext: container.mainContext)

        #expect(service.generateTemplateContents() == columns.joined(separator: ",") + "\n")
    }

    @Test("checked-in external CSV fixture header matches generated template")
    func checkedInExternalCSVFixtureHeaderMatchesGeneratedTemplate() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = SettingsExternalDataCSVService(modelContext: container.mainContext)
        let fixtureURL = try TestHelpers.importFixtureURL(named: TestHelpers.externalCSVFixtureName, from: #filePath)
        let fixtureContents = try String(contentsOf: fixtureURL, encoding: .utf8)
        let fixtureHeader = fixtureContents.split(whereSeparator: \.isNewline).first.map(String.init)

        #expect(fixtureHeader == service.generateTemplateContents().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("shared schema metadata matches importer contract")
    func sharedSchemaMetadataMatchesImporterContract() throws {
        let definitions = Dictionary(
            uniqueKeysWithValues: SettingsExternalCSVSchema.recordDefinitions.map { ($0.type, $0) }
        )

        #expect(SettingsExternalCSVSchema.RecordType.allCases.map(\.rawValue) == [
            "period",
            "symptom",
            "blood_sugar",
            "supplement",
            "meal",
            "daily_log",
            "ovulation_observation",
        ])

        #expect(definitions[.period]?.requiredFields == [.recordType, .date, .flowIntensity])
        #expect(definitions[.period]?.optionalFields == [.notes])

        #expect(definitions[.symptom]?.requiredFields == [.recordType, .date, .symptomType, .severity])
        #expect(definitions[.symptom]?.optionalFields == [.notes])

        #expect(definitions[.bloodSugar]?.requiredFields == [.recordType, .timestamp, .glucoseValue, .readingType])
        #expect(definitions[.bloodSugar]?.optionalFields == [.mealContext, .notes])

        #expect(definitions[.supplement]?.requiredFields == [.recordType, .date, .supplementName, .timeTaken])
        #expect(definitions[.supplement]?.optionalFields == [.dosageMg, .taken, .brand])

        #expect(definitions[.meal]?.requiredFields == [.recordType, .timestamp, .mealType, .mealDescription, .glycemicImpact])
        #expect(definitions[.meal]?.optionalFields == [.carbsGrams, .proteinGrams, .fatGrams, .notes])

        #expect(definitions[.dailyLog]?.requiredFields == [.recordType, .date])
        #expect(definitions[.dailyLog]?.optionalFields == [.weight, .sleepHours, .activeMinutes, .stressLevel, .energyLevel, .waterOz])
        #expect(definitions[.dailyLog]?.noteDefaultValue == "daily_log requires at least one of weight, sleep_hours, active_minutes, stress_level, energy_level, or water_oz.")

        #expect(definitions[.ovulationObservation]?.requiredFields == [.recordType, .date])
        #expect(definitions[.ovulationObservation]?.optionalFields == [.basalBodyTemperatureCelsius, .cervicalMucus, .lhTestResult, .notes])

        #expect(SettingsExternalCSVSchema.acceptedValues(for: .recordType) == SettingsExternalCSVSchema.RecordType.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .flowIntensity) == FlowIntensity.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .symptomType) == SymptomType.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .readingType) == GlucoseReadingType.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .mealType) == MealType.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .glycemicImpact) == GlycemicImpact.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .cervicalMucus) == CervicalMucusType.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .lhTestResult) == LHTestResult.allCases.map(\.rawValue))
        #expect(SettingsExternalCSVSchema.acceptedValues(for: .taken) == ["true", "false"])
    }

    @Test("checked-in external CSV fixture imports every supported record type")
    func checkedInExternalCSVFixtureImportsSuccessfully() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)
        let fixtureURL = try TestHelpers.importFixtureURL(named: TestHelpers.externalCSVFixtureName, from: #filePath)
        let fixtureData = try Data(contentsOf: fixtureURL)

        let summary = try service.importCSV(data: fixtureData)

        #expect(summary.channel == .externalCSV)
        #expect(summary.changeCounts.inserted == 7)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.counts.cycles == 0)
        #expect(summary.counts.cycleEntries == 1)
        #expect(summary.counts.symptoms == 1)
        #expect(summary.counts.bloodSugarReadings == 1)
        #expect(summary.counts.supplements == 1)
        #expect(summary.counts.meals == 1)
        #expect(summary.counts.dailyLogs == 1)
        #expect(summary.counts.ovulationObservations == 1)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<OvulationObservation>()).count == 1)
    }

    @Test("importCSV inserts one row for each supported record type")
    func importCSVInsertsAllSupportedRecordTypes() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "period",
                "date": "2026-03-10",
                "flow_intensity": "medium",
                "notes": "Imported period",
            ],
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "4",
                "notes": "Imported symptom",
            ],
            [
                "record_type": "blood_sugar",
                "timestamp": "2026-03-10T08:15:00Z",
                "glucose_value": "112",
                "reading_type": "fasting",
                "notes": "Imported reading",
            ],
            [
                "record_type": "supplement",
                "date": "2026-03-10",
                "supplement_name": "Inositol",
                "dosage_mg": "2000",
                "time_taken": "08:30",
                "taken": "true",
                "brand": "Theralogix",
            ],
            [
                "record_type": "meal",
                "timestamp": "2026-03-10T12:30:00Z",
                "meal_type": "lunch",
                "meal_description": "Salad bowl",
                "glycemic_impact": "low",
                "carbs_grams": "25",
                "protein_grams": "18",
                "fat_grams": "9",
                "notes": "Imported meal",
            ],
            [
                "record_type": "daily_log",
                "date": "2026-03-10",
                "weight": "152.5",
                "sleep_hours": "7.2",
                "active_minutes": "42",
                "stress_level": "3",
                "energy_level": "4",
                "water_oz": "80",
            ],
            [
                "record_type": "ovulation_observation",
                "date": "2026-03-14",
                "basal_body_temperature_celsius": "36.72",
                "cervical_mucus": "eggWhite",
                "lh_test_result": "peak",
                "notes": "Imported ovulation signal",
            ],
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.channel == .externalCSV)
        #expect(summary.changeCounts.inserted == 7)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.counts.cycleEntries == 1)
        #expect(summary.counts.symptoms == 1)
        #expect(summary.counts.bloodSugarReadings == 1)
        #expect(summary.counts.supplements == 1)
        #expect(summary.counts.meals == 1)
        #expect(summary.counts.dailyLogs == 1)
        #expect(summary.counts.ovulationObservations == 1)

        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<OvulationObservation>()).count == 1)
    }

    @Test("pre-v3 external CSV header remains importable")
    func legacyExternalCSVHeaderImportsSuccessfully() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)
        let columns = SettingsExternalCSVSchema.legacyHeader
        let row: [String: String] = [
            "record_type": "blood_sugar",
            "timestamp": "2026-03-10T08:15:00Z",
            "glucose_value": "112",
            "reading_type": "fasting",
            "meal_context": "Morning baseline",
            "notes": "Legacy header row",
        ]
        let csv = ([columns.joined(separator: ",")] + [
            columns.map { row[$0] ?? "" }.joined(separator: ",")
        ]).joined(separator: "\n") + "\n"

        let summary = try service.importCSV(data: Data(csv.utf8))

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.counts.bloodSugarReadings == 1)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == 1)
    }

    @Test("period rows stage through cycle logic and create separate cycles after a long gap")
    func periodRowsCreateSeparateCyclesAfterLongGap() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "period",
                "date": "2026-03-01",
                "flow_intensity": "light",
            ],
            [
                "record_type": "period",
                "date": "2026-03-20",
                "flow_intensity": "heavy",
            ],
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 2)
        #expect(summary.changeCounts.rejected == 0)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).count == 2)
    }

    @Test("duplicate symptom rows are skipped")
    func duplicateSymptomRowsAreSkipped() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "3",
                "notes": "Same row",
            ],
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "3",
                "notes": "Same row",
            ],
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.skipped == 1)
        #expect(summary.changeCounts.rejected == 0)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == 1)
    }

    @Test("daily log rows upsert existing entries and preserve unspecified fields")
    func dailyLogRowsUpsertExistingEntries() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let existingLog = DailyLog(
            date: date("2026-03-10"),
            weight: 150.0,
            sleepHours: nil,
            activeMinutes: nil,
            stressLevel: 2,
            energyLevel: nil,
            waterOz: 70
        )
        context.insert(existingLog)
        try context.save()

        let service = SettingsExternalDataCSVService(modelContext: context)
        let data = csvData(rows: [
            [
                "record_type": "daily_log",
                "date": "2026-03-10",
                "sleep_hours": "7.5",
                "active_minutes": "38",
                "stress_level": "2",
            ]
        ])

        let summary = try service.importCSV(data: data)
        let logs = try context.fetch(FetchDescriptor<DailyLog>())

        #expect(summary.changeCounts.inserted == 0)
        #expect(summary.changeCounts.updated == 1)
        #expect(summary.changeCounts.rejected == 0)
        #expect(logs.count == 1)
        #expect(logs.first?.weight == 150.0)
        #expect(logs.first?.sleepHours == 7.5)
        #expect(logs.first?.activeMinutes == 38)
        #expect(logs.first?.waterOz == 70)
    }

    @Test("invalid header is rejected")
    func invalidHeaderIsRejected() throws {
        let container = try TestHelpers.makeModelContainer()
        let service = SettingsExternalDataCSVService(modelContext: container.mainContext)
        let data = Data("wrong,header\nvalue,row\n".utf8)

        #expect(throws: SettingsExternalDataCSVService.ImportError.self) {
            _ = try service.importCSV(data: data)
        }
    }

    @Test("invalid bool values are reported as rejected rows while leaving valid imports untouched")
    func invalidBoolValuesAreReportedAsRejectedRows() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)
        let data = csvData(rows: [
            [
                "record_type": "supplement",
                "date": "2026-03-10",
                "supplement_name": "Inositol",
                "time_taken": "08:30",
                "taken": "yes",
            ]
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 0)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "row 2")
        #expect(summary.issues.first?.reason.contains("taken") == true)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).isEmpty)
    }

    @Test("missing required values are reported while valid rows still import")
    func missingRequiredValuesAreReportedWhileValidRowsStillImport() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)
        let data = csvData(rows: [
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "4",
            ],
            [
                "record_type": "meal",
                "timestamp": "2026-03-10T12:30:00Z",
                "meal_type": "lunch",
                "glycemic_impact": "low",
            ]
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "row 3")
        #expect(summary.issues.first?.reason.contains("meal_description") == true)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    @Test("mixed valid and invalid rows import valid rows and report all rejected rows")
    func mixedValidityRowsImportValidRowsAndReportRejectedRows() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "4",
            ],
            [
                "record_type": "meal",
                "timestamp": "2026-03-10T12:30:00Z",
                "meal_type": "brunch",
                "meal_description": "Toast",
                "glycemic_impact": "low",
            ],
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "row 3")
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    @Test("blank supplement taken values default to true")
    func blankSupplementTakenValuesDefaultToTrue() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "supplement",
                "date": "2026-03-10",
                "supplement_name": "Inositol",
                "time_taken": "08:30",
            ]
        ])

        let summary = try service.importCSV(data: data)
        let supplements = try context.fetch(FetchDescriptor<SupplementLog>())

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.rejected == 0)
        #expect(supplements.count == 1)
        #expect(supplements.first?.taken == true)
    }

    @Test("multiple invalid CSV rows are accumulated into the import summary")
    func multipleInvalidCSVRowsAreAccumulated() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)

        let data = csvData(rows: [
            [
                "record_type": "symptom",
                "date": "2026-03-10",
                "symptom_type": "cramps",
                "severity": "9",
            ],
            [
                "record_type": "meal",
                "timestamp": "2026-03-10T12:30:00Z",
                "meal_type": "lunch",
                "glycemic_impact": "low",
            ],
        ])

        let summary = try service.importCSV(data: data)

        #expect(summary.changeCounts.inserted == 0)
        #expect(summary.changeCounts.rejected == 2)
        #expect(summary.issues.count == 2)
        #expect(summary.issues.map(\.location) == ["row 2", "row 3"])
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    private func csvData(rows: [[String: String]]) -> Data {
        let renderedRows = rows.map { row in
            columns.map { row[$0] ?? "" }.joined(separator: ",")
        }
        let csv = ([columns.joined(separator: ",")] + renderedRows).joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    private func date(_ rawValue: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = rawValue.split(separator: "-")
        var components = DateComponents()
        components.year = Int(parts[0])
        components.month = Int(parts[1])
        components.day = Int(parts[2])
        components.hour = 12
        return calendar.date(from: components)!
    }
}
