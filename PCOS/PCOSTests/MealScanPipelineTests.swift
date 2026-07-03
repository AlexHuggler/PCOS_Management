import Testing
import Foundation
import UIKit
@testable import PCOS

@Suite("Meal Scan Pipeline")
@MainActor
struct MealScanPipelineTests {
    @Test("mock pipeline returns deterministic editable meal estimate")
    func mockPipelineReturnsMealEstimate() async throws {
        let pipeline = MealScanPipeline.mock()

        let result = try await pipeline.scan(image: UIImage(), mealType: .lunch)

        #expect(result.mealName == "Chicken rice bowl")
        #expect(result.detectedItems.count >= 3)
        #expect(result.nutrition.caloriesKcal > 400)
        #expect(result.metabolicProfile.estimatedGlycemicImpact == .moderate)
        #expect(result.confidence == .medium)
        #expect(result.warnings.contains(where: { $0.localizedCaseInsensitiveContains("oil") }))
    }

    @Test("missing model registry falls back to mock classification and does not crash")
    func missingModelRegistryFallsBackToMock() async throws {
        let registry = MealScanModelRegistry(
            foodClassifierModelName: nil,
            foodSegmentationModelName: nil,
            depthModelName: nil,
            modelVersion: "test-missing"
        )
        let pipeline = MealScanPipeline.production(registry: registry)

        let result = try await pipeline.scan(image: UIImage(), mealType: .dinner)

        #expect(result.detectedItems.isEmpty == false)
        #expect(result.modelVersion == "mock-food-fixtures")
        #expect(result.pipelineVersion == MealScanPipeline.pipelineVersion)
    }

    @Test("local fixture repository decodes common foods and aliases")
    func fixtureRepositorySearchesFoodsAndAliases() async throws {
        let repository = LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)

        let riceMatches = try await repository.searchFood(query: "plain rice")
        let chicken = try await repository.nutrition(forFoodId: "chicken-breast-cooked")

        #expect(riceMatches.first?.id == "rice-white-cooked")
        #expect(chicken?.proteinPer100g ?? 0 > 25)
    }

    @Test("density defaults convert volume estimates to grams")
    func densityDefaultsConvertVolumeToGrams() {
        let defaults = FoodDensityDefaults.fixture

        #expect(defaults.grams(forVolumeMl: 200, category: .cookedRice) == 170)
        #expect(defaults.grams(forVolumeMl: 30, category: .oilDressing) == 27)
    }

    @Test("meal scan JSON resources decode")
    func mealScanResourcesDecode() throws {
        let root = try TestHelpers.projectRoot()
            .appendingPathComponent("PCOS/PCOS/Features/Meals/MealScan/Resources", isDirectory: true)
        let decoder = JSONDecoder()

        let foods = try decoder.decode(
            [FoodNutritionRecord].self,
            from: Data(contentsOf: root.appendingPathComponent("SampleNutritionFixtures.json"))
        )
        let aliases = try decoder.decode(
            [FoodAlias].self,
            from: Data(contentsOf: root.appendingPathComponent("FoodAliases.json"))
        )
        let densities = try decoder.decode(
            [String: Double].self,
            from: Data(contentsOf: root.appendingPathComponent("FoodDensityDefaults.json"))
        )

        #expect(foods.contains(where: { $0.id == "olive-oil" }))
        #expect(aliases.contains(where: { $0.inputName == "smoothie" }))
        #expect(densities["cookedRice"] == 0.85)
    }
}
