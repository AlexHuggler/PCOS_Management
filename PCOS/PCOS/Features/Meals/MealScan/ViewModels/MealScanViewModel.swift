import Foundation
import os
import SwiftData
import UIKit

@Observable
@MainActor
final class MealScanViewModel {
    enum Phase: Equatable {
        case entry
        case camera
        case processing
        case repeatSuggestion
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
    private let remoteMealScanService: (any RemoteMealScanServing)?
    private let imageNormalizer: any MealScanImageNormalizing
    private let repeatMealFingerprinter: any MealImageFingerprinting
    private let repeatMealCache: (any MealScanRepeatCaching)?
    private let mealLogRepository: any MealLogRepository
    private var pendingNormalizedImage: NormalizedMealScanImage?
    private var pendingFingerprint: MealImageFingerprint?
    private var repeatSourceRecordID: UUID?

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
    var repeatMealSuggestion: RepeatMealSuggestion?

    var canAddManualFood: Bool { true }

    init(
        mealType: MealType,
        modelContext: ModelContext,
        pipeline: MealScanPipeline? = nil,
        remoteMealScanService: (any RemoteMealScanServing)? = nil,
        featureFlags: MealScanFeatureFlags = .current,
        imageNormalizer: any MealScanImageNormalizing = MealScanImageNormalizer(),
        repeatMealFingerprinter: any MealImageFingerprinting = VisionRepeatMealImageFingerprinter(),
        repeatMealCache: (any MealScanRepeatCaching)? = nil,
        mealLogRepository: (any MealLogRepository)? = nil
    ) {
        self.mealType = mealType
        self.modelContext = modelContext
        self.featureFlags = featureFlags
        self.nutritionRepository = LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)
        self.pipeline = pipeline ?? (featureFlags.enableMockMealScanData ? .mock() : .production(registry: MealScanModelRegistry(foodClassifierModelName: nil, foodSegmentationModelName: nil, depthModelName: nil, modelVersion: "unconfigured")))
        self.imageNormalizer = imageNormalizer
        self.repeatMealFingerprinter = repeatMealFingerprinter
        self.mealLogRepository = mealLogRepository ?? SwiftDataMealLogRepository(modelContext: modelContext)
        self.remoteMealScanService = remoteMealScanService ?? Self.makeRemoteMealScanService(
            modelContext: modelContext,
            nutritionRepository: nutritionRepository,
            calculator: calculator,
            featureFlags: featureFlags
        )
        if let repeatMealCache {
            self.repeatMealCache = repeatMealCache
        } else if featureFlags.enableRepeatMealSuggestions {
            self.repeatMealCache = MealScanRepeatCache(
                modelContext: modelContext,
                fingerprinter: repeatMealFingerprinter,
                similarityPolicy: featureFlags.enableSimilarMealSuggestions
                    ? MealRepeatSimilarityPolicy.loadApproved()
                    : .disabled
            )
        } else {
            self.repeatMealCache = nil
        }
    }

    func startScan() {
        phase = .camera
    }

    func scanWithFallback(image: UIImage) async {
        do {
            try await prepareSelectedImage(image)
        } catch {
            errorMessage = "No food was confidently detected. You can retake the photo or add the meal manually."
            phase = .manualFallback
        }
    }

    func scan(image: UIImage) async throws {
        try await prepareSelectedImage(image)
    }

    func prepareSelectedImage(_ image: UIImage) async throws {
        selectedImage = image
        errorMessage = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        phase = .processing
        let normalizedImage = try imageNormalizer.normalizeJPEGData(from: image)
        pendingNormalizedImage = normalizedImage
        selectedImageData = normalizedImage.jpegData
        pendingFingerprint = nil

        if featureFlags.enableRepeatMealSuggestions,
           let repeatMealCache {
            do {
                let fingerprint = try await repeatMealFingerprinter.makeFingerprint(
                    for: normalizedImage.jpegData
                )
                pendingFingerprint = fingerprint
                if let suggestion = await repeatMealCache.suggestion(
                    for: fingerprint,
                    now: Date()
                ) {
                    repeatMealSuggestion = suggestion
                    phase = .repeatSuggestion
                    return
                }
            } catch {
                Logger.meals.error("Repeat meal fingerprinting failed; continuing with a fresh scan.")
            }
        }

        try await scanPendingImageAsNew()
    }

