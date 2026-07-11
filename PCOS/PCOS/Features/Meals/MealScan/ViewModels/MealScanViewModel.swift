import Foundation
import SwiftData
import UIKit

@Observable
@MainActor
final class MealScanViewModel {
    enum Phase: Equatable {
        case entry
        case camera
        case processing
        case review
        case manualFallback
        case saved
    }

    private let modelContext: ModelContext
    private var pipeline: MealScanPipeline
    private let nutritionRepository: LocalFoodNutritionRepository
    private let calculator = MealNutritionCalculator()
    private let metabolicProfileService = MealMetabolicProfileService()
    private let featureFlags: MealScanFeatureFlags
    private let remoteMealScanService: GeminiRemoteMealScanService?

    var phase: Phase = .entry
    var mealType: MealType
    var mealName: String = "AI meal estimate"
    var draftItems: [MealFoodItemDraft] = []
    var totalNutrition = NutritionSnapshot()
    var metabolicProfile: MealMetabolicProfile?
    var confidence: NutritionConfidence = .unknown
    var warnings: [String] = []
    var errorMessage: String?
    var hiddenIngredientEstimate: HiddenIngredientEstimate = .no
    var hasUserEdits = false
    var selectedImage: UIImage?
    var selectedImageData: Data?
    var lastScanResult: MealScanResult?

    var canAddManualFood: Bool { true }

