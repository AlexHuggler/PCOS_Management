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

    @Test("image preparation errors stay typed and disclose no quota use")
    func imagePreparationErrorStaysTyped() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .dinner,
            modelContext: container.mainContext,
            pipeline: .mock(),
            imageNormalizer: ThrowingMealScanImageNormalizer()
        )

        await viewModel.scanWithFallback(image: UIImage())

        #expect(viewModel.phase == .manualFallback)
        #expect(viewModel.errorMessage?.localizedCaseInsensitiveContains("secure upload limit") == true)
        #expect(viewModel.errorMessage?.localizedCaseInsensitiveContains("no fresh AI photo analysis was used") == true)
        #expect(viewModel.lastScanResult == nil)
    }

    @Test("remote scan failure fails closed without synthesizing a local estimate")
    func remoteScanFailureDoesNotUseLocalPipeline() async throws {
        let container = try TestHelpers.makeModelContainer()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: ThrowingRemoteMealScanEstimator(),
            resultCache: nil,
            imageNormalizer: ViewModelStubMealScanImageNormalizer(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: GeminiRemoteMealScanConfiguration(
                proxyEndpointURL: URL(string: "https://example.com/v1/meal-scans/estimate")
            ),
            storeKitEvidenceProvider: ViewModelFixedStoreKitEvidenceProvider()
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: service
        )

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .remoteConsent)

        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.phase == .manualFallback)
        #expect(viewModel.lastScanResult == nil)
        #expect(viewModel.draftItems.isEmpty)
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
                proxyEndpointURL: URL(string: "https://example.com/v1/meal-scans/estimate")
            ),
            storeKitEvidenceProvider: ViewModelFixedStoreKitEvidenceProvider()
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: service
        )

        await viewModel.scanWithFallback(image: UIImage())

        #expect(viewModel.phase == .remoteConsent)

        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.phase == .manualFallback)
        #expect(viewModel.errorMessage?.localizedCaseInsensitiveContains("rolling 24-hour") == true)
        #expect(viewModel.lastScanResult == nil)
        #expect(viewModel.draftItems.isEmpty)
        #expect(viewModel.canAddManualFood)
        #expect(viewModel.mealScanQuota?.remaining == 0)
        #expect(viewModel.canStartFreshAnalysis == false)
    }

    @Test("ambiguous outcome preserves one request ID until explicit new-analysis confirmation")
    func ambiguousOutcomePreservesRequestIDUntilExplicitConfirmation() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = SpyRemoteMealScanService(
            result: makeScanResult(),
            throwsOutcomeUnknown: true
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())
        let originalRequestID = try #require(viewModel.pendingRequestID)
        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.phase == .ambiguousOutcome)
        #expect(remote.receivedRequestIDs == [originalRequestID])

        try await viewModel.retryAmbiguousOutcome()
        #expect(viewModel.phase == .ambiguousOutcome)
        #expect(remote.receivedRequestIDs == [originalRequestID, originalRequestID])
        #expect(viewModel.canRetryAmbiguousOutcome == false)

        viewModel.requestNewAnalysisAfterAmbiguousOutcome()
        #expect(viewModel.phase == .newAttemptConfirmation)
        #expect(viewModel.pendingRequestID == originalRequestID)

        try await viewModel.confirmNewAnalysisAfterAmbiguousOutcome()
        let newRequestID = try #require(viewModel.pendingRequestID)
        #expect(newRequestID != originalRequestID)
        #expect(remote.receivedRequestIDs == [originalRequestID, originalRequestID, newRequestID])
    }

    @Test("fresh outcome retains exact rolling quota and warns at two remaining")
    func freshOutcomeRetainsRollingQuota() async throws {
        let container = try TestHelpers.makeModelContainer()
        let quota = MealScanQuota(
            tier: "paid",
            used: 8,
            limit: 10,
            remaining: 2,
            windowSeconds: 86_400,
            resetAt: "2026-07-14T01:02:03.000Z",
            retryAfterSeconds: nil
        )
        let remote = SpyRemoteMealScanService(result: makeScanResult(), quota: quota)
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())
        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.mealScanQuota == quota)
        #expect(viewModel.mealScanCacheDisposition == .fresh)
        #expect(viewModel.shouldWarnAboutRemainingAnalyses)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetDate = try #require(formatter.date(from: "2026-07-14T01:02:03.000Z"))
        #expect(viewModel.quotaResetAtLocalText == resetDate.formatted(date: .abbreviated, time: .shortened))
    }

    @Test("quota zero still permits exact local structured-cache reuse")
    func quotaZeroStillPermitsLocalCacheReuse() async throws {
        let container = try TestHelpers.makeModelContainer()
        let quota = MealScanQuota(
            tier: "paid",
            used: 10,
            limit: 10,
            remaining: 0,
            windowSeconds: 86_400,
            resetAt: "2026-07-14T01:02:03.000Z",
            retryAfterSeconds: 120
        )
        let remote = SpyRemoteMealScanService(result: makeScanResult(), quota: quota)
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())
        try await viewModel.confirmRemotePhotoEstimate()
        #expect(viewModel.canStartFreshAnalysis == false)

        remote.cachedOutcomeResult = MealScanOutcome(
            result: makeScanResult(mealName: "Local cached meal"),
            quota: nil,
            cacheDisposition: .local
        )
        viewModel.retake()
        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .review)
        #expect(viewModel.mealName == "Local cached meal")
        #expect(viewModel.mealScanCacheDisposition == .local)
        #expect(remote.callCount == 1)
        #expect(remote.cachedOutcomeCallCount == 2)
    }

    @Test("quota zero still permits a free server-cache check")
    func quotaZeroStillPermitsServerCacheCheck() async throws {
        let container = try TestHelpers.makeModelContainer()
        let quota = MealScanQuota(
            tier: "paid",
            used: 10,
            limit: 10,
            remaining: 0,
            windowSeconds: 86_400,
            resetAt: "2026-07-14T01:02:03.000Z",
            retryAfterSeconds: 120
        )
        let remote = SpyRemoteMealScanService(result: makeScanResult(), quota: quota)
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())
        try await viewModel.confirmRemotePhotoEstimate()
        #expect(viewModel.canStartFreshAnalysis == false)

        remote.cacheDisposition = .server
        viewModel.retake()
        try await viewModel.prepareSelectedImage(UIImage())
        #expect(viewModel.phase == .remoteConsent)

        try await viewModel.confirmRemotePhotoEstimate()
        #expect(viewModel.phase == .review)
        #expect(viewModel.mealScanCacheDisposition == .server)
        #expect(remote.callCount == 2)
    }

    @Test("unknown then pending then complete uses one request ID and two bounded checks")
    func unknownPendingCompleteKeepsOneRequestID() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = SpyRemoteMealScanService(
            result: makeScanResult(),
            queuedErrors: [
                .outcomeUnknown(requestID: UUID()),
                .requestPending(requestID: UUID(), retryAfterSeconds: 0)
            ]
        )
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())
        let requestID = try #require(viewModel.pendingRequestID)
        remote.rewriteQueuedErrorRequestIDs(to: requestID)

        try await viewModel.confirmRemotePhotoEstimate()
        #expect(viewModel.phase == .ambiguousOutcome)
        #expect(viewModel.isRequestPending == false)

        try await viewModel.retryAmbiguousOutcome()
        #expect(viewModel.phase == .ambiguousOutcome)
        #expect(viewModel.isRequestPending)
        #expect(viewModel.canRetryAmbiguousOutcome)

        try await viewModel.retryAmbiguousOutcome()
        #expect(viewModel.phase == .review)
        #expect(remote.receivedRequestIDs == [requestID, requestID, requestID])
        #expect(viewModel.canRetryAmbiguousOutcome == false)
    }

    @Test("manual fallback starts with blank user-entered nutrition")
    func manualFallbackStartsBlank() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .dinner,
            modelContext: container.mainContext,
            pipeline: .mock()
        )

        viewModel.continueWithManualEntry()

        let item = try #require(viewModel.draftItems.first)
        #expect(item.canonicalFoodId == "manual-food")
        #expect(item.nutritionSource == .userManual)
        #expect(item.nutrition == NutritionSnapshot())
        #expect(viewModel.totalNutrition == NutritionSnapshot())
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

    @Test("fresh remote photo waits for explicit consent before upload")
    func freshRemotePhotoWaitsForConsent() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let repeatCache = SpyMealScanRepeatCache(suggestion: nil)
        let remote = SpyRemoteMealScanService(result: makeScanResult(mealName: "Fresh remote meal"))
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: repeatCache,
            remote: remote
        )

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .remoteConsent)
        #expect(remote.callCount == 0)
        #expect(viewModel.selectedImageData == normalized.jpegData)

        try await viewModel.confirmRemotePhotoEstimate()

        #expect(remote.callCount == 1)
        #expect(remote.receivedImages == [normalized])
        #expect(viewModel.phase == .review)
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

    @Test("scan as new bypasses repeat lookup but still requires upload consent")
    func scanAsNewRequiresConsentBeforeRemoteCall() async throws {
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
        #expect(remote.callCount == 0)
        #expect(viewModel.phase == .remoteConsent)

        try await viewModel.confirmRemotePhotoEstimate()

        #expect(remote.callCount == 1)
        #expect(remote.receivedImages == [normalized])
        #expect(viewModel.phase == .review)
        #expect(viewModel.mealName == remoteResult.mealName)
        #expect(viewModel.repeatMealSuggestion == nil)
        #expect(viewModel.confirmedMeal().repeatSourceRecordID == nil)
    }

    @Test("manual entry from consent discards the photo without a remote call")
    func manualEntryFromConsentDiscardsPendingPhoto() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let remote = SpyRemoteMealScanService(result: makeScanResult())
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: SpyMealScanRepeatCache(suggestion: nil),
            remote: remote
        )

        try await viewModel.prepareSelectedImage(UIImage())
        viewModel.continueWithManualEntry()

        #expect(remote.callCount == 0)
        #expect(viewModel.phase == .review)
        #expect(viewModel.selectedImage == nil)
        #expect(viewModel.selectedImageData == nil)
        #expect(viewModel.draftItems.count == 1)
        #expect(viewModel.draftItems.first?.detectionSource == "manual")
    }

    @Test("retaking from consent clears the photo and requires a fresh consent step")
    func retakeRequiresFreshConsent() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let remote = SpyRemoteMealScanService(result: makeScanResult())
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: SpyMealScanRepeatCache(suggestion: nil),
            remote: remote
        )

        try await viewModel.prepareSelectedImage(UIImage())
        #expect(viewModel.phase == .remoteConsent)

        viewModel.retake()

        #expect(viewModel.phase == .camera)
        #expect(viewModel.selectedImage == nil)
        #expect(viewModel.selectedImageData == nil)
        #expect(remote.callCount == 0)

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .remoteConsent)
        #expect(remote.callCount == 0)
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
        #expect(remote.callCount == 0)
        #expect(viewModel.phase == .remoteConsent)

        try await viewModel.confirmRemotePhotoEstimate()

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
        try await viewModel.confirmRemotePhotoEstimate()
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
        try await viewModel.confirmRemotePhotoEstimate()

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
        try await viewModel.confirmRemotePhotoEstimate()

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

