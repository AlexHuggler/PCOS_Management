import Testing
import SwiftData
import UIKit
@testable import PCOS

@Suite("Meal Scan ViewModel", .serialized)
@MainActor
struct MealScanViewModelTests {
    @Test("scanning mock image updates review totals and manual fallback stays available")
    func scanUpdatesReviewTotals() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )

        #expect(viewModel.canAddManualFood)
        try await viewModel.scan(image: UIImage())

        #expect(viewModel.phase == .review)
        #expect(viewModel.draftItems.isEmpty == false)
        #expect(viewModel.totalNutrition.caloriesKcal > 0)
        #expect(viewModel.confidence == .medium)
    }

    @Test("editing grams recalculates item and meal totals")
    func editingGramsRecalculatesTotals() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )
        try await viewModel.scan(image: UIImage())
        let firstID = try #require(viewModel.draftItems.first?.id)
        let originalCalories = viewModel.totalNutrition.caloriesKcal

        viewModel.updateItem(id: firstID) { item in
            item.estimatedGrams *= 2
        }

        #expect(viewModel.draftItems.first?.wasUserEdited == true)
        #expect(viewModel.totalNutrition.caloriesKcal > originalCalories)
        #expect(viewModel.hasUserEdits)
    }

    @Test("hidden oil prompt adds oil estimate and lowers confidence")
    func hiddenOilPromptUpdatesTotalsAndConfidence() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )
        try await viewModel.scan(image: UIImage())
        let originalFat = viewModel.totalNutrition.fatGrams

        viewModel.applyHiddenIngredientEstimate(.moderate)

        #expect(viewModel.totalNutrition.fatGrams > originalFat)
        #expect(viewModel.draftItems.contains(where: { $0.canonicalFoodId == "olive-oil" }))
        #expect(viewModel.confidence == .low || viewModel.confidence == .medium)
    }

    @Test("scan failure moves to manual fallback instead of crashing")
    func scanFailureFallsBackToManual() async {
        let container = try! TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .dinner,
            modelContext: container.mainContext,
            pipeline: MealScanPipeline(
                classificationService: FailingFoodClassificationService(),
                segmentationService: MockFoodSegmentationService(),
                portionEstimationService: MockPortionEstimationService(),
                nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)
            )
        )

        await viewModel.scanWithFallback(image: UIImage())

        #expect(viewModel.phase == .manualFallback)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.canAddManualFood)
    }

    @Test("remote scan failure keeps local Meal Scan V2 fallback available")
    func remoteScanFailureUsesLocalPipeline() async throws {
        let container = try TestHelpers.makeModelContainer()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: ThrowingRemoteMealScanEstimator(),
            resultCache: nil,
            imageNormalizer: ViewModelStubMealScanImageNormalizer(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: GeminiRemoteMealScanConfiguration(
                proxyEndpointURL: URL(string: "https://example.com/v1/meal-scans/estimate"),
                revenueCatAppUserID: "$RCAnonymousID:test"
            )
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: service
        )

        try await viewModel.scan(image: UIImage())

        #expect(viewModel.phase == .review)
        #expect(viewModel.lastScanResult?.modelVersion == "mock-food-fixtures")
        #expect(viewModel.draftItems.isEmpty == false)
    }

    @Test("remote quota errors show quota message instead of local mock estimate")
    func remoteQuotaErrorShowsManualFallbackWithoutLocalEstimate() async throws {
        let container = try TestHelpers.makeModelContainer()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: QuotaExceededRemoteMealScanEstimator(),
            resultCache: nil,
            imageNormalizer: ViewModelStubMealScanImageNormalizer(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: GeminiRemoteMealScanConfiguration(
                proxyEndpointURL: URL(string: "https://example.com/v1/meal-scans/estimate"),
                revenueCatAppUserID: "$RCAnonymousID:test"
            )
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: service
        )

        await viewModel.scanWithFallback(image: UIImage())

        #expect(viewModel.phase == .manualFallback)
        #expect(viewModel.errorMessage?.localizedCaseInsensitiveContains("photo estimate limit") == true)
        #expect(viewModel.lastScanResult == nil)
        #expect(viewModel.draftItems.isEmpty)
        #expect(viewModel.canAddManualFood)
    }
}

private struct FailingFoodClassificationService: FoodClassificationService {
    func classifyFood(in image: UIImage) async throws -> [FoodClassificationCandidate] {
        throw FoodLookupError.productNotFound
    }
}

@MainActor
private final class ThrowingRemoteMealScanEstimator: RemoteMealScanEstimating {
    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        throw URLError(.badServerResponse)
    }
}

@MainActor
private final class QuotaExceededRemoteMealScanEstimator: RemoteMealScanEstimating {
    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        throw GeminiMealScanProxyError(
            statusCode: 429,
            error: "daily_scan_quota_exceeded",
            reason: "trial_quota_exceeded",
            quota: RemoteMealScanQuota(
                accessTier: "trial",
                used: 25,
                limit: 5,
                softLimit: 5,
                remainingToday: 0,
                trialUsed: 25,
                trialLimit: 25,
                remainingTrial: 0
            ),
            retryable: nil
        )
    }
}

private struct ViewModelStubMealScanImageNormalizer: MealScanImageNormalizing {
    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        let data = Data("normalized-image".utf8)
        return NormalizedMealScanImage(
            jpegData: data,
            sourceImageHash: MealScanImageNormalizer.sha256Hex(data),
            width: 8,
            height: 8
        )
    }
}
