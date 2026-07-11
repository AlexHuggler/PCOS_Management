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

    @Test("matching photo offers repeat meal before any remote scan")
    func matchingPhotoOffersRepeatBeforeRemoteScan() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let fingerprint = makeFingerprint(for: normalized)
        let suggestion = makeRepeatSuggestion()
        let repeatCache = SpyMealScanRepeatCache(suggestion: suggestion)
        let remote = SpyRemoteMealScanService(result: makeScanResult(mealName: "Fresh remote meal"))
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: fingerprint,
            repeatCache: repeatCache,
            remote: remote
        )

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .repeatSuggestion)
        #expect(viewModel.repeatMealSuggestion == suggestion)
        #expect(repeatCache.suggestionCallCount == 1)
        #expect(remote.callCount == 0)
    }

    @Test("using previous meal restores reviewed fields with fresh IDs")
    func usePreviousMealRestoresReviewedFieldsWithFreshIDs() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let fingerprint = makeFingerprint(for: normalized)
        let suggestion = makeRepeatSuggestion()
        let originalItemIDs = Set(suggestion.snapshot.items.map(\.id))
        let repeatCache = SpyMealScanRepeatCache(suggestion: suggestion)
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: fingerprint,
            repeatCache: repeatCache,
            remote: SpyRemoteMealScanService(result: makeScanResult())
        )
        try await viewModel.prepareSelectedImage(UIImage())

        viewModel.usePreviousMeal()

        #expect(viewModel.phase == .review)
        #expect(viewModel.mealName == suggestion.snapshot.mealName)
        #expect(viewModel.mealType == suggestion.snapshot.mealType)
        #expect(viewModel.totalNutrition == suggestion.snapshot.nutrition)
        #expect(viewModel.confidence == suggestion.snapshot.confidence)
        #expect(viewModel.warnings == suggestion.snapshot.warnings)
        #expect(viewModel.hiddenIngredientEstimate == suggestion.snapshot.hiddenIngredientEstimate)
        #expect(viewModel.lastScanResult?.modelVersion == suggestion.snapshot.source.modelVersion)
        #expect(viewModel.lastScanResult?.pipelineVersion == suggestion.snapshot.source.pipelineVersion)
        #expect(Set(viewModel.draftItems.map(\.id)).isDisjoint(with: originalItemIDs))
        #expect(viewModel.draftItems.map(\.canonicalFoodId) == suggestion.snapshot.items.map(\.canonicalFoodId))
        #expect(viewModel.metabolicProfile != nil)
        #expect(viewModel.confirmedMeal().repeatSourceRecordID == suggestion.recordID)
        #expect(repeatCache.reusedRecordIDs == [suggestion.recordID])
    }

    @Test("scan as new bypasses repeat lookup and scans normalized image once")
    func scanAsNewBypassesRepeatLookupOnce() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let repeatCache = SpyMealScanRepeatCache(suggestion: makeRepeatSuggestion())
        let remoteResult = makeScanResult(mealName: "Fresh remote meal")
        let remote = SpyRemoteMealScanService(result: remoteResult)
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: repeatCache,
            remote: remote
        )
        try await viewModel.prepareSelectedImage(UIImage())

        try await viewModel.scanPendingImageAsNew()

        #expect(repeatCache.suggestionCallCount == 1)
        #expect(remote.callCount == 1)
        #expect(remote.receivedImages == [normalized])
        #expect(viewModel.phase == .review)
        #expect(viewModel.mealName == remoteResult.mealName)
        #expect(viewModel.repeatMealSuggestion == nil)
        #expect(viewModel.confirmedMeal().repeatSourceRecordID == nil)
    }

    @Test("local fingerprint failure continues with normal remote scan")
    func fingerprintFailureContinuesWithRemoteScan() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let repeatCache = SpyMealScanRepeatCache(suggestion: makeRepeatSuggestion())
        let remote = SpyRemoteMealScanService(result: makeScanResult(mealName: "Fresh after local failure"))
        var flags = MealScanFeatureFlags.passOneDefaults
        flags.enableRepeatMealSuggestions = true
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: flags,
            imageNormalizer: FixedMealScanImageNormalizer(normalized: normalized),
            repeatMealFingerprinter: ThrowingRepeatMealFingerprinter(),
            repeatMealCache: repeatCache
        )

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(repeatCache.suggestionCallCount == 0)
        #expect(remote.callCount == 1)
        #expect(viewModel.phase == .review)
    }

    @Test("save persists reviewed meal before repeat cache snapshot")
    func savePersistsMealBeforeRepeatCache() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let events = ScanEventRecorder()
        let repeatCache = SpyMealScanRepeatCache(suggestion: nil, events: events)
        let mealRepository = SpyMealLogRepository(events: events)
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: repeatCache,
            remote: SpyRemoteMealScanService(result: makeScanResult()),
            mealRepository: mealRepository
        )
        try await viewModel.prepareSelectedImage(UIImage())
        viewModel.mealName = "Final reviewed bowl"
        events.values.removeAll()

        try await viewModel.save()

        let savedMeal = try #require(mealRepository.savedMeals.first)
        let cached = try #require(repeatCache.savedSnapshots.first)
        #expect(events.values == ["repository", "cache"])
        #expect(cached.sourceMealID == savedMeal.id)
        #expect(cached.sourceMealLoggedAt == savedMeal.loggedAt)
        #expect(cached.snapshot.mealName == "Final reviewed bowl")
        #expect(cached.fingerprint == makeFingerprint(for: normalized))
        #expect(viewModel.phase == .saved)
    }

    @Test("failed meal save never writes repeat cache")
    func failedMealSaveDoesNotWriteRepeatCache() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let repeatCache = SpyMealScanRepeatCache(suggestion: nil)
        let mealRepository = SpyMealLogRepository(saveError: ViewModelRepeatTestError.repositorySaveFailed)
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: repeatCache,
            remote: SpyRemoteMealScanService(result: makeScanResult()),
            mealRepository: mealRepository
        )
        try await viewModel.prepareSelectedImage(UIImage())

        await #expect(throws: ViewModelRepeatTestError.repositorySaveFailed) {
            try await viewModel.save()
        }

        #expect(repeatCache.savedSnapshots.isEmpty)
        #expect(viewModel.phase == .review)
    }

    @Test("repeat cache write failure leaves saved meal successful")
    func repeatCacheWriteFailureDoesNotUndoSavedMeal() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let repeatCache = SpyMealScanRepeatCache(
            suggestion: nil,
            saveError: ViewModelRepeatTestError.cacheSaveFailed
        )
        let mealRepository = SpyMealLogRepository()
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: repeatCache,
            remote: SpyRemoteMealScanService(result: makeScanResult()),
            mealRepository: mealRepository
        )
        try await viewModel.prepareSelectedImage(UIImage())

        try await viewModel.save()

        #expect(mealRepository.savedMeals.count == 1)
        #expect(viewModel.phase == .saved)
    }

    private func makeRepeatEnabledViewModel(
        context: ModelContext,
        normalized: NormalizedMealScanImage,
        fingerprint: MealImageFingerprint,
        repeatCache: SpyMealScanRepeatCache,
        remote: SpyRemoteMealScanService,
        mealRepository: SpyMealLogRepository = SpyMealLogRepository()
    ) -> MealScanViewModel {
        var flags = MealScanFeatureFlags.passOneDefaults
        flags.enableRepeatMealSuggestions = true
        return MealScanViewModel(
            mealType: .lunch,
            modelContext: context,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: flags,
            imageNormalizer: FixedMealScanImageNormalizer(normalized: normalized),
            repeatMealFingerprinter: FixedRepeatMealFingerprinter(fingerprint: fingerprint),
            repeatMealCache: repeatCache,
            mealLogRepository: mealRepository
        )
    }

    private func makeNormalizedImage() -> NormalizedMealScanImage {
        let data = Data("repeat-meal-normalized-image".utf8)
        return NormalizedMealScanImage(
            jpegData: data,
            sourceImageHash: MealScanImageNormalizer.sha256Hex(data),
            width: 16,
            height: 12
        )
    }

    private func makeFingerprint(for image: NormalizedMealScanImage) -> MealImageFingerprint {
        MealImageFingerprint(
            sourceImageHash: image.sourceImageHash,
            featurePrintArchive: Data([0x01, 0x02]),
            visionRevision: 2
        )
    }

    private func makeRepeatSuggestion() -> RepeatMealSuggestion {
        let snapshot = RepeatMealDraftSnapshot(
            mealName: "Reviewed lentil bowl",
            mealType: .dinner,
            items: makeScanResult().detectedItems,
            nutrition: makeScanResult().nutrition,
            confidence: .high,
            warnings: ["Review the dressing amount."],
            hiddenIngredientEstimate: .aLittle,
            source: RepeatMealSourceMetadata(
                modelVersion: "gemini-reviewed-v1",
                pipelineVersion: "reviewed-pipeline-v1"
            )
        )
        return RepeatMealSuggestion(
            recordID: UUID(),
            sourceMealID: UUID(),
            snapshot: snapshot,
            sourceMealLoggedAt: Date(timeIntervalSince1970: 1_780_200_000),
            matchKind: .exactImage
        )
    }

    private func makeScanResult(mealName: String = "Remote rice bowl") -> MealScanResult {
        let nutrition = NutritionSnapshot(
            caloriesKcal: 430,
            proteinGrams: 27,
            carbsGrams: 52,
            fatGrams: 14,
            fiberGrams: 9
        )
        let item = MealFoodItemDraft(
            displayName: "Lentil rice bowl",
            canonicalFoodId: "lentil-rice-bowl",
            nutritionSource: .usda,
            estimatedGrams: 320,
            nutrition: nutrition,
            confidence: .high,
            detectionSource: "remote_test",
            portionEstimationMethod: .servingSizeHeuristic
        )
        return MealScanResult(
            mealName: mealName,
            mealType: .lunch,
            detectedItems: [item],
            nutrition: nutrition,
            metabolicProfile: MealMetabolicProfile(
                carbLoadCategory: .moderate,
                proteinAdequacy: .strong,
                fiberAdequacy: .strong,
                fatLevel: .moderate,
                estimatedGlycemicImpact: .moderate,
                mealBalanceScore: 82,
                explanation: "Balanced test meal."
            ),
            confidence: .high,
            warnings: [],
            originalPredictionJSON: "{\"source\":\"test\"}",
            modelVersion: "remote-test-v1",
            pipelineVersion: "remote-pipeline-v1"
        )
    }
}