private struct ThrowingMealScanImageNormalizer: MealScanImageNormalizing {
    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        throw MealScanImageNormalizationError.exceedsMaximumBytes(
            actualBytes: 1_600_000,
            maximumBytes: 1_500_000
        )
    }
}

@MainActor
private final class SpyRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    var quota: MealScanQuota?
    var cacheDisposition: MealScanCacheDisposition
    let throwsOutcomeUnknown: Bool
    private var queuedErrors: [MealScanRemoteError]
    private(set) var callCount = 0
    private(set) var receivedImages: [NormalizedMealScanImage] = []
    private(set) var receivedRequestIDs: [UUID] = []
    var cachedOutcomeResult: MealScanOutcome?
    private(set) var cachedOutcomeCallCount = 0

    init(
        result: MealScanResult,
        quota: MealScanQuota? = nil,
        cacheDisposition: MealScanCacheDisposition = .fresh,
        throwsOutcomeUnknown: Bool = false,
        queuedErrors: [MealScanRemoteError] = []
    ) {
        self.result = result
        self.quota = quota
        self.cacheDisposition = cacheDisposition
        self.throwsOutcomeUnknown = throwsOutcomeUnknown
        self.queuedErrors = queuedErrors
    }

    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        cachedOutcomeCallCount += 1
        return cachedOutcomeResult
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        callCount += 1
        receivedImages.append(normalizedImage)
        receivedRequestIDs.append(requestID)
        if !queuedErrors.isEmpty {
            throw queuedErrors.removeFirst()
        }
        if throwsOutcomeUnknown {
            throw MealScanRemoteError.outcomeUnknown(requestID: requestID)
        }
        return MealScanOutcome(
            result: result,
            quota: quota,
            cacheDisposition: cacheDisposition
        )
    }

    func rewriteQueuedErrorRequestIDs(to requestID: UUID) {
        queuedErrors = queuedErrors.map { error in
            switch error {
            case .outcomeUnknown:
                .outcomeUnknown(requestID: requestID)
            case .requestPending(_, let retryAfterSeconds):
                .requestPending(requestID: requestID, retryAfterSeconds: retryAfterSeconds)
            default:
                error
            }
        }
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
            error: "rolling_scan_quota_exceeded",
            reason: "rolling_quota_exceeded",
            quota: MealScanQuota(
                tier: "paid",
                used: 5,
                limit: 5,
                remaining: 0,
                windowSeconds: 86_400,
                resetAt: "2026-07-14T01:02:03.000Z",
                retryAfterSeconds: 120
            ),
            retryable: nil
        )
    }
}

@MainActor
private struct ViewModelFixedStoreKitEvidenceProvider: MealScanStoreKitEvidenceProviding {
    func signedTransactionJWS() async throws -> String {
        "eyJhbGciOiJFUzI1NiJ9.eyJ0eCI6InRlc3QifQ.signature"
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