    func usePreviousMeal() {
        guard let suggestion = repeatMealSuggestion else { return }
        let snapshot = suggestion.snapshot
        let reusedItems = snapshot.makeDraftItemsForReuse()
        let profile = metabolicProfileService.profile(
            for: snapshot.nutrition,
            confidence: snapshot.confidence,
            hiddenIngredientEstimate: snapshot.hiddenIngredientEstimate,
            visibleWarnings: snapshot.warnings
        )
        let result = MealScanResult(
            id: UUID(),
            mealName: snapshot.mealName,
            mealType: snapshot.mealType,
            detectedItems: reusedItems,
            nutrition: snapshot.nutrition,
            metabolicProfile: profile,
            confidence: snapshot.confidence,
            warnings: snapshot.warnings,
            originalPredictionJSON: MealScanJSON.encodeOriginal(
                mealName: snapshot.mealName,
                items: reusedItems,
                nutrition: snapshot.nutrition,
                confidence: snapshot.confidence,
                warnings: snapshot.warnings
            ),
            modelVersion: snapshot.source.modelVersion,
            pipelineVersion: snapshot.source.pipelineVersion
        )

        mealType = snapshot.mealType
        hiddenIngredientEstimate = snapshot.hiddenIngredientEstimate
        hasUserEdits = false
        repeatSourceRecordID = suggestion.recordID
        apply(result: result)
        do {
            try repeatMealCache?.markReused(recordID: suggestion.recordID, now: Date())
        } catch {
            Logger.meals.error("Repeat meal usage update failed; continuing with reviewed nutrition.")
        }
        repeatMealSuggestion = nil
        phase = .review
    }

    func scanPendingImageAsNew() async throws {
        guard let image = selectedImage,
              let normalizedImage = pendingNormalizedImage else {
            throw MealScanViewModelError.missingPendingImage
        }

        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        phase = .processing
        let result: MealScanResult
        if let remoteMealScanService {
            do {
                result = try await remoteMealScanService.scan(
                    normalizedImage: normalizedImage,
                    mealType: mealType
                )
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
            photoData: selectedImageData,
            repeatSourceRecordID: repeatSourceRecordID
        )
    }

    func save() async throws {
        let confirmedMeal = confirmedMeal()
        try await mealLogRepository.saveMealScan(confirmedMeal)

        if featureFlags.enableRepeatMealSuggestions,
           let repeatMealCache,
           let pendingFingerprint {
            let result = confirmedMeal.scanResult
            let snapshot = RepeatMealDraftSnapshot(
                mealName: result.mealName,
                mealType: result.mealType,
                items: result.detectedItems,
                nutrition: result.nutrition,
                confidence: result.confidence,
                warnings: result.warnings,
                hiddenIngredientEstimate: hiddenIngredientEstimate,
                source: RepeatMealSourceMetadata(
                    modelVersion: result.modelVersion,
                    pipelineVersion: result.pipelineVersion
                )
            )
            do {
                try repeatMealCache.save(
                    snapshot: snapshot,
                    sourceMealID: confirmedMeal.id,
                    sourceMealLoggedAt: confirmedMeal.loggedAt,
                    fingerprint: pendingFingerprint,
                    now: Date()
                )
            } catch {
                Logger.meals.error("Repeat meal cache save failed; reviewed meal remains saved.")
            }
        }
        phase = .saved
    }

    func retake() {
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingFingerprint = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
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
    ) -> (any RemoteMealScanServing)? {
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

private enum MealScanViewModelError: Error {
    case missingPendingImage
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
