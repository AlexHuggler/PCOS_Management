import Foundation
import os
import SwiftData
import UIKit

@Observable
@MainActor
final class MealScanViewModel {
    enum Phase: Equatable {
        case photoChoice
        case processing
        case repeatSuggestion
        case remoteConsent
        case failure
        case review
        case saved
    }

    enum ProcessingStage: Equatable {
        case preparingPhoto
        case checkingPreviousEstimate
        case estimatingFoodsAndPortions
    }

    private let modelContext: ModelContext
    private var pipeline: MealScanPipeline
    private let nutritionRepository: LocalFoodNutritionRepository
    private let calculator = MealNutritionCalculator()
    private let metabolicProfileService = MealMetabolicProfileService()
    private let featureFlags: MealScanFeatureFlags
    private let initialMealType: MealType
    private let remoteMealScanService: (any RemoteMealScanServing)?
    private let imageNormalizer: any MealScanImageNormalizing
    private let repeatMealFingerprinter: any MealImageFingerprinting
    private let repeatMealCache: (any MealScanRepeatCaching)?
    private let mealLogRepository: any MealLogRepository
    private var pendingNormalizedImage: NormalizedMealScanImage?
    private var pendingFingerprint: MealImageFingerprint?
    private var repeatSourceRecordID: UUID?
    private(set) var pendingRequestID: UUID?
    private var consentedRequestID: UUID?
    private var pendingRequestConsumption: MealScanConsumptionState = .notUsed
    private var unknownRetryCount = 0
    private var sameRequestRecheckCount = 0
    private var pendingRetryAvailableAt: Date?
    private(set) var pendingRetryAfterSeconds: Int?
    private(set) var isRequestPending = false
    private var pendingPhotoRetryEligible = false
    private var pendingPhotoRetryAvailableAt: Date?

    var phase: Phase = .photoChoice
    private(set) var processingStage: ProcessingStage = .preparingPhoto
    var mealType: MealType
    var mealName: String = L10n.string("Photo meal estimate", defaultValue: "Photo meal estimate")
    var draftItems: [MealFoodItemDraft] = []
    var totalNutrition = NutritionSnapshot()
    var metabolicProfile: MealMetabolicProfile?
    var confidence: NutritionConfidence = .unknown
    var warnings: [String] = []
    private(set) var failure: MealScanFailure?
    private(set) var failureOccurrence = 0
    private(set) var analysisSource: MealScanAnalysisSource?
    var scanConsumption: MealScanConsumptionState {
        failure?.consumption ?? analysisSource?.consumption ?? .notUsed
    }
    private(set) var isShowingNewAnalysisConfirmation = false
    var hiddenIngredientEstimate: HiddenIngredientEstimate = .no
    var hasUserEdits = false
    var selectedImage: UIImage?
    var selectedImageData: Data?
    var lastScanResult: MealScanResult?
    var repeatMealSuggestion: RepeatMealSuggestion?
    private(set) var mealScanQuota: MealScanQuota?
    var mealScanCacheDisposition: MealScanCacheDisposition? {
        analysisSource.map { source in
            switch source {
            case .exactPrevious, .localCache: .local
            case .serverCache: .server
            case .fresh: .fresh
            }
        }
    }
    private(set) var savedMealID: UUID?

