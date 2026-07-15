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
        var result = try await MealScanPipeline.mock().scan(image: UIImage(), mealType: .lunch)
        result.detectedItems[0].wasPortionAdjusted = true
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
        #expect(items.first(where: { $0.id == result.detectedItems[0].id })?.wasPortionAdjusted == true)
        #expect(summaries.count == 1)
        #expect(metadata.count == 1)
        #expect(imports.count == 1)
        #expect(meal.mealDescription == "Chicken rice bowl")
        #expect(meal.sourceLabel == "Photo meal estimate")
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

    @Test("reused meal saves repeated labels without rewriting item nutrition sources")
    func saveReusedMealPreservesItemNutritionSources() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        var result = try await MealScanPipeline.mock().scan(image: UIImage(), mealType: .dinner)
        var expectedSources: [UUID: NutritionDataSource] = [:]
        for index in result.detectedItems.indices {
            let source: NutritionDataSource = index.isMultiple(of: 2) ? .usda : .openFoodFacts
            result.detectedItems[index].nutritionSource = source
            expectedSources[result.detectedItems[index].id] = source
        }
        let repeatRecordID = UUID()
        let confirmed = ConfirmedMealScan(
            scanResult: result,
            mealType: .dinner,
            userConfirmed: true,
            repeatSourceRecordID: repeatRecordID
        )

        try await SwiftDataMealLogRepository(modelContext: context).saveMealScan(confirmed)

        let meal = try #require(context.fetch(FetchDescriptor<MealEntry>()).first)
        let nutritionImport = try #require(context.fetch(FetchDescriptor<NutritionImportRecord>()).first)
        let storedItems = try context.fetch(FetchDescriptor<MealScanFoodItem>())

        #expect(confirmed.repeatSourceRecordID == repeatRecordID)
        #expect(meal.sourceLabel == "Repeated reviewed meal")
        #expect(meal.mealSource == "reusedMeal")
        #expect(nutritionImport.sourceName == "Repeated reviewed meal")
        #expect(nutritionImport.sourceKind == .aiMealScan)
        #expect(storedItems.count == expectedSources.count)
        for item in storedItems {
            #expect(item.nutritionSource == expectedSources[item.id])
        }
    }

    @Test("schema v5 backup round trips AI meal scan metadata")
    func backupRoundTripsMealScanFields() async throws {
        let source = try TestHelpers.makeModelContainer()
        let destination = try TestHelpers.makeModelContainer()
        var result = try await MealScanPipeline.mock().scan(image: UIImage(), mealType: .lunch)
        result.detectedItems[0].wasPortionAdjusted = true
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
        #expect(
            try destination.mainContext.fetch(FetchDescriptor<MealScanFoodItem>())
                .first(where: { $0.id == result.detectedItems[0].id })?
                .wasPortionAdjusted == true
        )
    }
}