private enum ViewModelRepeatTestError: Error {
    case fingerprintFailed
    case repositorySaveFailed
    case cacheSaveFailed
}

@MainActor
private final class ScanEventRecorder {
    var values: [String] = []
}

private struct FixedMealScanImageNormalizer: MealScanImageNormalizing {
    let normalized: NormalizedMealScanImage

    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        normalized
    }
}

private struct FixedRepeatMealFingerprinter: MealImageFingerprinting {
    let fingerprint: MealImageFingerprint

    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint {
        fingerprint
    }

    func distance(between lhs: MealImageFingerprint, and rhs: MealImageFingerprint) async throws -> Float {
        0
    }
}

private struct ThrowingRepeatMealFingerprinter: MealImageFingerprinting {
    func makeFingerprint(for normalizedJPEGData: Data) async throws -> MealImageFingerprint {
        throw ViewModelRepeatTestError.fingerprintFailed
    }

    func distance(between lhs: MealImageFingerprint, and rhs: MealImageFingerprint) async throws -> Float {
        throw ViewModelRepeatTestError.fingerprintFailed
    }
}

@MainActor
private final class SpyRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var callCount = 0
    private(set) var receivedImages: [NormalizedMealScanImage] = []

    init(result: MealScanResult) {
        self.result = result
    }

    func scan(normalizedImage: NormalizedMealScanImage, mealType: MealType) async throws -> MealScanResult {
        callCount += 1
        receivedImages.append(normalizedImage)
        return result
    }
}

