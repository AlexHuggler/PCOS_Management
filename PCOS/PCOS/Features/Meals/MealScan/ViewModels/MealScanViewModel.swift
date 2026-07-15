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
        case remoteConsent
        case ambiguousOutcome
        case newAttemptConfirmation
        case review
        case manualFallback
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
    private let remoteMealScanService: (any RemoteMealScanServing)?
    private let imageNormalizer: any MealScanImageNormalizing
    private let repeatMealFingerprinter: any MealImageFingerprinting
    private let repeatMealCache: (any MealScanRepeatCaching)?
    private let mealLogRepository: any MealLogRepository
    private var pendingNormalizedImage: NormalizedMealScanImage?
    private var pendingFingerprint: MealImageFingerprint?
    private var repeatSourceRecordID: UUID?
    private(set) var pendingRequestID: UUID?
    private var unknownRetryCount = 0
    private var sameRequestRecheckCount = 0
    private var pendingRetryAvailableAt: Date?
    private(set) var pendingRetryAfterSeconds: Int?
    private(set) var isRequestPending = false
    private var pendingPhotoRetryEligible = false
    private var pendingPhotoRetryAvailableAt: Date?

    var phase: Phase = .entry
    private(set) var processingStage: ProcessingStage = .preparingPhoto
    var mealType: MealType
    var mealName: String = L10n.string("Photo meal estimate", defaultValue: "Photo meal estimate")
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
    private(set) var mealScanQuota: MealScanQuota?
    private(set) var mealScanCacheDisposition: MealScanCacheDisposition?
    private(set) var savedMealID: UUID?

    var canAddManualFood: Bool { true }
    var canStartFreshAnalysis: Bool { mealScanQuota?.remaining != 0 }
    var canRetryAmbiguousOutcome: Bool {
        canRetryAmbiguousOutcome(at: Date())
    }
    func canRetryAmbiguousOutcome(at now: Date) -> Bool {
        guard phase == .ambiguousOutcome,
              sameRequestRecheckCount < 2,
              isRequestPending || unknownRetryCount < 1 else {
            return false
        }
        return pendingRetryAvailableAt.map { now >= $0 } ?? true
    }
    var pendingRetryAvailableAtLocalText: String? {
        pendingRetryAvailableAt?.formatted(date: .omitted, time: .shortened)
    }
    var hasRetryablePendingPhoto: Bool {
        phase == .manualFallback && pendingPhotoRetryEligible && pendingNormalizedImage != nil && pendingRequestID != nil
    }
    var canRetryPendingPhoto: Bool {
        canRetryPendingPhoto(at: Date())
    }
    func canRetryPendingPhoto(at now: Date) -> Bool {
        guard hasRetryablePendingPhoto, canStartFreshAnalysis else { return false }
        return pendingPhotoRetryAvailableAt.map { now >= $0 } ?? true
    }
    var pendingPhotoRetryAvailableAtLocalText: String? {
        pendingPhotoRetryAvailableAt?.formatted(date: .omitted, time: .shortened)
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
        phase = .camera
    }

    func scanWithFallback(image: UIImage) async {
        do {
            try await prepareSelectedImage(image)
        } catch {
            errorMessage = error.localizedDescription + " " + L10n.string(
                "No fresh AI photo analysis was used.",
                defaultValue: "No fresh AI photo analysis was used."
            )
            phase = .manualFallback
        }
    }

    func scan(image: UIImage) async throws {
        try await prepareSelectedImage(image)
    }

    func prepareSelectedImage(_ image: UIImage) async throws {
        savedMealID = nil
        selectedImage = image
        errorMessage = nil
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
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil

        processingStage = .checkingPreviousEstimate
        if let remoteMealScanService,
           let normalizedImage = pendingNormalizedImage {
            if let cachedOutcome = try? await remoteMealScanService.cachedOutcome(
                normalizedImage: normalizedImage,
                mealType: mealType
            ) {
                mealScanCacheDisposition = cachedOutcome.cacheDisposition
                apply(result: cachedOutcome.result)
                phase = .review
                return
            }

            phase = .remoteConsent
            return
        }

        try await performPendingImageScan()
    }

    func confirmRemotePhotoEstimate() async throws {
        guard phase == .remoteConsent,
              remoteMealScanService != nil else {
            throw MealScanViewModelError.remoteConsentRequired
        }

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
        try await performPendingImageScan()
    }

    func requestNewAnalysisAfterAmbiguousOutcome() {
        guard phase == .ambiguousOutcome, canStartFreshAnalysis else { return }
        phase = .newAttemptConfirmation
    }

    func cancelNewAnalysisConfirmation() {
        guard phase == .newAttemptConfirmation else { return }
        phase = .ambiguousOutcome
    }

    func confirmNewAnalysisAfterAmbiguousOutcome() async throws {
        guard phase == .newAttemptConfirmation,
              pendingNormalizedImage != nil,
              canStartFreshAnalysis else {
            throw MealScanViewModelError.newAttemptConfirmationRequired
        }
        pendingRequestID = UUID()
        resetAmbiguousRequestState()
        try await performPendingImageScan()
    }

    func continueWithManualEntry() {
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingRequestID = nil
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
        pendingFingerprint = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        errorMessage = nil
        addManualFood(named: L10n.string("Manual food", defaultValue: "Manual food"))
    }

    private func performPendingImageScan(startedFromUnknownRecheck: Bool = false) async throws {
        guard let normalizedImage = pendingNormalizedImage else {
            throw MealScanViewModelError.missingPendingImage
        }

        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
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
                mealScanCacheDisposition = outcome.cacheDisposition
                resetAmbiguousRequestState()
            } catch let error as MealScanRemoteError {
                errorMessage = error.errorDescription
                switch error {
                case .outcomeUnknown(let unknownRequestID):
                    pendingRequestID = unknownRequestID
                    isRequestPending = false
                    pendingRetryAfterSeconds = nil
                    pendingRetryAvailableAt = nil
                    phase = .ambiguousOutcome
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
                    phase = .ambiguousOutcome
                default:
                    phase = .manualFallback
                }
                return
            } catch let error as GeminiMealScanProxyError {
                mealScanQuota = error.quota ?? mealScanQuota
                errorMessage = error.errorDescription
                pendingPhotoRetryEligible = error.retryable == true && canStartFreshAnalysis
                pendingPhotoRetryAvailableAt = error.retryAfterSeconds.map {
                    Date().addingTimeInterval(TimeInterval($0))
                }
                phase = .manualFallback
                return
            } catch {
                errorMessage = L10n.string(
                    "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually.",
                    defaultValue: "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually."
                )
                phase = .manualFallback
                return
            }
        } else if featureFlags.enableMockMealScanData,
                  let image = selectedImage {
            result = try await pipeline.scan(image: image, mealType: mealType)
            mealScanQuota = nil
            mealScanCacheDisposition = nil
        } else {
            errorMessage = L10n.string(
                "Photo estimates are not configured. Scan a barcode or enter the meal manually.",
                defaultValue: "Photo estimates are not configured. Scan a barcode or enter the meal manually."
            )
            phase = .manualFallback
            return
        }
        apply(result: result)
        phase = .review
    }

    func useMockPhoto() async {
        #if DEBUG
        guard let sampleImage = UIImage(named: "botanical-meal-bowl") else {
            errorMessage = L10n.string(
                "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually.",
                defaultValue: "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually."
            )
            phase = .manualFallback
            return
        }
        await scanWithFallback(image: sampleImage)
        #else
        errorMessage = L10n.string(
            "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually.",
            defaultValue: "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually."
        )
        phase = .manualFallback
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
        mutate(&draftItems[index])
        draftItems[index].recordUserEdit(previousEstimatedGrams: previousEstimatedGrams)
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
        let confirmedMeal = confirmedMeal()
        try await mealLogRepository.saveMealScan(confirmedMeal)
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
            mealContext: "After \(meal.mealDescription)",
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
        selectedImage = nil
        selectedImageData = nil
        pendingNormalizedImage = nil
        pendingRequestID = nil
        resetAmbiguousRequestState()
        resetPendingPhotoRetryState()
        pendingFingerprint = nil
        repeatMealSuggestion = nil
        repeatSourceRecordID = nil
        errorMessage = nil
        phase = .camera
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
        guard arguments.contains("UITestMode") else { return }

        if arguments.contains("SeedMealScanProcessingPhase") {
            processingStage = .estimatingFoodsAndPortions
            phase = .processing
        } else if arguments.contains("SeedMealScanManualFallbackPhase") {
            errorMessage = L10n.string(
                "No food was confidently detected. You can retake the photo or add the meal manually.",
                defaultValue: "No food was confidently detected. You can retake the photo or add the meal manually."
            )
            phase = .manualFallback
        } else if arguments.contains("SeedMealScanAmbiguousOutcomePhase") {
            pendingRequestID = UUID(uuidString: "A8A72F4E-96C3-494F-B9BD-111D8D3B6AA8")
            errorMessage = L10n.string(
                "CycleBalance could not confirm whether the previous analysis completed.",
                defaultValue: "CycleBalance could not confirm whether the previous analysis completed."
            )
            phase = .ambiguousOutcome
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
}
