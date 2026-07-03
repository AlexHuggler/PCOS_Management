import Testing
import Foundation
import SwiftData
@testable import PCOS

@MainActor
enum TestHelpers {
    static let demoBackupFixtureName = "CycleBalance_Demo_Backup_SymptomManagement.json"
    static let externalCSVFixtureName = "CycleBalance_Demo_ExternalImport.csv"

    /// Creates an in-memory ModelContainer for testing.
    static func makeModelContainer() throws -> ModelContainer {
        let schema = Schema([
            CycleEntry.self,
            Cycle.self,
            OvulationObservation.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            MealScanFoodItem.self,
            MealScanNutritionSummary.self,
            MealScanMetadata.self,
            MealScanResultCacheRecord.self,
            NutritionImportRecord.self,
            HealthKitImportedSampleRecord.self,
            HairPhotoEntry.self,
            DailyLog.self,
            PregnancyRecord.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func projectRoot(from filePath: StaticString = #filePath) throws -> URL {
        let sourceFileURL = URL(fileURLWithPath: "\(filePath)")
        var candidateURL = sourceFileURL.deletingLastPathComponent()
        let fileManager = FileManager.default

        while candidateURL.path != "/" {
            if fileManager.fileExists(atPath: candidateURL.appendingPathComponent("project.yml").path) {
                return candidateURL
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL == candidateURL {
                break
            }
            candidateURL = parentURL
        }

        throw NSError(
            domain: "TestHelpers",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate project root for \(filePath)."]
        )
    }

    static func importFixtureURL(
        named fileName: String,
        from filePath: StaticString = #filePath
    ) throws -> URL {
        let fixtureURL = try projectRoot(from: filePath)
            .appendingPathComponent("TestData", isDirectory: true)
            .appendingPathComponent("Imports", isDirectory: true)
            .appendingPathComponent(fileName)

        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw NSError(
                domain: "TestHelpers",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing import fixture at \(fixtureURL.path)."]
            )
        }

        return fixtureURL
    }
}