@MainActor
private final class SpyMealScanRepeatCache: MealScanRepeatCaching {
    struct SavedSnapshot: Equatable {
        var snapshot: RepeatMealDraftSnapshot
        var sourceMealID: UUID
        var sourceMealLoggedAt: Date
        var fingerprint: MealImageFingerprint
    }

    var suggestionResult: RepeatMealSuggestion?
    var saveError: Error?
    var events: ScanEventRecorder?
    private(set) var suggestionCallCount = 0
    private(set) var reusedRecordIDs: [UUID] = []
    private(set) var savedSnapshots: [SavedSnapshot] = []

    init(
        suggestion: RepeatMealSuggestion?,
        events: ScanEventRecorder? = nil,
        saveError: Error? = nil
    ) {
        suggestionResult = suggestion
        self.events = events
        self.saveError = saveError
    }

    func suggestion(for fingerprint: MealImageFingerprint, now: Date) async -> RepeatMealSuggestion? {
        suggestionCallCount += 1
        return suggestionResult
    }

    func save(
        snapshot: RepeatMealDraftSnapshot,
        sourceMealID: UUID,
        sourceMealLoggedAt: Date,
        fingerprint: MealImageFingerprint,
        now: Date
    ) throws {
        events?.values.append("cache")
        if let saveError { throw saveError }
        savedSnapshots.append(
            SavedSnapshot(
                snapshot: snapshot,
                sourceMealID: sourceMealID,
                sourceMealLoggedAt: sourceMealLoggedAt,
                fingerprint: fingerprint
            )
        )
    }

    func markMatched(recordID: UUID, now: Date) throws {}

    func markReused(recordID: UUID, now: Date) throws {
        reusedRecordIDs.append(recordID)
    }

    func removeRecords(sourceMealID: UUID) throws {}
}

@MainActor
private final class SpyMealLogRepository: MealLogRepository {
    var saveError: Error?
    var events: ScanEventRecorder?
    private(set) var savedMeals: [ConfirmedMealScan] = []

    init(
        events: ScanEventRecorder? = nil,
        saveError: Error? = nil
    ) {
        self.events = events
        self.saveError = saveError
    }

    func saveMealScan(_ confirmedMeal: ConfirmedMealScan) async throws {
        events?.values.append("repository")
        if let saveError { throw saveError }
        savedMeals.append(confirmedMeal)
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