    var canAddManualFood: Bool { true }
    var saveValidationMessage: String? {
        guard !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return L10n.string(
                "Enter a meal name before saving.",
                defaultValue: "Enter a meal name before saving."
            )
        }
        guard !draftItems.isEmpty else {
            return L10n.string(
                "Add at least one food before saving.",
                defaultValue: "Add at least one food before saving."
            )
        }
        guard draftItems.allSatisfy({ $0.estimatedGrams.isFinite && $0.estimatedGrams > 0 }) else {
            return L10n.string(
                "Each food needs a portion greater than zero.",
                defaultValue: "Each food needs a portion greater than zero."
            )
        }
        return nil
    }
    var canSaveMeal: Bool { saveValidationMessage == nil }
    var canStartFreshAnalysis: Bool { mealScanQuota?.remaining != 0 }
    var canRetryAmbiguousOutcome: Bool {
        canRetryAmbiguousOutcome(at: Date())
    }
    func canRetryAmbiguousOutcome(at now: Date) -> Bool {
        guard phase == .failure,
              failure?.retryBehavior == .checkSameRequest,
              sameRequestRecheckCount < 2,
              isRequestPending || unknownRetryCount < 1 else {
            return false
        }
        return pendingRetryAvailableAt.map { now >= $0 } ?? true
    }
    var pendingRetryAvailableAtLocalText: String? {
        pendingRetryAvailableAt?.formatted(date: .omitted, time: .shortened)
    }
    func pendingRetryRemainingSeconds(at now: Date) -> Int? {
        Self.remainingSeconds(until: pendingRetryAvailableAt, at: now)
    }
    var hasRetryablePendingPhoto: Bool {
        phase == .failure
            && failure?.retryBehavior == .retrySameRequest
            && pendingPhotoRetryEligible
            && pendingNormalizedImage != nil
            && pendingRequestID != nil
    }
    var canRetryPendingPhoto: Bool {
        canRetryPendingPhoto(at: Date())
    }
    func canRetryPendingPhoto(at now: Date) -> Bool {
        guard hasRetryablePendingPhoto else { return false }
        return pendingPhotoRetryAvailableAt.map { now >= $0 } ?? true
    }
    var pendingPhotoRetryAvailableAtLocalText: String? {
        pendingPhotoRetryAvailableAt?.formatted(date: .omitted, time: .shortened)
    }
    func pendingPhotoRetryRemainingSeconds(at now: Date) -> Int? {
        Self.remainingSeconds(until: pendingPhotoRetryAvailableAt, at: now)
    }
    var shouldWarnAboutRemainingAnalyses: Bool {
        mealScanCacheDisposition == .fresh && (mealScanQuota?.remaining ?? .max) <= 2
    }
    var quotaResetAtLocalText: String? {
        guard let resetAt = mealScanQuota?.resetAt,
              let date = Self.parseISO8601(resetAt)
        else {
            return nil
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    init(
        mealType: MealType,
        modelContext: ModelContext,
        pipeline: MealScanPipeline? = nil,
        remoteMealScanService: (any RemoteMealScanServing)? = nil,
        featureFlags: MealScanFeatureFlags = .current,
        imageNormalizer: any MealScanImageNormalizing = MealScanImageNormalizer(),
        repeatMealFingerprinter: (any MealImageFingerprinting)? = nil,
        repeatMealCache: (any MealScanRepeatCaching)? = nil,
        mealLogRepository: (any MealLogRepository)? = nil
    ) {
        self.mealType = mealType
        self.initialMealType = mealType
        self.modelContext = modelContext
        self.featureFlags = featureFlags
        self.nutritionRepository = LocalFoodNutritionRepository(records: SampleNutritionFixtures.records)
        self.pipeline = pipeline ?? (featureFlags.enableMockMealScanData ? .mock() : .production(registry: MealScanModelRegistry(foodClassifierModelName: nil, foodSegmentationModelName: nil, depthModelName: nil, modelVersion: "unconfigured")))
        self.imageNormalizer = imageNormalizer
        let resolvedRepeatMealFingerprinter = repeatMealFingerprinter ?? Self.makeRepeatMealFingerprinter()
        self.repeatMealFingerprinter = resolvedRepeatMealFingerprinter
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
                fingerprinter: resolvedRepeatMealFingerprinter,
                similarityPolicy: featureFlags.enableSimilarMealSuggestions
                    ? MealRepeatSimilarityPolicy.loadApproved()
                    : .disabled
            )
        } else {
            self.repeatMealCache = nil
        }

        #if DEBUG
        applyUITestPhaseFixtureIfNeeded(arguments: ProcessInfo.processInfo.arguments)
        #endif
    }

    func startScan() {
        phase = .photoChoice
    }

    func scanWithFallback(image: UIImage) async {
        do {
            try await prepareSelectedImage(image)
        } catch {
            rejectUnreadableSelectedPhoto()
        }
    }

    func rejectUnreadableSelectedPhoto() {
        resetAnalysisContent()
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingRequestID = nil
        resetPendingRequestTruth()
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
        applyFailure(MealScanFailure(
            kind: .unreadableMeal,
            cause: .invalidImage,
            consumption: .notUsed,
            retryBehavior: .none
        ))
        phase = .failure
    }

    func scan(image: UIImage) async throws {
        try await prepareSelectedImage(image)
    }

    func prepareSelectedImage(_ image: UIImage) async throws {
        savedMealID = nil
        resetAnalysisContent()
        pendingNormalizedImage = nil
        pendingRequestID = nil
        pendingFingerprint = nil
        resetPendingRequestTruth()
        selectedImage = image
        selectedImageData = nil
        failure = nil
        analysisSource = nil
        mealScanQuota = nil
        isShowingNewAnalysisConfirmation = false
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        processingStage = .preparingPhoto
        phase = .processing
        let normalizedImage = try imageNormalizer.normalizeJPEGData(from: image)
        pendingNormalizedImage = normalizedImage
        pendingRequestID = UUID()
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
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
                    if suggestion.matchKind == .exactImage {
                        usePreviousMeal()
                        return
                    }
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
        analysisSource = .exactPrevious
        pendingRequestConsumption = MealScanAnalysisSource.exactPrevious.consumption
        failure = nil
        do {
            try repeatMealCache?.markReused(recordID: suggestion.recordID, now: Date())
        } catch {
            Logger.meals.error("Repeat meal usage update failed; continuing with reviewed nutrition.")
        }
        repeatMealSuggestion = nil
        phase = .review
    }

    func scanPendingImageAsNew() async throws {
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        failure = nil
        phase = .processing
        resetPendingPhotoRetryState()

        processingStage = .checkingPreviousEstimate
        if let remoteMealScanService,
           let normalizedImage = pendingNormalizedImage {
            do {
                if let cachedOutcome = try await remoteMealScanService.cachedOutcome(
                    normalizedImage: normalizedImage,
                    mealType: mealType
                ) {
                    analysisSource = cachedOutcome.source
                    pendingRequestConsumption = cachedOutcome.source.consumption
                    mealScanQuota = cachedOutcome.quota
                    failure = nil
                    apply(result: cachedOutcome.result)
                    phase = .review
                    return
                }
            } catch let error as any MealScanFailureProviding {
                applyFailure(error.mealScanFailure)
                phase = .failure
                return
            } catch {
                if error is CancellationError { throw error }
                applyFailure(MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .unclassified,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                ))
                phase = .failure
                return
            }

            phase = .remoteConsent
            return
        }

        try await performPendingImageScan()
    }

    func confirmRemotePhotoEstimate() async throws {
        #if DEBUG
        if Self.uiTestFixture(in: ProcessInfo.processInfo.arguments) == "freshFlow" {
            consentedRequestID = pendingRequestID
            seedUITestReview(consumption: .used, cacheDisposition: .fresh)
            return
        }
        #endif

        guard phase == .remoteConsent,
              remoteMealScanService != nil else {
            throw MealScanViewModelError.remoteConsentRequired
        }

        consentedRequestID = pendingRequestID
        try await performPendingImageScan()
    }

    func retryAmbiguousOutcome() async throws {
        guard canRetryAmbiguousOutcome,
              pendingRequestID != nil else {
            throw MealScanViewModelError.ambiguousOutcomeRequired
        }
        let startedFromUnknown = !isRequestPending
        sameRequestRecheckCount += 1
        if startedFromUnknown {
            unknownRetryCount += 1
        }
        pendingRetryAfterSeconds = nil
        pendingRetryAvailableAt = nil
        try await performPendingImageScan(startedFromUnknownRecheck: startedFromUnknown)
    }

    func retryPendingPhoto() async throws {
        guard canRetryPendingPhoto else {
            throw MealScanViewModelError.retryablePhotoRequired
        }
        if consentedRequestID == pendingRequestID {
            try await performPendingImageScan()
        } else {
            try await scanPendingImageAsNew()
        }
    }

    func requestNewAnalysisAfterAmbiguousOutcome() {
        guard phase == .failure,
              failure?.retryBehavior == .checkSameRequest,
              canStartFreshAnalysis else { return }
        isShowingNewAnalysisConfirmation = true
    }

    func cancelNewAnalysisConfirmation() {
        isShowingNewAnalysisConfirmation = false
    }

    func confirmNewAnalysisAfterAmbiguousOutcome() async throws {
        guard phase == .failure,
              isShowingNewAnalysisConfirmation,
              pendingNormalizedImage != nil,
              canStartFreshAnalysis else {
            throw MealScanViewModelError.newAttemptConfirmationRequired
        }
        isShowingNewAnalysisConfirmation = false
        pendingRequestID = UUID()
        resetPendingRequestTruth()
        consentedRequestID = pendingRequestID
        resetAmbiguousRequestState()
        try await performPendingImageScan()
    }

    func continueWithManualEntry() {
        resetAnalysisContent()
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingRequestID = nil
        resetPendingRequestTruth()
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
        pendingFingerprint = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        failure = nil
        analysisSource = nil
        mealScanQuota = nil
        isShowingNewAnalysisConfirmation = false
        addManualFood(named: L10n.string("Manual food", defaultValue: "Manual food"))
    }

    private func performPendingImageScan(startedFromUnknownRecheck: Bool = false) async throws {
        guard let normalizedImage = pendingNormalizedImage else {
            throw MealScanViewModelError.missingPendingImage
        }

        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        failure = nil
        isShowingNewAnalysisConfirmation = false
        processingStage = remoteMealScanService == nil ? .preparingPhoto : .estimatingFoodsAndPortions
        phase = .processing
        resetPendingPhotoRetryState()
        let result: MealScanResult
        if let remoteMealScanService {
            guard let requestID = pendingRequestID else {
                throw MealScanViewModelError.missingRequestID
            }
            do {
                let outcome = try await remoteMealScanService.scan(
                    normalizedImage: normalizedImage,
                    mealType: mealType,
                    requestID: requestID
                )
                result = outcome.result
                mealScanQuota = outcome.quota ?? mealScanQuota
                analysisSource = outcome.source
                pendingRequestConsumption = outcome.source.consumption
                resetAmbiguousRequestState()
            } catch let error as MealScanRemoteError {
                applyFailure(error.mealScanFailure)
                switch error {
                case .outcomeUnknown(let unknownRequestID):
                    pendingRequestID = unknownRequestID
                    isRequestPending = false
                    pendingRetryAfterSeconds = nil
                    pendingRetryAvailableAt = nil
                case .providerTimeoutAfterDispatch(let requestID, let retryAfterSeconds),
                     .serverOutcomeUnknown(let requestID, let retryAfterSeconds),
                     .providerDispatchOutcomeUnknown(let requestID, let retryAfterSeconds):
                    pendingRequestID = requestID
                    isRequestPending = false
                    pendingRetryAfterSeconds = retryAfterSeconds
                    pendingRetryAvailableAt = retryAfterSeconds.map {
                        Date().addingTimeInterval(TimeInterval($0))
                    }
                case .requestPending(let pendingRequestID, let retryAfterSeconds):
                    self.pendingRequestID = pendingRequestID
                    isRequestPending = true
                    pendingRetryAfterSeconds = retryAfterSeconds
                    pendingRetryAvailableAt = retryAfterSeconds.map {
                        Date().addingTimeInterval(TimeInterval($0))
                    }
                    if startedFromUnknownRecheck {
                        unknownRetryCount = max(0, unknownRetryCount - 1)
                    }
                case .principalDispatchInProgress(let pendingRequestID, _):
                    self.pendingRequestID = pendingRequestID
                    isRequestPending = false
                default:
                    break
                }
                phase = .failure
                return
            } catch let error as GeminiMealScanProxyError {
                mealScanQuota = error.quota ?? mealScanQuota
                applyFailure(error.mealScanFailure)
                phase = .failure
                return
            } catch let error as any MealScanFailureProviding {
                applyFailure(error.mealScanFailure)
                phase = .failure
                return
            } catch {
                applyFailure(
                    MealScanFailure(
                        kind: .ambiguousResult,
                        consumption: .unknown,
                        retryBehavior: .checkSameRequest
                    )
                )
                phase = .failure
                return
            }
        } else if featureFlags.enableMockMealScanData,
                  let image = selectedImage {
            result = try await pipeline.scan(image: image, mealType: mealType)
            mealScanQuota = nil
            analysisSource = .localCache
            pendingRequestConsumption = MealScanAnalysisSource.localCache.consumption
        } else {
            applyFailure(
                MealScanFailure(
                    kind: .serviceDisabled,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            )
            phase = .failure
            return
        }
        failure = nil
        apply(result: result)
        phase = .review
    }

    func useMockPhoto() async {
        #if DEBUG
        if Self.uiTestFixture(in: ProcessInfo.processInfo.arguments) == "freshFlow" {
            seedUITestPhoto()
            pendingRequestID = UUID(uuidString: "A8A72F4E-96C3-494F-B9BD-111D8D3B6AA8")
            failure = nil
            analysisSource = nil
            phase = .remoteConsent
            return
        }

        guard let sampleImage = UIImage(named: "botanical-meal-bowl") else {
            applyFailure(
                MealScanFailure(
                    kind: .serviceDisabled,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            )
            phase = .failure
            return
        }
        await scanWithFallback(image: sampleImage)
        #else
        applyFailure(
            MealScanFailure(
                kind: .serviceDisabled,
                consumption: .notUsed,
                retryBehavior: .none
            )
        )
        phase = .failure
        #endif
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
        let previousEstimatedGrams = draftItems[index].estimatedGrams
        let previousNutrition = draftItems[index].nutrition
        mutate(&draftItems[index])
        draftItems[index].recordUserEdit(previousEstimatedGrams: previousEstimatedGrams)
        if let food = SampleNutritionFixtures.records.first(where: { $0.id == draftItems[index].canonicalFoodId }) {
            draftItems[index].nutrition = calculator.calculateItemNutrition(
                food: food,
                grams: draftItems[index].estimatedGrams
            )
        } else if previousEstimatedGrams.isFinite,
                  previousEstimatedGrams > 0,
                  draftItems[index].estimatedGrams.isFinite,
                  draftItems[index].estimatedGrams >= 0 {
            draftItems[index].nutrition = previousNutrition.scaled(
                by: draftItems[index].estimatedGrams / previousEstimatedGrams
            )
        }
        hasUserEdits = true
        recalculate()
    }

    func adjustPortion(id: UUID, byGrams delta: Double) {
        updateItem(id: id) { item in
            item.estimatedGrams = max(1, item.estimatedGrams + delta)
        }
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

    func newManualFoodDraft() -> MealFoodItemDraft {
        MealFoodItemDraft(
            displayName: "",
            canonicalFoodId: "manual-food",
            nutritionSource: .userManual,
            estimatedGrams: 0,
            servingDescription: nil,
            nutrition: NutritionSnapshot(),
            confidence: .unknown,
            detectionSource: "manual",
            portionEstimationMethod: .manualUserInput,
            wasUserEdited: true
        )
    }

    func appendItem(_ item: MealFoodItemDraft) {
        guard !item.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.estimatedGrams.isFinite,
              item.estimatedGrams > 0 else { return }
        draftItems.append(item)
        hasUserEdits = true
        recalculate()
    }

    func removeItem(id: UUID) {
        draftItems.removeAll { $0.id == id }
        hasUserEdits = true
        recalculate()
    }

    func addManualFood(named name: String? = nil, grams: Double = 0) {
        let resolvedName = name ?? L10n.string("Food", defaultValue: "Food")
        draftItems.append(
            MealFoodItemDraft(
                displayName: resolvedName,
                canonicalFoodId: "manual-food",
                nutritionSource: .userManual,
                estimatedGrams: grams,
                servingDescription: nil,
                nutrition: NutritionSnapshot(),
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
                    displayName: L10n.string("Olive oil estimate", defaultValue: "Olive oil estimate"),
                    canonicalFoodId: oil.id,
                    nutritionSource: oil.source,
                    estimatedGrams: grams,
                    servingDescription: estimate.displayName,
                    nutrition: calculator.calculateItemNutrition(food: oil, grams: grams),
                    confidence: estimate == .notSure ? .low : .medium,
                    warning: L10n.string("Added from hidden oil, butter, dressing, or sauce prompt.", defaultValue: "Added from hidden oil, butter, dressing, or sauce prompt."),
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
        guard canSaveMeal else {
            phase = .review
            throw MealScanViewModelError.invalidSave
        }
        let confirmedMeal = confirmedMeal()
        do {
            try await mealLogRepository.saveMealScan(confirmedMeal)
        } catch {
            let inheritedConsumption = scanConsumption
            applyFailure(MealScanFailure(
                kind: .saveFailed,
                cause: .saveFailed,
                consumption: inheritedConsumption,
                retryBehavior: .retrySave
            ))
            phase = .review
            throw error
        }
        failure = nil
        savedMealID = confirmedMeal.id

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

    func savedMealContextDraft() throws -> SavedMealContextDraft {
        let meal = try savedMealEntry()
        return SavedMealContextDraft(
            mealID: meal.id,
            mealName: meal.mealDescription,
            severity: meal.postMealSymptomSeverity ?? 0,
            note: meal.postMealSymptomNote ?? ""
        )
    }

    func savedMealGlucosePrefillContext() throws -> GlucosePrefillContext {
        let meal = try savedMealEntry()
        return GlucosePrefillContext(
            mealContext: L10n.format(
                "After %@",
                defaultValue: "After %@",
                meal.mealDescription
            ),
            readingType: .afterMeal,
            readingDate: Date()
        )
    }

    func updateSavedMealContext(severity: Int, note: String) throws {
        let meal = try savedMealEntry()
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSeverity = (1...5).contains(severity) ? severity : nil
        meal.postMealSymptomSeverity = normalizedSeverity
        meal.postMealSymptomNote = trimmedNote.isEmpty ? nil : trimmedNote
        meal.postMealFeedbackTimestamp = normalizedSeverity != nil || !trimmedNote.isEmpty
            ? Date()
            : nil
        meal.updatedAt = Date()
        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
    }

    private func savedMealEntry() throws -> MealEntry {
        guard let targetMealID = savedMealID else {
            throw MealScanViewModelError.missingSavedMealIdentity
        }
        let descriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate<MealEntry> { entry in
                entry.id == targetMealID
            }
        )
        guard let meal = try modelContext.fetch(descriptor).first else {
            throw MealScanViewModelError.savedMealNotFound
        }
        return meal
    }

    func retake() {
        savedMealID = nil
        resetAnalysisContent()
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingRequestID = nil
        resetPendingRequestTruth()
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
        pendingFingerprint = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        failure = nil
        analysisSource = nil
        mealScanQuota = nil
        isShowingNewAnalysisConfirmation = false
        phase = .photoChoice
    }

    private func applyFailure(_ failure: MealScanFailure) {
        var resolvedFailure = failure
        if pendingRequestID != nil || failure.kind == .saveFailed {
            pendingRequestConsumption = pendingRequestConsumption.preservingStrongestTruth(
                with: failure.consumption
            )
            resolvedFailure.consumption = pendingRequestConsumption
        }
        self.failure = resolvedFailure
        failureOccurrence &+= 1
        if resolvedFailure.kind != .saveFailed {
            analysisSource = nil
        }
        mealScanQuota = resolvedFailure.quota ?? mealScanQuota
        pendingRetryAfterSeconds = resolvedFailure.retryAfterSeconds
        pendingRetryAvailableAt = nil
        pendingPhotoRetryAvailableAt = nil
        pendingPhotoRetryEligible = false
        let availableAt = resolvedFailure.retryAfterSeconds.map {
            Date().addingTimeInterval(TimeInterval($0))
        }
        switch resolvedFailure.retryBehavior {
        case .retrySameRequest:
            pendingPhotoRetryEligible = pendingNormalizedImage != nil && pendingRequestID != nil
            pendingPhotoRetryAvailableAt = availableAt
        case .checkSameRequest:
            pendingRetryAvailableAt = availableAt
        case .none, .retrySave:
            break
        }
    }

    private func resetAmbiguousRequestState() {
        unknownRetryCount = 0
        sameRequestRecheckCount = 0
        pendingRetryAfterSeconds = nil
        pendingRetryAvailableAt = nil
        isRequestPending = false
    }

    private func resetPendingPhotoRetryState() {
        pendingPhotoRetryEligible = false
        pendingPhotoRetryAvailableAt = nil
    }

    private func resetPendingRequestTruth() {
        consentedRequestID = nil
        pendingRequestConsumption = .notUsed
    }

    private func resetAnalysisContent() {
        mealType = initialMealType
        mealName = L10n.string("Photo meal estimate", defaultValue: "Photo meal estimate")
        draftItems = []
        totalNutrition = NutritionSnapshot()
        metabolicProfile = nil
        confidence = .unknown
        warnings = []
        hiddenIngredientEstimate = .no
        hasUserEdits = false
        lastScanResult = nil
    }

    private static func remainingSeconds(until availableAt: Date?, at now: Date) -> Int? {
        guard let availableAt else { return nil }
        return max(0, Int(ceil(availableAt.timeIntervalSince(now))))
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
              let configuration = GeminiRemoteMealScanConfiguration.from(),
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
            appCheckTokenProvider: FirebaseMealScanAppCheckTokenProvider(),
            storeKitEvidenceProvider: StoreKitMealScanEvidenceProvider()
        )
    }

    private static func makeRepeatMealFingerprinter() -> any MealImageFingerprinting {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITestMode"),
           arguments.contains("SeedRepeatMealSuggestion") {
            return UITestRepeatMealImageFingerprinter()
        }
        #endif
        return VisionRepeatMealImageFingerprinter()
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    #if DEBUG
    private func applyUITestPhaseFixtureIfNeeded(arguments: [String]) {
        guard arguments.contains("UITestMode"),
              let fixture = Self.uiTestFixture(in: arguments) else { return }

        if fixture == "photoChoice" || fixture == "permissionDenied" || fixture == "freshFlow" {
            phase = .photoChoice
        } else if fixture == "processing" {
            processingStage = .estimatingFoodsAndPortions
            phase = .processing
        } else if fixture == "consent" {
            seedUITestPhoto()
            phase = .remoteConsent
        } else if fixture == "freshReview" {
            seedUITestReview(consumption: .used, cacheDisposition: .fresh)
        } else if fixture == "cacheReview" {
            seedUITestReview(consumption: .notUsed, cacheDisposition: .local)
        } else if fixture == "freshSaveFailure" {
            seedUITestReview(consumption: .used, cacheDisposition: .fresh)
            failure = MealScanFailure(kind: .saveFailed, consumption: .used, retryBehavior: .retrySave)
        } else if fixture == "cacheSaveFailure" {
            seedUITestReview(consumption: .notUsed, cacheDisposition: .local)
            failure = MealScanFailure(kind: .saveFailed, consumption: .notUsed, retryBehavior: .retrySave)
        } else if fixture == "saved" {
            seedUITestReview(consumption: .notUsed, cacheDisposition: .local)
            phase = .saved
        } else if let seededFailure = Self.uiTestFailure(for: fixture) {
            seedUITestPhoto()
            pendingRequestID = UUID(uuidString: "A8A72F4E-96C3-494F-B9BD-111D8D3B6AA8")
            applyFailure(seededFailure)
            pendingPhotoRetryEligible = seededFailure.retryBehavior == .retrySameRequest
            phase = .failure
        }
    }

    private static func uiTestFixture(in arguments: [String]) -> String? {
        guard arguments.contains("UITestMode"),
              let keyIndex = arguments.firstIndex(of: "-mealScan.fixture"),
              arguments.indices.contains(keyIndex + 1) else { return nil }
        return arguments[keyIndex + 1]
    }

    private func seedUITestPhoto() {
        guard let image = UIImage(named: "botanical-meal-bowl") else { return }
        selectedImage = image
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        selectedImageData = data
        pendingNormalizedImage = NormalizedMealScanImage(
            jpegData: data,
            sourceImageHash: MealScanImageNormalizer.sha256Hex(data),
            width: max(1, Int(image.size.width.rounded())),
            height: max(1, Int(image.size.height.rounded()))
        )
    }

    private func seedUITestReview(
        consumption: MealScanConsumptionState,
        cacheDisposition: MealScanCacheDisposition
    ) {
        seedUITestPhoto()
        let fixtureFoods: [(String, Double)] = [
            ("chicken-breast-cooked", 115),
            ("rice-brown-cooked", 165),
            ("broccoli", 95),
        ]
        let items = fixtureFoods.compactMap { foodID, grams -> MealFoodItemDraft? in
            guard let food = SampleNutritionFixtures.records.first(where: { $0.id == foodID }) else {
                return nil
            }
            return MealFoodItemDraft(
                displayName: food.displayName,
                canonicalFoodId: food.id,
                nutritionSource: food.source,
                estimatedGrams: grams,
                servingDescription: food.servingDescription,
                nutrition: calculator.calculateItemNutrition(food: food, grams: grams),
                confidence: .high,
                detectionSource: "ui_test_fixture",
                portionEstimationMethod: .servingSizeHeuristic
            )
        }
        let nutrition = calculator.aggregateMealNutrition(items: items)
        let profile = metabolicProfileService.profile(
            for: nutrition,
            confidence: .high,
            hiddenIngredientEstimate: .aLittle,
            visibleWarnings: [
                L10n.string(
                    "Check sauces and cooking oils before saving.",
                    defaultValue: "Check sauces and cooking oils before saving."
                ),
            ]
        )
        apply(result: MealScanResult(
            mealName: L10n.string("Chicken and brown rice bowl", defaultValue: "Chicken and brown rice bowl"),
            mealType: mealType,
            detectedItems: items,
            nutrition: nutrition,
            metabolicProfile: profile,
            confidence: .high,
            warnings: [
                L10n.string(
                    "Check sauces and cooking oils before saving.",
                    defaultValue: "Check sauces and cooking oils before saving."
                ),
            ],
            originalPredictionJSON: "{\"source\":\"ui_test_fixture\"}",
            modelVersion: "ui-test-fixture-v1",
            pipelineVersion: "ui-test-fixture-v1"
        ))
        hiddenIngredientEstimate = .aLittle
        analysisSource = switch cacheDisposition {
        case .fresh: .fresh
        case .server: .serverCache
        case .local: .localCache
        }
        pendingRequestConsumption = analysisSource?.consumption ?? consumption
        phase = .review
    }

    private static func uiTestFailure(for fixture: String) -> MealScanFailure? {
        switch fixture {
        case "serviceDisabled":
            MealScanFailure(
                kind: .serviceDisabled,
                cause: .featureDisabled,
                consumption: .notUsed,
                recovery: .none
            )
        case "offlineBeforeDispatch":
            MealScanFailure(
                kind: .offlineBeforeDispatch,
                cause: .offline,
                consumption: .notUsed,
                recovery: .retrySameRequest(afterSeconds: nil)
            )
        case "transportUnknown", "connectionInterruptedAfterDispatch":
            MealScanFailure(
                kind: .connectionInterruptedAfterDispatch,
                cause: .transportOutcomeUnknown,
                consumption: .unknown,
                recovery: .checkSameRequest(afterSeconds: nil)
            )
        case "providerTimeout":
            MealScanFailure(
                kind: .connectionInterruptedAfterDispatch,
                cause: .providerTimeout,
                consumption: .used,
                recovery: .checkSameRequest(afterSeconds: nil)
            )
        case "appIntegrity":
            MealScanFailure(
                kind: .appIntegrity,
                cause: .appIntegrityRejected,
                consumption: .notUsed,
                recovery: .retrySameRequest(afterSeconds: nil)
            )
        case "entitlement":
            MealScanFailure(
                kind: .entitlement,
                cause: .entitlementRejected,
                consumption: .notUsed,
                recovery: .retrySameRequest(afterSeconds: nil)
            )
        case "quotaExhausted":
            MealScanFailure(
                kind: .quotaExhausted,
                cause: .quotaExhausted,
                consumption: .notUsed,
                recovery: .none,
                quota: MealScanQuota(
                    tier: "paid",
                    used: 10,
                    limit: 10,
                    remaining: 0,
                    windowSeconds: 86_400,
                    resetAt: "2026-07-18T01:02:03.000Z",
                    retryAfterSeconds: 120
                )
            )
        case "unreadablePreflight":
            MealScanFailure(
                kind: .unreadableMeal,
                cause: .invalidImage,
                consumption: .notUsed,
                recovery: .none
            )
        case "unreadableMeal", "unreadableProvider":
            MealScanFailure(
                kind: .unreadableMeal,
                cause: .providerResponseInvalid,
                consumption: .used,
                recovery: .none
            )
        case "pendingUnknown", "ambiguousResult":
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .requestPending,
                consumption: .unknown,
                recovery: .checkSameRequest(afterSeconds: nil)
            )
        case "serverOutcomeUsed":
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .serverOutcomeUnknown,
                consumption: .used,
                recovery: .checkSameRequest(afterSeconds: nil)
            )
        default:
            nil
        }
    }
    #endif
}

#if DEBUG
private struct UITestRepeatMealImageFingerprinter: MealImageFingerprinting {
    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint {
        MealImageFingerprint(
            sourceImageHash: MealScanImageNormalizer.sha256Hex(normalizedJPEGData),
            featurePrintArchive: nil,
            visionRevision: 2
        )
    }

    func distance(
        between lhs: MealImageFingerprint,
        and rhs: MealImageFingerprint
    ) async throws -> Float {
        throw RepeatMealFingerprintError.missingArchive
    }
}
#endif

private enum MealScanViewModelError: Error {
    case missingPendingImage
    case missingRequestID
    case remoteConsentRequired
    case ambiguousOutcomeRequired
    case retryablePhotoRequired
    case newAttemptConfirmationRequired
    case missingSavedMealIdentity
    case savedMealNotFound
    case invalidSave
}