    init(
        mealType: MealType,
        modelContext: ModelContext,
        pipeline: MealScanPipeline? = nil,
        remoteMealScanService: GeminiRemoteMealScanService? = nil,
        featureFlags: MealScanFeatureFlags = .current
    ) {
        self.mealType = mealType
        self.modelContext = modelContext
        self.featureFlags = featureFlags
        self.nutritionRepository = LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)
        self.pipeline = pipeline ?? (featureFlags.enableMockMealScanData ? .mock() : .production(registry: MealScanModelRegistry(foodClassifierModelName: nil, foodSegmentationModelName: nil, depthModelName: nil, modelVersion: "unconfigured")))
        self.remoteMealScanService = remoteMealScanService ?? Self.makeRemoteMealScanService(
            modelContext: modelContext,
            nutritionRepository: nutritionRepository,
            calculator: calculator,
            featureFlags: featureFlags
        )
    }

    func startScan() {
        phase = .camera
    }

    func scanWithFallback(image: UIImage) async {
        do {
            try await scan(image: image)
        } catch {
            errorMessage = "No food was confidently detected. You can retake the photo or add the meal manually."
            phase = .manualFallback
        }
    }

    func scan(image: UIImage) async throws {
        selectedImage = image
        selectedImageData = image.jpegData(compressionQuality: 0.82)
        phase = .processing
        let result: MealScanResult
        if let remoteMealScanService {
            do {
                result = try await remoteMealScanService.scan(image: image, mealType: mealType)
            } catch let error as GeminiMealScanProxyError where error.shouldShowManualFallbackWithoutLocalEstimate {
                errorMessage = error.errorDescription
                phase = .manualFallback
                return
            } catch {
                result = try await pipeline.scan(image: image, mealType: mealType)
            }
        } else {
            result = try await pipeline.scan(image: image, mealType: mealType)
        }
        apply(result: result)
        phase = .review
    }

    func useMockPhoto() async {
        await scanWithFallback(image: UIImage())
    }

    func apply(result: MealScanResult) {
        lastScanResult = result
        mealName = result.mealName
        draftItems = result.detectedItems
        warnings = result.warnings
        confidence = result.confidence
        totalNutrition = result.nutrition
        metabolicProfile = result.metabolicProfile
    }

    func updateItem(id: UUID, mutate: (inout MealFoodItemDraft) -> Void) {
        guard let index = draftItems.firstIndex(where: { $0.id == id }) else { return }
        mutate(&draftItems[index])
        draftItems[index].wasUserEdited = true
        if let food = SampleNutritionFixtures.records.first(where: { $0.id == draftItems[index].canonicalFoodId }) {
            draftItems[index].nutrition = calculator.calculateItemNutrition(
                food: food,
                grams: draftItems[index].estimatedGrams
            )
        }
        hasUserEdits = true
        recalculate()
    }

    func replaceItem(_ item: MealFoodItemDraft) {
        if let index = draftItems.firstIndex(where: { $0.id == item.id }) {
            draftItems[index] = item
        } else {
            draftItems.append(item)
        }
        hasUserEdits = true
        recalculate()
    }

    func removeItem(id: UUID) {
        draftItems.removeAll { $0.id == id }
        hasUserEdits = true
        recalculate()
    }

    func addManualFood(named name: String = "Food", grams: Double = 100) {
        let food = SampleNutritionFixtures.records.first { $0.id == "rice-white-cooked" }
        let nutrition = food.map { calculator.calculateItemNutrition(food: $0, grams: grams) } ?? NutritionSnapshot()
        draftItems.append(
            MealFoodItemDraft(
                displayName: name,
                canonicalFoodId: food?.id ?? "manual-food",
                nutritionSource: food?.source ?? .userManual,
                estimatedGrams: grams,
                servingDescription: food?.servingDescription,
                nutrition: nutrition,
                confidence: .unknown,
                detectionSource: "manual",
                portionEstimationMethod: .manualUserInput,
                wasUserEdited: true
            )
        )
        hasUserEdits = true
        recalculate()
        phase = .review
    }

    func applyHiddenIngredientEstimate(_ estimate: HiddenIngredientEstimate) {
        hiddenIngredientEstimate = estimate
        draftItems.removeAll { $0.canonicalFoodId == "olive-oil" && $0.detectionSource == "hidden_ingredient_prompt" }

        if estimate.addedOilGrams > 0,
           let oil = SampleNutritionFixtures.records.first(where: { $0.id == "olive-oil" }) {
            let grams = estimate.addedOilGrams
            draftItems.append(
                MealFoodItemDraft(
                    displayName: "Olive oil estimate",
                    canonicalFoodId: oil.id,
                    nutritionSource: oil.source,
                    estimatedGrams: grams,
                    servingDescription: estimate.displayName,
                    nutrition: calculator.calculateItemNutrition(food: oil, grams: grams),
                    confidence: estimate == .notSure ? .low : .medium,
                    warning: "Added from hidden oil, butter, dressing, or sauce prompt.",
                    detectionSource: "hidden_ingredient_prompt",
                    portionEstimationMethod: .servingSizeHeuristic,
                    wasUserEdited: true
                )
            )
        }

        hasUserEdits = true
        recalculate()
    }

    func searchFoods(query: String) async -> [FoodNutritionRecord] {
        (try? await nutritionRepository.searchFood(query: query)) ?? []
    }

    func draftItem(for food: FoodNutritionRecord, grams: Double, existingID: UUID? = nil) -> MealFoodItemDraft {
        MealFoodItemDraft(
            id: existingID ?? UUID(),
            displayName: food.displayName,
            canonicalFoodId: food.id,
            nutritionSource: food.source,
            estimatedGrams: grams,
            servingDescription: food.servingDescription,
            nutrition: calculator.calculateItemNutrition(food: food, grams: grams),
            confidence: .medium,
            detectionSource: existingID == nil ? "manual" : "user_edit",
            portionEstimationMethod: .manualUserInput,
            wasUserEdited: true
        )
    }

    func confirmedMeal() -> ConfirmedMealScan {
        let result = currentResult()
        return ConfirmedMealScan(
            id: result.id,
            scanResult: result,
            mealType: mealType,
            userConfirmed: true,
            hasUserEdits: hasUserEdits,
            finalUserConfirmedJSON: MealScanJSON.encodeOriginal(
                mealName: mealName,
                items: draftItems,
                nutrition: totalNutrition,
                confidence: confidence,
                warnings: warnings
            ),
            photoData: selectedImageData
        )
    }

    func save() async throws {
        try await SwiftDataMealLogRepository(modelContext: modelContext).saveMealScan(confirmedMeal())
        phase = .saved
    }

    func retake() {
        selectedImage = nil
        selectedImageData = nil
        errorMessage = nil
        phase = .camera
    }

    private func recalculate() {
        totalNutrition = calculator.aggregateMealNutrition(items: draftItems)
        let itemConfidence = MealScanConfidenceScorer.aggregate(draftItems.map(\.confidence))
        confidence = MealScanConfidenceScorer.adjustedConfidence(
            base: itemConfidence,
            hiddenIngredientEstimate: hiddenIngredientEstimate,
            isMixedDish: draftItems.contains(where: \.isMixedDish),
            wasUserEdited: hasUserEdits
        )
        metabolicProfile = metabolicProfileService.profile(
            for: totalNutrition,
            confidence: confidence,
            hiddenIngredientEstimate: hiddenIngredientEstimate,
            visibleWarnings: warnings
        )
        lastScanResult = currentResult()
    }

    private func currentResult() -> MealScanResult {
        let profile = metabolicProfile ?? metabolicProfileService.profile(
            for: totalNutrition,
            confidence: confidence,
            hiddenIngredientEstimate: hiddenIngredientEstimate,
            visibleWarnings: warnings
        )
        return MealScanResult(
            id: lastScanResult?.id ?? UUID(),
            mealName: mealName,
            mealType: mealType,
            detectedItems: draftItems,
            nutrition: totalNutrition,
            metabolicProfile: profile,
            confidence: confidence,
            warnings: warnings,
            originalPredictionJSON: lastScanResult?.originalPredictionJSON ?? "{}",
            modelVersion: lastScanResult?.modelVersion ?? "manual",
            pipelineVersion: lastScanResult?.pipelineVersion ?? MealScanPipeline.pipelineVersion
        )
    }

    private static func makeRemoteMealScanService(
        modelContext: ModelContext,
        nutritionRepository: LocalFoodNutritionRepository,
        calculator: MealNutritionCalculator,
        featureFlags: MealScanFeatureFlags
    ) -> GeminiRemoteMealScanService? {
        guard featureFlags.enableGeminiMealScan,
              let configuration = GeminiRemoteMealScanConfiguration.from(
                revenueCatAppUserID: SubscriptionManager.shared.revenueCatAppUserID
              ),
              let endpointURL = configuration.proxyEndpointURL
        else {
            return nil
        }

        return GeminiRemoteMealScanService(
            remoteEstimator: GeminiMealScanProxyClient(endpointURL: endpointURL),
            resultCache: featureFlags.enableMealScanResultCache ? MealScanResultCache(modelContext: modelContext) : nil,
            imageNormalizer: MealScanImageNormalizer(),
            nutritionLookupService: nutritionRepository,
            calculator: calculator,
            configuration: configuration,
            appCheckTokenProvider: FirebaseMealScanAppCheckTokenProvider()
        )
    }
}

private extension GeminiMealScanProxyError {
    var shouldShowManualFallbackWithoutLocalEstimate: Bool {
        switch error {
        case "daily_scan_quota_exceeded", "premium_entitlement_required", "app_integrity_required":
            true
        default:
            false
        }
    }
}
