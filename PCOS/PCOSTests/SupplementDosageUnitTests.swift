import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Supplement dosage units", .serialized)
@MainActor
struct SupplementDosageUnitTests {
    private func preset(_ key: String) throws -> PCOSSupplement {
        try #require(PCOSSupplements.catalog.first { $0.key == key })
    }

    @Test("Catalog presets carry clinically correct units and plausible amounts")
    func catalogPresetUnits() throws {
        let vitaminD = try preset("vitamin_d")
        #expect(vitaminD.defaultDosage == 2000)
        #expect(vitaminD.defaultDosageUnit == .internationalUnit)

        let folate = try preset("folate")
        #expect(folate.defaultDosage == 400)
        #expect(folate.defaultDosageUnit == .microgram)

        let chromium = try preset("chromium")
        #expect(chromium.defaultDosage == 200)
        #expect(chromium.defaultDosageUnit == .microgram)

        let inositol = try preset("inositol")
        #expect(inositol.defaultDosage == 4000)
        #expect(inositol.defaultDosageUnit == .milligram)

        for supplement in PCOSSupplements.catalog {
            #expect(
                supplement.defaultDosage <= supplement.defaultDosageUnit.plausibleMaximumDose,
                "\(supplement.name) preset \(supplement.defaultDosage) \(supplement.defaultDosageUnit.rawValue) exceeds a plausible dose"
            )
        }
    }

    @Test("Dose formatting appends the unit symbol instead of assuming milligrams")
    func doseFormattingUsesUnit() {
        #expect(DosageUnit.formatted(2000, unit: .internationalUnit) == "\(L10n.decimal(2000, fractionDigits: 0)) IU")
        #expect(DosageUnit.formatted(400, unit: .microgram) == "\(L10n.decimal(400, fractionDigits: 0)) mcg")
        #expect(DosageUnit.formatted(0.5, unit: .gram) == "\(L10n.decimal(0.5, fractionDigits: 1)) g")
        #expect(DosageUnit.formatted(4000, unit: .milligram) == "\(L10n.decimal(4000, fractionDigits: 0)) mg")
    }

    @Test("Logged supplements default to milligrams and persist the chosen unit")
    func logsPersistUnit() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = SupplementViewModel(modelContext: container.mainContext)

        try viewModel.logSupplement(name: "Vitamin D", dosageMg: 2000, dosageUnit: .internationalUnit, brand: nil, time: Date())
        try viewModel.logSupplement(name: "Magnesium", dosageMg: 400, brand: nil, time: Date())

        let logs = viewModel.fetchTodaysLogs()
        #expect(logs.first { $0.supplementName == "Vitamin D" }?.dosageUnit == .internationalUnit)
        #expect(logs.first { $0.supplementName == "Magnesium" }?.dosageUnit == .milligram)
    }

    @Test("Recommended dosage label shows the preset unit")
    func recommendedLabelUsesPresetUnit() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = SupplementViewModel(modelContext: container.mainContext)
        let vitaminD = try preset("vitamin_d")

        let label = viewModel.recommendedDosageLabel(for: vitaminD)
        #expect(label.hasSuffix(" IU"), "label was \(label)")
        #expect(label.contains(L10n.decimal(2000, fractionDigits: 0)))
    }

    @Test("JSON backup preserves the dose unit and treats legacy records as milligrams")
    func backupPreservesUnit() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let sourceContext = sourceContainer.mainContext
        sourceContext.insert(SupplementLog(date: Date(), supplementName: "Vitamin D", dosageMg: 2000, dosageUnit: .internationalUnit, timeTaken: Date()))
        sourceContext.insert(SupplementLog(date: Date(), supplementName: "Magnesium", dosageMg: 400, timeTaken: Date()))
        try sourceContext.save()

        let backupData = try SettingsDataBackupService(modelContext: sourceContext).generateJSONBackupData()
        let decoded = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)
        #expect(decoded.records.supplements.first { $0.supplementName == "Vitamin D" }?.dosageUnit == "IU")

        let destinationContainer = try TestHelpers.makeModelContainer()
        let destinationContext = destinationContainer.mainContext
        _ = try SettingsDataImportService(modelContext: destinationContext).importJSONBackup(data: backupData)
        let imported = try destinationContext.fetch(FetchDescriptor<SupplementLog>())
        #expect(imported.first { $0.supplementName == "Vitamin D" }?.dosageUnit == .internationalUnit)
        #expect(imported.first { $0.supplementName == "Magnesium" }?.dosageUnit == .milligram)

        // Legacy backups have no dosageUnit key and must decode as nil (imported as milligrams).
        var legacyRecord = SupplementLogRecord(id: UUID(), date: Date(), supplementName: "Folate", dosageMg: 400, timeTaken: Date(), taken: true, brand: nil)
        legacyRecord.dosageUnit = nil
        let legacyData = try JSONEncoder().encode(legacyRecord)
        #expect(try JSONDecoder().decode(SupplementLogRecord.self, from: legacyData).dosageUnit == nil)
    }

    @Test("External CSV import reads an optional dosage_unit column and defaults to milligrams")
    func csvImportReadsUnit() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = SettingsExternalDataCSVService(modelContext: context)
        let columns = SettingsExternalCSVSchema.header
        #expect(columns.contains("dosage_unit"))

        let rows: [[String: String]] = [
            ["record_type": "supplement", "date": "2026-03-10", "supplement_name": "Vitamin D", "dosage_mg": "2000", "dosage_unit": "IU", "time_taken": "08:30", "taken": "true"],
            ["record_type": "supplement", "date": "2026-03-11", "supplement_name": "Magnesium", "dosage_mg": "400", "time_taken": "08:30", "taken": "true"],
        ]
        let rendered = ([columns.joined(separator: ",")] + rows.map { row in columns.map { row[$0] ?? "" }.joined(separator: ",") }).joined(separator: "\n") + "\n"
        let summary = try service.importCSV(data: Data(rendered.utf8))
        #expect(summary.counts.supplements == 2)

        let logs = try context.fetch(FetchDescriptor<SupplementLog>())
        #expect(logs.first { $0.supplementName == "Vitamin D" }?.dosageUnit == .internationalUnit)
        #expect(logs.first { $0.supplementName == "Magnesium" }?.dosageUnit == .milligram)
    }

    @Test("Supplement surfaces no longer hard-code milligrams")
    func viewsDoNotHardcodeMilligrams() throws {
        let projectRoot = try TestHelpers.projectRoot(from: #filePath)
        func source(_ relativePath: String) throws -> String {
            try String(contentsOf: projectRoot.appendingPathComponent(relativePath), encoding: .utf8)
        }
        let logView = try source("PCOS/PCOS/Features/Supplements/Views/SupplementLogView.swift")
        #expect(!logView.contains("Text(\"\\(Int(dosage)) mg\")"))
        #expect(!logView.contains("Text(\"mg\")"))
        let historyView = try source("PCOS/PCOS/Features/Supplements/Views/SupplementHistoryView.swift")
        #expect(!historyView.contains("return \"\\(formatted) mg\""))
        let exportService = try source("PCOS/PCOS/App/SettingsDataExportService.swift")
        #expect(!exportService.contains(") mg\""))
    }
}
