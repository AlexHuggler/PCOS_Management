import Testing
import Foundation
import HealthKit
import SwiftData
@testable import PCOS

@Suite("Settings Data Backup + Import", .serialized)
@MainActor
struct SettingsDataBackupImportServiceTests {
    @Test("generateJSONBackupData returns a decodable schema-v1 backup")
    func generateJSONBackupDataReturnsDecodableSchemaV1Backup() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        context.insert(Cycle(startDate: Date()))
        try context.save()

        let backupService = SettingsDataBackupService(modelContext: context)
        let backupData = try backupService.generateJSONBackupData()
        let backup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)

        #expect(backup.schemaVersion == SettingsDataBackupFile.currentSchemaVersion)
        #expect(backup.source == .userExport)
        #expect(backup.records.cycles.count == 1)
    }

    @Test("repeat cache stays out of exports and replace-all import clears it")
    func repeatCacheIsPrivateAndClearedByReplaceAllImport() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let loggedAt = Date(timeIntervalSince1970: 1_780_100_000)
        let meal = MealEntry(
            timestamp: loggedAt,
            mealType: .lunch,
            mealDescription: "Private repeat source",
            glycemicImpact: .medium
        )
        let privateHash = "private-repeat-hash-9B85A66E"
        context.insert(meal)
        context.insert(
            MealScanRepeatCacheRecord(
                sourceMealID: meal.id,
                sourceImageHash: privateHash,
                featurePrintArchive: Data([0xDE, 0xAD, 0xBE, 0xEF]),
                visionRevision: 2,
                snapshotJSON: "{\"privateRepeatSnapshot\":true}",
                snapshotSchemaVersion: RepeatMealDraftSnapshot.currentSchemaVersion,
                mealName: "Private repeat source",
                mealType: .lunch,
                caloriesKcal: 410,
                proteinGrams: 28,
                carbsGrams: 44,
                fatGrams: 13,
                sourceMealLoggedAt: loggedAt
            )
        )
        try context.save()

        let backupData = try SettingsDataBackupService(modelContext: context).generateJSONBackupData()
        let backupJSON = try #require(String(data: backupData, encoding: .utf8))
        let csvURL = try SettingsDataExportService(modelContext: context).generateCSVExport()
        let csv = try String(contentsOf: csvURL, encoding: .utf8)

        for exportedText in [backupJSON, csv] {
            #expect(!exportedText.contains(privateHash))
            #expect(!exportedText.contains("privateRepeatSnapshot"))
            #expect(!exportedText.contains("featurePrintArchive"))
        }

        let emptyBackup = SettingsDataBackupFile(
            exportedAt: Date(),
            appVersion: "1.0.0",
            source: .userExport,
            records: SettingsDataBackupRecords()
        )
        _ = try SettingsDataImportService(modelContext: context).replaceAll(with: emptyBackup)

        #expect(try context.fetch(FetchDescriptor<MealScanRepeatCacheRecord>()).isEmpty)
    }

    @Test("generateJSONBackup writes a decodable schema-v1 file")
    func generateJSONBackupWritesDecodableSchemaV1File() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        context.insert(SymptomEntry(date: Date(), type: .cramps, severity: 3, notes: "exported"))
        try context.save()

        let backupService = SettingsDataBackupService(modelContext: context)
        let backupURL = try backupService.generateJSONBackup()
        let backupData = try Data(contentsOf: backupURL)
        let backup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)

        #expect(backupURL.lastPathComponent == "CycleBalance_Backup.json")
        #expect(backup.schemaVersion == SettingsDataBackupFile.currentSchemaVersion)
        #expect(backup.source == .userExport)
        #expect(backup.records.symptoms.count == 1)
    }

    @Test("JSON backup round-trip preserves typed records and relationships")
    func jsonBackupRoundTripPreservesTypedData() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let sourceContext = sourceContainer.mainContext

        let cycle = Cycle(startDate: Date())
        sourceContext.insert(cycle)

        let cycleEntry = CycleEntry(
            date: Date(),
            flowIntensity: .heavy,
            isPeriodDay: true,
            cyclePhase: .menstrual,
            notes: "High flow"
        )
        cycleEntry.cycle = cycle
        sourceContext.insert(cycleEntry)

        let symptom = SymptomEntry(date: Date(), type: .energyCrash, severity: 4, notes: "Afternoon slump")
        symptom.cycleEntry = cycleEntry
        sourceContext.insert(symptom)

        sourceContext.insert(BloodSugarReading(
            timestamp: Date(),
            glucoseValue: 142,
            readingType: .afterMeal,
            mealContext: "2h post lunch",
            notes: "Slight spike"
        ))

        sourceContext.insert(SupplementLog(
            date: Date(),
            supplementName: "Inositol",
            dosageMg: 2000,
            timeTaken: Date(),
            taken: false,
            brand: "Theralogix"
        ))

        sourceContext.insert(MealEntry(
            timestamp: Date(),
            mealType: .dinner,
            mealDescription: "Rice bowl",
            glycemicImpact: .high,
            photoData: Data([0xAA, 0xBB]),
            carbsGrams: 65,
            proteinGrams: 24,
            fatGrams: 14,
            notes: "Demo meal"
        ))

        sourceContext.insert(HairPhotoEntry(
            date: Date(),
            photoType: .faceChin,
            photoData: Data([0x01, 0x02, 0x03]),
            notes: "Lighting consistent",
            analysisResult: "No change"
        ))

        sourceContext.insert(DailyLog(
            date: Date(),
            weight: 152.5,
            sleepHours: 7.1,
            activeMinutes: 42,
            stressLevel: 3,
            energyLevel: 4,
            waterOz: 72
        ))

        sourceContext.insert(Insight(
            insightType: .dietImpact,
            title: "Meal trend",
            content: "Higher GI dinner tracked with energy dip.",
            confidence: 0.7,
            dataPointsUsed: 12,
            actionable: true,
            relatedSymptoms: ["energy_crash"]
        ))

        try sourceContext.save()

        let backupService = SettingsDataBackupService(modelContext: sourceContext)
        let backupData = try backupService.generateJSONBackupData()

        let destinationContainer = try TestHelpers.makeModelContainer()
        let destinationContext = destinationContainer.mainContext
        let importService = SettingsDataImportService(modelContext: destinationContext)
        let summary = try importService.importJSONBackup(data: backupData)

        #expect(
            summary.channel == .jsonBackup(
                schemaVersion: SettingsDataBackupFile.currentSchemaVersion,
                source: .userExport
            )
        )
        #expect(summary.changeCounts.inserted == 9)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.counts.cycles == 1)
        #expect(summary.counts.cycleEntries == 1)
        #expect(summary.counts.symptoms == 1)
        #expect(summary.counts.bloodSugarReadings == 1)
        #expect(summary.counts.supplements == 1)
        #expect(summary.counts.meals == 1)
        #expect(summary.counts.hairPhotos == 1)
        #expect(summary.counts.dailyLogs == 1)
        #expect(summary.counts.insights == 1)

        let importedCycleEntries = try destinationContext.fetch(FetchDescriptor<CycleEntry>())
        #expect(importedCycleEntries.first?.flowIntensity == .heavy)
        #expect(importedCycleEntries.first?.cyclePhase == .menstrual)

        let importedSymptoms = try destinationContext.fetch(FetchDescriptor<SymptomEntry>())
        #expect(importedSymptoms.first?.symptomType == .energyCrash)
        #expect(importedSymptoms.first?.category == .metabolic)
        #expect(importedSymptoms.first?.cycleEntry?.id == importedCycleEntries.first?.id)

        let importedReadings = try destinationContext.fetch(FetchDescriptor<BloodSugarReading>())
        #expect(importedReadings.first?.readingType == .afterMeal)
    }

    @Test("JSON backup schema v4 preserves ovulation observations")
    func jsonBackupSchemaV4PreservesOvulationObservations() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let sourceContext = sourceContainer.mainContext

        let observationID = UUID()
        let observationDate = Date(timeIntervalSince1970: 1_779_331_200)
        let createdAt = Date(timeIntervalSince1970: 1_779_334_800)
        sourceContext.insert(
            OvulationObservation(
                id: observationID,
                date: observationDate,
                basalBodyTemperatureCelsius: 36.72,
                cervicalMucus: .eggWhite,
                lhTestResult: .peak,
                notes: "Peak test and fertile mucus",
                createdAt: createdAt
            )
        )
        try sourceContext.save()

        let backupService = SettingsDataBackupService(modelContext: sourceContext)
        let backupData = try backupService.generateJSONBackupData()
        let backup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)
        let record = try #require(backup.records.ovulationObservations.first)

        #expect(backup.schemaVersion == SettingsDataBackupFile.currentSchemaVersion)
        #expect(backup.records.counts.ovulationObservations == 1)
        #expect(record.id == observationID)
        #expect(record.date == observationDate)
        #expect(record.basalBodyTemperatureCelsius == 36.72)
        #expect(record.cervicalMucus == .eggWhite)
        #expect(record.lhTestResult == .peak)
        #expect(record.notes == "Peak test and fertile mucus")
        #expect(record.createdAt == createdAt)

        let destinationContainer = try TestHelpers.makeModelContainer()
        let importService = SettingsDataImportService(modelContext: destinationContainer.mainContext)
        let summary = try importService.importJSONBackup(data: backupData)
        let imported = try destinationContainer.mainContext.fetch(FetchDescriptor<OvulationObservation>())

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.counts.ovulationObservations == 1)
        #expect(imported.count == 1)
        #expect(imported.first?.id == observationID)
        #expect(imported.first?.basalBodyTemperatureCelsius == 36.72)
        #expect(imported.first?.cervicalMucus == .eggWhite)
        #expect(imported.first?.lhTestResult == .peak)
    }

    @Test("JSON backup preserves nutrition imports and meal source metadata")
    func jsonBackupPreservesNutritionImportsAndMealSourceMetadata() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let sourceContext = sourceContainer.mainContext

        let importID = UUID()
        let mealDate = Date(timeIntervalSince1970: 1_779_331_200)
        sourceContext.insert(
            NutritionImportRecord(
                id: importID,
                sourceKind: .barcodeOpenFoodFacts,
                sourceName: "Open Food Facts",
                externalIdentifier: "737628064502",
                startDate: mealDate,
                barcode: "737628064502",
                productName: "Black Bean Snack",
                brandName: "Cycle Pantry",
                servingText: "1 bar (45 g)",
                calories: 180,
                carbsGrams: 24,
                proteinGrams: 8,
                fatGrams: 6,
                fiberGrams: 5,
                sugarGrams: 7,
                confidence: 0.82,
                completeness: 0.92,
                importedAt: mealDate,
                reviewStatus: .reviewed,
                userReviewed: true
            )
        )
        sourceContext.insert(
            MealEntry(
                timestamp: mealDate,
                mealType: .snack,
                mealDescription: "Black Bean Snack",
                glycemicImpact: .medium,
                carbsGrams: 24,
                proteinGrams: 8,
                fatGrams: 6,
                nutritionImportID: importID,
                barcode: "737628064502",
                sourceLabel: "Open Food Facts",
                calories: 180,
                fiberGrams: 5,
                sugarGrams: 7,
                servingText: "1 bar (45 g)"
            )
        )
        try sourceContext.save()

        let backupData = try SettingsDataBackupService(modelContext: sourceContext).generateJSONBackupData()
        let backup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)
        let nutritionRecord = try #require(backup.records.nutritionImports.first)
        let mealRecord = try #require(backup.records.meals.first)

        #expect(backup.schemaVersion == SettingsDataBackupFile.currentSchemaVersion)
        #expect(backup.records.counts.nutritionImports == 1)
        #expect(nutritionRecord.id == importID)
        #expect(nutritionRecord.sourceKind == .barcodeOpenFoodFacts)
        #expect(nutritionRecord.barcode == "737628064502")
        #expect(nutritionRecord.productName == "Black Bean Snack")
        #expect(nutritionRecord.fiberGrams == 5)
        #expect(nutritionRecord.reviewStatus == .reviewed)
        #expect(mealRecord.nutritionImportID == importID)
        #expect(mealRecord.calories == 180)
        #expect(mealRecord.servingText == "1 bar (45 g)")

        let destinationContainer = try TestHelpers.makeModelContainer()
        let importService = SettingsDataImportService(modelContext: destinationContainer.mainContext)
        let summary = try importService.importJSONBackup(data: backupData)
        let importedNutrition = try destinationContainer.mainContext.fetch(FetchDescriptor<NutritionImportRecord>())
        let importedMeals = try destinationContainer.mainContext.fetch(FetchDescriptor<MealEntry>())

        #expect(summary.changeCounts.inserted == 2)
        #expect(summary.counts.nutritionImports == 1)
        #expect(importedNutrition.first?.id == importID)
        #expect(importedNutrition.first?.sourceKind == .barcodeOpenFoodFacts)
        #expect(importedMeals.first?.nutritionImportID == importID)
        #expect(importedMeals.first?.sourceLabel == "Open Food Facts")
    }

    @Test("JSON backup preserves HealthKit imported sample provenance")
    func jsonBackupPreservesHealthKitImportedSampleProvenance() throws {
        let sourceContainer = try TestHelpers.makeModelContainer()
        let sourceContext = sourceContainer.mainContext
        let sampleDate = Date(timeIntervalSince1970: 1_700_300_000)
        sourceContext.insert(
            HealthKitImportedSampleRecord(
                sampleUUID: "flo-cycle-sample-1",
                healthKitIdentifier: HKCategoryTypeIdentifier.menstrualFlow.rawValue,
                sourceName: "Flo",
                sourceBundleIdentifier: "org.flo",
                startDate: sampleDate,
                endDate: sampleDate.addingTimeInterval(60),
                categoryValue: HKCategoryValueMenstrualFlow.light.rawValue,
                derivedRecordKind: .cycleEntry,
                derivedRecordID: UUID(),
                importedAt: sampleDate,
                notes: "From Flo via Apple Health."
            )
        )
        try sourceContext.save()

        let backupData = try SettingsDataBackupService(modelContext: sourceContext).generateJSONBackupData()
        let backup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: backupData)
        let backedUpRecord = try #require(backup.records.healthKitImportedSamples.first)

        #expect(backup.records.counts.healthKitImportedSamples == 1)
        #expect(backedUpRecord.sourceName == "Flo")
        #expect(backedUpRecord.derivedRecordKind == .cycleEntry)

        let destinationContainer = try TestHelpers.makeModelContainer()
        let importService = SettingsDataImportService(modelContext: destinationContainer.mainContext)
        let summary = try importService.importJSONBackup(data: backupData)
        let importedRecords = try destinationContainer.mainContext.fetch(FetchDescriptor<HealthKitImportedSampleRecord>())

        #expect(summary.counts.healthKitImportedSamples == 1)
        #expect(importedRecords.count == 1)
        #expect(importedRecords.first?.sampleUUID == "flo-cycle-sample-1")
        #expect(importedRecords.first?.sourceLabel == "Flo")
    }

    @Test("checked-in demo backup fixture imports successfully")
    func checkedInDemoBackupFixtureImportsSuccessfully() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)
        let fixtureURL = try TestHelpers.importFixtureURL(named: TestHelpers.demoBackupFixtureName, from: #filePath)
        let fixtureData = try Data(contentsOf: fixtureURL)
        let fixtureBackup = try SettingsDataBackupCoding.makeDecoder().decode(SettingsDataBackupFile.self, from: fixtureData)

        let summary = try importService.importJSONBackup(data: fixtureData)

        #expect(
            summary.channel == .jsonBackup(
                schemaVersion: fixtureBackup.schemaVersion,
                source: fixtureBackup.source
            )
        )
        #expect(summary.counts == fixtureBackup.records.counts)
        #expect(summary.changeCounts.inserted == fixtureBackup.records.counts.total)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.issues.isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == fixtureBackup.records.cycles.count)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).count == fixtureBackup.records.cycleEntries.count)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).count == fixtureBackup.records.symptoms.count)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).count == fixtureBackup.records.bloodSugarReadings.count)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).count == fixtureBackup.records.supplements.count)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).count == fixtureBackup.records.meals.count)
        #expect(try context.fetch(FetchDescriptor<HairPhotoEntry>()).count == fixtureBackup.records.hairPhotos.count)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).count == fixtureBackup.records.dailyLogs.count)
        #expect(try context.fetch(FetchDescriptor<Insight>()).count == fixtureBackup.records.insights.count)
        #expect(try context.fetch(FetchDescriptor<PregnancyRecord>()).count == fixtureBackup.records.pregnancyRecords.count)
        #expect(try context.fetch(FetchDescriptor<OvulationObservation>()).count == fixtureBackup.records.ovulationObservations.count)
    }

    @Test("all checked-in JSON backup fixtures import successfully")
    func allCheckedInJSONBackupFixturesImportSuccessfully() throws {
        let importsURL = try TestHelpers.projectRoot(from: #filePath)
            .appendingPathComponent("TestData", isDirectory: true)
            .appendingPathComponent("Imports", isDirectory: true)

        let fixtureURLs = try FileManager.default.contentsOfDirectory(
            at: importsURL,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fixtureURL in fixtureURLs {
            let container = try TestHelpers.makeModelContainer()
            let context = container.mainContext
            let importService = SettingsDataImportService(modelContext: context)
            let fixtureData = try Data(contentsOf: fixtureURL)
            let fixtureBackup: SettingsDataBackupFile

            do {
                fixtureBackup = try SettingsDataBackupCoding.makeDecoder().decode(
                    SettingsDataBackupFile.self,
                    from: fixtureData
                )
            } catch {
                Issue.record("Fixture \(fixtureURL.lastPathComponent) failed to decode: \(error)")
                continue
            }

            do {
                let summary = try importService.importJSONBackup(data: fixtureData)
                if summary.counts != fixtureBackup.records.counts {
                    Issue.record(
                        "Fixture \(fixtureURL.lastPathComponent) imported counts \(summary.counts) but expected \(fixtureBackup.records.counts)."
                    )
                }
                if summary.changeCounts.rejected != 0 || summary.hasIssues {
                    Issue.record(
                        "Fixture \(fixtureURL.lastPathComponent) imported with unexpected issues: \(summary.issues)"
                    )
                }
            } catch {
                Issue.record("Fixture \(fixtureURL.lastPathComponent) failed to import: \(error)")
            }
        }
    }

    @Test("import rejects unsupported schema version")
    func importRejectsUnsupportedSchemaVersion() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

        let backup = SettingsDataBackupFile(
            schemaVersion: 99,
            exportedAt: Date(),
            appVersion: "1.0.0",
            source: .userExport,
            records: SettingsDataBackupRecords()
        )
        let data = try SettingsDataBackupCoding.makeEncoder().encode(backup)

        #expect(
            throws: SettingsDataImportService.ImportError.unsupportedSchemaVersion(
                expected: SettingsDataBackupFile.currentSchemaVersion,
                actual: 99
            )
        ) {
            _ = try importService.importJSONBackup(data: data)
        }
    }

    @Test("import decoder accepts both fractional and standard ISO8601 date strings")
    func importAcceptsBothIsoDateFormats() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

        let json = """
        {
          "appVersion":"1.0.0",
          "exportedAt":"2026-03-12T14:30:00.123Z",
          "records":{
            "bloodSugarReadings":[],
            "cycleEntries":[],
            "cycles":[
              {
                "endDate":"2026-01-15T12:00:00Z",
                "id":"11111111-1111-1111-1111-111111111111",
                "isPredicted":false,
                "lengthDays":35,
                "startDate":"2025-12-12T12:00:00.000Z"
              }
            ],
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

        let summary = try importService.importJSONBackup(data: Data(json.utf8))
        #expect(summary.counts.cycles == 1)
    }

    @Test("fully invalid JSON backup leaves existing data untouched and reports rejected references")
    func fullyInvalidJSONBackupLeavesExistingDataUntouched() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        context.insert(Cycle(startDate: Date()))
        try context.save()

        let backup = SettingsDataBackupFile(
            exportedAt: Date(),
            appVersion: "1.0.0",
            source: .userExport,
            records: SettingsDataBackupRecords(
                cycles: [],
                cycleEntries: [
                    CycleEntryRecord(
                        id: UUID(),
                        date: Date(),
                        flowIntensity: .light,
                        isPeriodDay: true,
                        cyclePhase: .menstrual,
                        notes: nil,
                        createdAt: Date(),
                        cycleID: UUID()
                    )
                ]
            )
        )
        let data = try SettingsDataBackupCoding.makeEncoder().encode(backup)
        let importService = SettingsDataImportService(modelContext: context)

        let summary = try importService.importJSONBackup(data: data)

        let cycles = try context.fetch(FetchDescriptor<Cycle>())
        #expect(summary.changeCounts.inserted == 0)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.counts.total == 0)
        #expect(summary.hasIssues)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "cycleEntries[0]")
        #expect(summary.issues.first?.reason.contains("missing or rejected cycle") == true)
        #expect(cycles.count == 1)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).isEmpty)
    }

    @Test("mixed valid and invalid JSON backup records import the valid subset and report rejected rows")
    func mixedValidityJSONBackupImportsValidSubset() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

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
            "cycles":[
              {
                "startDate":"2026-03-01T12:00:00Z"
              }
            ],
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

        let summary = try importService.importJSONBackup(data: Data(json.utf8))

        #expect(summary.changeCounts.inserted == 1)
        #expect(summary.changeCounts.updated == 0)
        #expect(summary.changeCounts.skipped == 0)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.counts.cycles == 1)
        #expect(summary.counts.cycleEntries == 0)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "cycleEntries[0]")
        #expect(summary.issues.first?.reason.contains("flowIntensity") == true)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).isEmpty)
    }

    @Test("invalid JSON record IDs are reported as rejected issues instead of aborting the import")
    func invalidJSONRecordIDsAreReportedAsRejectedIssues() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

        let json = """
        {
          "appVersion":"1.0.0",
          "exportedAt":"2026-03-12T14:30:00Z",
          "records":{
            "bloodSugarReadings":[],
            "cycleEntries":[],
            "cycles":[],
            "dailyLogs":[],
            "hairPhotos":[],
            "insights":[],
            "meals":[],
            "supplements":[],
            "symptoms":[
              {
                "category":"pain",
                "cycleEntryID":null,
                "date":"2026-03-10T12:00:00Z",
                "id":"not-a-uuid",
                "notes":null,
                "severity":3,
                "symptomType":"cramps"
              }
            ]
          },
          "schemaVersion":1,
          "source":{"kind":"user_export","scenarioID":null}
        }
        """

        let summary = try importService.importJSONBackup(data: Data(json.utf8))

        #expect(summary.changeCounts.inserted == 0)
        #expect(summary.changeCounts.rejected == 1)
        #expect(summary.issues.count == 1)
        #expect(summary.issues.first?.location == "symptoms[0]")
        #expect(summary.issues.first?.reason.contains("Invalid id") == true)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).isEmpty)
    }

    @Test("JSON backup import applies defaults for missing optional metadata and record fields")
    func jsonBackupImportAppliesDefaultsForMissingOptionalFields() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

        let json = """
        {
          "records":{
            "bloodSugarReadings":[],
            "cycleEntries":[],
            "cycles":[],
            "dailyLogs":[],
            "hairPhotos":[],
            "insights":[
              {
                "content":"Example content",
                "generatedDate":"2026-03-10T12:00:00Z",
                "insightType":"cycle_pattern",
                "title":"Example title"
              }
            ],
            "meals":[],
            "supplements":[
              {
                "date":"2026-03-10T12:00:00Z",
                "supplementName":"Magnesium",
                "timeTaken":"2026-03-10T21:30:00Z"
              }
            ],
            "symptoms":[
              {
                "date":"2026-03-10T12:00:00Z",
                "severity":3,
                "symptomType":"cramps"
              }
            ]
          }
        }
        """

        let summary = try importService.importJSONBackup(data: Data(json.utf8))
        let insights = try context.fetch(FetchDescriptor<Insight>())
        let supplements = try context.fetch(FetchDescriptor<SupplementLog>())
        let symptoms = try context.fetch(FetchDescriptor<SymptomEntry>())

        #expect(summary.changeCounts.inserted == 3)
        #expect(summary.changeCounts.rejected == 0)
        #expect(summary.issues.isEmpty)
        #expect(insights.count == 1)
        #expect(insights.first?.confidence == 0)
        #expect(insights.first?.dataPointsUsed == 0)
        #expect(insights.first?.actionable == true)
        #expect(insights.first?.relatedSymptoms == [])
        #expect(supplements.count == 1)
        #expect(supplements.first?.taken == true)
        #expect(symptoms.count == 1)
        #expect(symptoms.first?.category == .pain)
    }

    @Test("JSON backup records without IDs receive generated UUIDs and still import")
    func jsonBackupRecordsWithoutIDsReceiveGeneratedUUIDs() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let importService = SettingsDataImportService(modelContext: context)

        let json = """
        {
          "records":{
            "bloodSugarReadings":[
              {
                "timestamp":"2026-03-10T08:15:00Z",
                "glucoseValue":101,
                "readingType":"fasting"
              },
              {
                "timestamp":"2026-03-11T08:15:00Z",
                "glucoseValue":104,
                "readingType":"fasting"
              }
            ]
          }
        }
        """

        let summary = try importService.importJSONBackup(data: Data(json.utf8))
        let readings = try context.fetch(FetchDescriptor<BloodSugarReading>())

        #expect(summary.changeCounts.inserted == 2)
        #expect(summary.changeCounts.rejected == 0)
        #expect(readings.count == 2)
        #expect(Set(readings.map(\.id)).count == 2)
    }
}
