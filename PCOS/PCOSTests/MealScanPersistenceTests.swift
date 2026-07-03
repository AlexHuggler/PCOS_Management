import Testing
import Foundation
import SwiftData
import UIKit
@testable import PCOS

@Suite("Meal Scan Persistence", .serialized)
@MainActor
struct MealScanPersistenceTests {
    @Test("confirmed meal scan saves meal, items, summary, metadata, and reviewed nutrition import")
    func saveConfirmedMealScan() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let result = try await MealScanPipeline.mock().scan(image: UIImage(), mealType: .lunch)
        let confirmed = ConfirmedMealScan(
            scanResult: result,
            loggedAt: Date(timeIntervalSince1970: 1_779_331_200),
            mealType: .lunch,
            userConfirmed: true,
            hasUserEdits: true
        )

        try await SwiftDataMealLogRepository(modelContext: context).saveMealScan(confirmed)

        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        let items = try context.fetch(FetchDescriptor<MealScanFoodItem>())
        let summaries = try context.fetch(FetchDescriptor<MealScanNutritionSummary>())
        let metadata = try context.fetch(FetchDescriptor<MealScanMetadata>())
        let imports = try context.fetch(FetchDescriptor<NutritionImportRecord>())

        let meal = try #require(meals.first)
        #expect(meals.count == 1)
        #expect(items.count == result.detectedItems.count)
        #expect(summaries.count == 1)
        #expect(metadata.count == 1)
        #expect(imports.count == 1)
        #expect(meal.mealDescription == "Chicken rice bowl")
        #expect(meal.sourceLabel == "AI meal estimate")
        #expect(meal.mealSource == "ai_meal_scan")
        #expect(meal.userConfirmed == true)
        #expect(meal.confidenceScore == result.confidence.score)
        #expect(meal.carbsGrams == result.nutrition.carbsGrams)
        #expect(meal.proteinGrams == result.nutrition.proteinGrams)
        #expect(meal.fiberGrams == result.nutrition.fiberGrams)
        #expect(meal.sugarGrams == result.nutrition.sugarGrams)
        #expect(summaries.first?.netCarbsGrams == result.nutrition.netCarbsGrams)
        #expect(metadata.first?.originalPredictionJSON.isEmpty == false)
        #expect(metadata.first?.finalUserConfirmedJSON.isEmpty == false)
        #expect(metadata.first?.hasUserEdits == true)
        #expect(imports.first?.sourceKind == .aiMealScan)
        #expect(imports.first?.reviewStatus == .reviewed)
    }

    @Test("schema v5 backup round trips AI meal scan metadata")
    func backupRoundTripsMealScanFields() async throws {
        let source = try TestHelpers.makeModelContainer()
        let destination = try TestHelpers.makeModelContainer()
        let result = try await MealScanPipeline.mock().scan(image: UIImage(), mealType: .lunch)
        let confirmed = ConfirmedMealScan(scanResult: result, mealType: .lunch, userConfirmed: true)

        try await SwiftDataMealLogRepository(modelContext: source.mainContext).saveMealScan(confirmed)

        let backup = try SettingsDataBackupService(modelContext: source.mainContext)
            .makeBackupFile(source: .userExport)
        #expect(backup.schemaVersion == 5)
        #expect(backup.records.mealScanFoodItems.count == result.detectedItems.count)
        #expect(backup.records.mealScanNutritionSummaries.count == 1)
        #expect(backup.records.mealScanMetadata.count == 1)

        let data = try JSONEncoder.cycleBalanceBackup.encode(backup)
        let summary = try SettingsDataImportService(modelContext: destination.mainContext)
            .importBackupData(data)

        #expect(summary.counts.meals == 1)
        #expect(summary.counts.mealScanFoodItems == result.detectedItems.count)
        #expect(try destination.mainContext.fetch(FetchDescriptor<MealScanMetadata>()).first?.userConfirmed == true)
    }
}
