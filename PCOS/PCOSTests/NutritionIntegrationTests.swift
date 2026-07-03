import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Nutrition Import Integrations", .serialized)
@MainActor
struct NutritionIntegrationTests {
    @Test("Open Food Facts normalizer maps product nutrition and completeness")
    func openFoodFactsNormalizerMapsProductNutrition() throws {
        let json = """
        {
          "code": "737628064502",
          "status": 1,
          "product": {
            "product_name": "Black Bean Snack",
            "brands": "Cycle Pantry",
            "serving_size": "1 bar (45 g)",
            "nutriments": {
              "energy-kcal_serving": 180,
              "carbohydrates_serving": 24,
              "proteins_serving": 8,
              "fat_serving": 6,
              "fiber_serving": 5,
              "sugars_serving": 7
            }
          }
        }
        """

        let product = try OpenFoodFactsProductNormalizer.normalizedProduct(
            from: Data(json.utf8),
            barcode: "737628064502"
        )

        #expect(product.sourceKind == .barcodeOpenFoodFacts)
        #expect(product.sourceLabel == "Open Food Facts")
        #expect(product.barcode == "737628064502")
        #expect(product.productName == "Black Bean Snack")
        #expect(product.brandName == "Cycle Pantry")
        #expect(product.servingText == "1 bar (45 g)")
        #expect(product.calories == 180)
        #expect(product.carbsGrams == 24)
        #expect(product.proteinGrams == 8)
        #expect(product.fatGrams == 6)
        #expect(product.fiberGrams == 5)
        #expect(product.sugarGrams == 7)
        #expect(product.completeness > 0.85)
    }

    @Test("USDA fallback is disabled without a local API key")
    func usdaFallbackIsDisabledWithoutKey() async throws {
        let service = USDAFoodDataCentralLookupService(apiKey: nil)

        #expect(service.isEnabled == false)
        await #expect(throws: FoodLookupError.apiKeyMissing) {
            _ = try await service.lookupBarcode("737628064502")
        }
    }

    @Test("Nutrition candidate saves a reviewed import and linked meal metadata")
    func nutritionCandidateSavesReviewedImportAndMealMetadata() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let viewModel = MealViewModel(modelContext: context)
        let importedAt = Date(timeIntervalSince1970: 1_779_331_200)

        viewModel.applyNutritionCandidate(
            FoodProductCandidate(
                sourceKind: .barcodeOpenFoodFacts,
                sourceLabel: "Open Food Facts",
                sourceName: "Open Food Facts",
                externalIdentifier: "737628064502",
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
                waterOz: nil,
                confidence: 0.82,
                completeness: 0.92
            ),
            importedAt: importedAt
        )

        #expect(viewModel.mealDescription == "Black Bean Snack")
        #expect(viewModel.carbsText == "24")
        #expect(viewModel.pendingNutritionImportSummary?.sourceLabel == "Open Food Facts")

        try viewModel.saveMeal()

        let imports = try context.fetch(FetchDescriptor<NutritionImportRecord>())
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        let nutritionImport = try #require(imports.first)
        let meal = try #require(meals.first)

        #expect(imports.count == 1)
        #expect(nutritionImport.userReviewed == true)
        #expect(nutritionImport.reviewStatus == .reviewed)
        #expect(nutritionImport.barcode == "737628064502")
        #expect(meal.nutritionImportID == nutritionImport.id)
        #expect(meal.sourceLabel == "Open Food Facts")
        #expect(meal.calories == 180)
        #expect(meal.fiberGrams == 5)
        #expect(meal.sugarGrams == 7)
        #expect(meal.servingText == "1 bar (45 g)")
    }

    @Test("Aha moment prioritizes HealthKit nutrition import source summaries")
    func ahaMomentPrioritizesHealthKitNutritionSourceSummaries() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_779_331_200)

        for offset in 0..<4 {
            context.insert(
                NutritionImportRecord(
                    sourceKind: .healthKit,
                    sourceName: "YAZIO",
                    externalIdentifier: "sample-\(offset)",
                    startDate: Calendar.current.date(byAdding: .day, value: -offset, to: now) ?? now,
                    productName: nil,
                    carbsGrams: 30 + Double(offset),
                    proteinGrams: 12,
                    importedAt: now
                )
            )
        }
        try context.save()

        let resolvedMoment = try AhaMomentService(modelContext: context)
            .topMoment(isPremium: false, now: now)
        let moment = try #require(resolvedMoment)

        #expect(moment.title == "YAZIO added 4 nutrition days")
        #expect(moment.body.contains("Apple Health"))
        #expect(moment.nextAction == "Review one imported day before logging your next meal.")
        #expect(moment.premiumDetail == nil)
    }
}
