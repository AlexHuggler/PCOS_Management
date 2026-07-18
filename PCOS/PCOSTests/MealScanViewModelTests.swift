import Testing
import SwiftData
import UIKit
@testable import PCOS

@Suite("Meal Scan ViewModel", .serialized)
@MainActor
struct MealScanViewModelTests {
    @Test("meal scanner opens directly to photo choice")
    func mealScannerStartsAtPhotoChoice() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )

        #expect(viewModel.phase == .photoChoice)
        #expect(viewModel.failure == nil)
        #expect(viewModel.scanConsumption == .notUsed)
    }

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
        #expect(viewModel.draftItems.first?.wasPortionAdjusted == true)
        #expect(viewModel.totalNutrition.caloriesKcal > originalCalories)
        #expect(viewModel.hasUserEdits)
    }

    @Test("AI item portion edits scale item nutrition and meal totals")
    func aiItemPortionEditsScaleNutrition() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )
        var result = makeScanResult(mealName: "AI lentil bowl")
        result.detectedItems[0].canonicalFoodId = "gemini-estimate-0"
        result.detectedItems[0].nutritionSource = .aiEstimate
        viewModel.apply(result: result)
        let itemID = try #require(viewModel.draftItems.first?.id)
        let originalGrams = try #require(viewModel.draftItems.first?.estimatedGrams)
        let originalNutrition = try #require(viewModel.draftItems.first?.nutrition)

        viewModel.adjustPortion(id: itemID, byGrams: originalGrams)

        let adjusted = try #require(viewModel.draftItems.first)
        #expect(adjusted.estimatedGrams == originalGrams * 2)
        #expect(adjusted.nutrition.caloriesKcal == originalNutrition.caloriesKcal * 2)
        #expect(adjusted.nutrition.proteinGrams == originalNutrition.proteinGrams * 2)
        #expect(adjusted.nutrition.carbsGrams == originalNutrition.carbsGrams * 2)
        #expect(viewModel.totalNutrition == adjusted.nutrition)
    }

    @Test("inline portion controls use 25 gram steps and stay above zero")
    func inlinePortionAdjustmentUsesClampedTwentyFiveGramSteps() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )
        await viewModel.useMockPhoto()
        let itemID = try #require(viewModel.draftItems.first?.id)
        let originalGrams = try #require(viewModel.draftItems.first?.estimatedGrams)

        viewModel.adjustPortion(id: itemID, byGrams: 25)
        #expect(viewModel.draftItems.first?.estimatedGrams == originalGrams + 25)

        viewModel.updateItem(id: itemID) { $0.estimatedGrams = 10 }
        viewModel.adjustPortion(id: itemID, byGrams: -25)
        #expect(viewModel.draftItems.first?.estimatedGrams == 1)
        #expect(viewModel.hasUserEdits)
    }

    @Test("food editor parses decimal-comma portions and preserves a catalog-item rename")
    func foodEditorUsesLocaleAndKeepsEditedName() throws {
        let grams = MealFoodItemEditView.parseGrams(
            "120,5",
            locale: Locale(identifier: "de_DE")
        )
        #expect(grams == 120.5)

        for localeIdentifier in ["de_DE", "fr_FR", "es_ES"] {
            let locale = Locale(identifier: localeIdentifier)
            let displayed = MealFoodItemEditView.formatGrams(120.5, locale: locale)
            #expect(displayed == "120,5")
            #expect(MealFoodItemEditView.parseGrams(displayed, locale: locale) == 120.5)
        }

        let original = MealFoodItemDraft(
            displayName: "Lentils",
            canonicalFoodId: "lentils-cooked",
            nutritionSource: .usda,
            estimatedGrams: 100,
            nutrition: NutritionSnapshot(caloriesKcal: 116),
            confidence: .high,
            detectionSource: "local",
            portionEstimationMethod: .manualUserInput
        )
        let edited = MealFoodItemEditView.editedItem(
            original,
            displayName: "Lentils with herbs",
            grams: 120.5
        )

        #expect(edited.displayName == "Lentils with herbs")
        #expect(edited.estimatedGrams == 120.5)
        #expect(edited.canonicalFoodId == original.canonicalFoodId)
    }

    @Test("portion-adjusted truth ignores name-only and unchanged saves and survives repeat edits")
    func portionAdjustedTruthTracksOnlyPortionChanges() async throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock()
        )
        try await viewModel.scan(image: UIImage())
        let firstID = try #require(viewModel.draftItems.first?.id)
        let originalGrams = try #require(viewModel.draftItems.first?.estimatedGrams)

        viewModel.updateItem(id: firstID) { item in
            item.displayName = "Renamed only"
        }
        #expect(viewModel.draftItems.first?.wasUserEdited == true)
        #expect(viewModel.draftItems.first?.wasPortionAdjusted == false)

        viewModel.updateItem(id: firstID) { item in
            item.estimatedGrams = originalGrams
        }
        #expect(viewModel.draftItems.first?.wasPortionAdjusted == false)

        viewModel.updateItem(id: firstID) { item in
            item.estimatedGrams = originalGrams + 25
        }
        #expect(viewModel.draftItems.first?.wasPortionAdjusted == true)

        viewModel.updateItem(id: firstID) { item in
            item.displayName = "Renamed after portion edit"
        }
        #expect(viewModel.draftItems.first?.wasPortionAdjusted == true)
    }

    @Test("saved-meal context localizes glucose prefill and updates the exact scan in place")
    func savedMealContextUpdatesExactIdentityInPlace() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: context,
            pipeline: .mock()
        )
        try await viewModel.scan(image: UIImage())
        try await viewModel.save()

        let savedID = try #require(viewModel.savedMealID)
        let beforeMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let beforeFoodItems = try context.fetch(FetchDescriptor<MealScanFoodItem>())
        let draft = try viewModel.savedMealContextDraft()
        #expect(beforeMeals.count == 1)
        #expect(draft.mealID == savedID)
        #expect(draft.mealName == beforeMeals.first?.mealDescription)

        let glucosePrefill = try L10n.withOverrides(
            appLanguage: .fr,
            preferredLanguages: ["fr_FR"]
        ) {
            try viewModel.savedMealGlucosePrefillContext()
        }
        let afterPrefillMeals = try context.fetch(FetchDescriptor<MealEntry>())
        #expect(glucosePrefill.mealContext == "Après \(draft.mealName)")
        #expect(glucosePrefill.readingType == .afterMeal)
        #expect(afterPrefillMeals.count == 1)
        #expect(afterPrefillMeals.first?.id == savedID)
        #expect(afterPrefillMeals.first?.postMealSymptomNote == nil)

        try viewModel.updateSavedMealContext(
            severity: 4,
            note: "Steady energy; digestion felt comfortable."
        )

        let afterMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let afterFoodItems = try context.fetch(FetchDescriptor<MealScanFoodItem>())
        let updatedMeal = try #require(afterMeals.first)
        #expect(afterMeals.count == 1)
        #expect(updatedMeal.id == savedID)
        #expect(updatedMeal.postMealSymptomSeverity == 4)
        #expect(updatedMeal.postMealSymptomNote == "Steady energy; digestion felt comfortable.")
        #expect(updatedMeal.postMealFeedbackTimestamp != nil)
        #expect(afterFoodItems.map(\.id) == beforeFoodItems.map(\.id))
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.kind == .unreadableMeal)
        #expect(viewModel.failure?.consumption == .notUsed)
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure == MealScanFailure(
            kind: .unreadableMeal,
            cause: .invalidImage,
            consumption: .notUsed,
            retryBehavior: .none
        ))
        #expect(viewModel.lastScanResult == nil)
    }

    @Test("an unreadable selected library asset becomes a typed preflight failure")
    func unreadableLibraryAssetBecomesTypedFailure() throws {
        let container = try TestHelpers.makeModelContainer()
        let viewModel = MealScanViewModel(
            mealType: .dinner,
            modelContext: container.mainContext,
            pipeline: .mock()
        )

        viewModel.rejectUnreadableSelectedPhoto()

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure == MealScanFailure(
            kind: .unreadableMeal,
            cause: .invalidImage,
            consumption: .notUsed,
            retryBehavior: .none
        ))
        #expect(viewModel.scanConsumption == .notUsed)
    }

    @Test("ambiguous failure guidance only promises a check action when one exists")
    func ambiguousFailureGuidanceMatchesRecovery() {
        let noRecovery = MealScanFailureView.detail(for: MealScanFailure(
            kind: .ambiguousResult,
            consumption: .notUsed,
            retryBehavior: .none
        ))
        let checkRecovery = MealScanFailureView.detail(for: MealScanFailure(
            kind: .ambiguousResult,
            consumption: .unknown,
            retryBehavior: .checkSameRequest
        ))

        #expect(!noRecovery.localizedCaseInsensitiveContains("check again"))
        #expect(checkRecovery.localizedCaseInsensitiveContains("check again"))
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.kind == .ambiguousResult)
        #expect(viewModel.failure?.consumption == .unknown)
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.kind == .quotaExhausted)
        #expect(viewModel.failure?.consumption == .notUsed)
        #expect(viewModel.lastScanResult == nil)
        #expect(viewModel.draftItems.isEmpty)
        #expect(viewModel.canAddManualFood)
        #expect(viewModel.mealScanQuota?.remaining == 0)
        #expect(viewModel.canStartFreshAnalysis == false)
    }

    @Test("retryable pre-dispatch failure can explicitly retry the same photo and request")
    func retryablePreDispatchFailureRetriesSamePhotoAndRequest() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = RetryableThenSuccessfulRemoteMealScanService(result: makeScanResult())
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.canRetryPendingPhoto)
        #expect(remote.callCount == 1)

        try await viewModel.retryPendingPhoto()

        #expect(viewModel.phase == .review)
        #expect(!viewModel.canRetryPendingPhoto)
        #expect(remote.receivedRequestIDs == [originalRequestID, originalRequestID])
        #expect(remote.receivedImages.count == 2)
        #expect(remote.receivedImages[0] == remote.receivedImages[1])
    }

    @Test("timed retry guidance is routed only to its matching recovery control")
    func timedRetryGuidanceMatchesRecoveryKind() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = TimedRecoveryRemoteMealScanService(result: makeScanResult())
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

        #expect(viewModel.failure?.retryBehavior == .retrySameRequest)
        #expect(viewModel.pendingPhotoRetryAvailableAtLocalText != nil)
        #expect(viewModel.pendingRetryAvailableAtLocalText == nil)

        viewModel.retake()
        try await viewModel.prepareSelectedImage(UIImage())
        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.failure?.retryBehavior == .checkSameRequest)
        #expect(viewModel.pendingRetryAvailableAtLocalText != nil)
        #expect(viewModel.pendingPhotoRetryAvailableAtLocalText == nil)
    }

    @Test("typed cache failure before consent is not swallowed as a cache miss")
    func typedCacheFailureBeforeConsentRemainsNotUsed() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = ThrowingCachedOutcomeRemoteMealScanService(result: makeScanResult())
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            remoteMealScanService: remote,
            featureFlags: .passOneDefaults,
            imageNormalizer: ViewModelStubMealScanImageNormalizer()
        )

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.consumption == .notUsed)
        #expect(viewModel.failure?.retryBehavior == .retrySameRequest)
        #expect(remote.callCount == 0)
    }

    @Test("retrying a transient pre-consent cache failure returns to consent before transport")
    func transientCacheFailureRetryStillRequiresConsent() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = TransientCacheFailureRemoteMealScanService(result: makeScanResult())
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.consumption == .notUsed)
        #expect(remote.cachedOutcomeCallCount == 1)
        #expect(remote.scanCallCount == 0)

        try await viewModel.retryPendingPhoto()

        #expect(viewModel.phase == .remoteConsent)
        #expect(viewModel.failure == nil)
        #expect(viewModel.pendingRequestID == requestID)
        #expect(remote.cachedOutcomeCallCount == 2)
        #expect(remote.scanCallCount == 0)

        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.phase == .review)
        #expect(remote.scanCallCount == 1)
        #expect(remote.receivedRequestIDs == [requestID])
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

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.consumption == .unknown)
        #expect(remote.receivedRequestIDs == [originalRequestID])

        try await viewModel.retryAmbiguousOutcome()
        #expect(viewModel.phase == .failure)
        #expect(remote.receivedRequestIDs == [originalRequestID, originalRequestID])
        #expect(viewModel.canRetryAmbiguousOutcome == false)

        viewModel.requestNewAnalysisAfterAmbiguousOutcome()
        #expect(viewModel.phase == .failure)
        #expect(viewModel.isShowingNewAnalysisConfirmation)
        #expect(viewModel.pendingRequestID == originalRequestID)

        try await viewModel.confirmNewAnalysisAfterAmbiguousOutcome()
        let newRequestID = try #require(viewModel.pendingRequestID)
        #expect(newRequestID != originalRequestID)
        #expect(remote.receivedRequestIDs == [originalRequestID, originalRequestID, newRequestID])
    }

    @Test("same-request recovery never downgrades confirmed scan consumption")
    func sameRequestRecoveryPreservesStrongestConsumptionTruth() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = UsedThenOfflineRemoteMealScanService(result: makeScanResult())
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
        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.failure?.consumption == .used)
        #expect(viewModel.failure?.retryBehavior == .checkSameRequest)

        try await viewModel.retryAmbiguousOutcome()

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.kind == .offlineBeforeDispatch)
        #expect(viewModel.failure?.consumption == .used)
        #expect(viewModel.failure?.retryBehavior == .retrySameRequest)
        #expect(remote.receivedRequestIDs == [requestID, requestID])
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

    @Test("a new photo clears stale source and quota metadata before cache reuse")
    func newPhotoClearsStaleAnalysisMetadata() async throws {
        let container = try TestHelpers.makeModelContainer()
        let staleQuota = MealScanQuota(
            tier: "paid",
            used: 9,
            limit: 10,
            remaining: 1,
            windowSeconds: 86_400,
            resetAt: "2026-07-18T01:02:03.000Z",
            retryAfterSeconds: nil
        )
        let remote = SpyRemoteMealScanService(result: makeScanResult(), quota: staleQuota)
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
        #expect(viewModel.scanConsumption == .used)
        #expect(viewModel.mealScanCacheDisposition == .fresh)
        #expect(viewModel.mealScanQuota == staleQuota)

        viewModel.retake()
        #expect(viewModel.scanConsumption == .notUsed)
        #expect(viewModel.mealScanCacheDisposition == nil)
        #expect(viewModel.mealScanQuota == nil)

        remote.cachedOutcomeResult = MealScanOutcome(
            result: makeScanResult(mealName: "Exact cached meal"),
            quota: nil,
            cacheDisposition: .local
        )
        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .review)
        #expect(viewModel.scanConsumption == .notUsed)
        #expect(viewModel.mealScanCacheDisposition == .local)
        #expect(viewModel.mealScanQuota == nil)
    }

    @Test("same-request recovery is never blocked by a stale zero-quota snapshot")
    func sameRequestRecoveryIgnoresStaleQuotaSnapshot() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = QuotaThenRetryableRemoteMealScanService(result: makeScanResult())
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
        #expect(viewModel.mealScanQuota?.remaining == 0)

        viewModel.retake()
        try await viewModel.prepareSelectedImage(UIImage())
        let requestID = try #require(viewModel.pendingRequestID)
        try await viewModel.confirmRemotePhotoEstimate()

        #expect(viewModel.phase == .failure)
        #expect(viewModel.failure?.retryBehavior == .retrySameRequest)
        #expect(viewModel.canRetryPendingPhoto)

        try await viewModel.retryPendingPhoto()

        #expect(viewModel.phase == .review)
        #expect(remote.receivedRequestIDs.suffix(2) == [requestID, requestID])
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
        #expect(viewModel.phase == .failure)
        #expect(viewModel.isRequestPending == false)

        try await viewModel.retryAmbiguousOutcome()
        #expect(viewModel.phase == .failure)
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

    @Test("exact matching photo reuses reviewed estimate before consent or remote scan")
    func exactMatchingPhotoReusesReviewBeforeConsentOrRemoteScan() async throws {
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

        #expect(viewModel.phase == .review)
        #expect(viewModel.repeatMealSuggestion == nil)
        #expect(viewModel.mealName == suggestion.snapshot.mealName)
        #expect(viewModel.totalNutrition == suggestion.snapshot.nutrition)
        #expect(viewModel.scanConsumption == .notUsed)
        #expect(repeatCache.suggestionCallCount == 1)
        #expect(remote.callCount == 0)
        #expect(remote.cachedOutcomeCallCount == 0)
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
        #expect(viewModel.scanConsumption == .used)
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

        #expect(viewModel.phase == .photoChoice)
        #expect(viewModel.selectedImage == nil)
        #expect(viewModel.selectedImageData == nil)
        #expect(remote.callCount == 0)

        try await viewModel.prepareSelectedImage(UIImage())

        #expect(viewModel.phase == .remoteConsent)
        #expect(remote.callCount == 0)
    }

    @Test("retake clears the previous review before a new photo or manual meal")
    func retakeClearsPriorAnalysisContent() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = SpyRemoteMealScanService(result: makeScanResult())
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
        viewModel.mealType = .dinner
        viewModel.mealName = "Edited prior meal"
        viewModel.applyHiddenIngredientEstimate(.aLittle)

        #expect(viewModel.lastScanResult != nil)
        #expect(viewModel.draftItems.count > 1)
        #expect(viewModel.hiddenIngredientEstimate == .aLittle)
        #expect(viewModel.hasUserEdits)

        viewModel.retake()

        #expect(viewModel.phase == .photoChoice)
        #expect(viewModel.mealType == .lunch)
        #expect(viewModel.mealName == L10n.string("Photo meal estimate", defaultValue: "Photo meal estimate"))
        #expect(viewModel.draftItems.isEmpty)
        #expect(viewModel.totalNutrition == NutritionSnapshot())
        #expect(viewModel.metabolicProfile == nil)
        #expect(viewModel.confidence == .unknown)
        #expect(viewModel.warnings.isEmpty)
        #expect(viewModel.hiddenIngredientEstimate == .no)
        #expect(!viewModel.hasUserEdits)
        #expect(viewModel.lastScanResult == nil)

        viewModel.continueWithManualEntry()

        #expect(viewModel.phase == .review)
        #expect(viewModel.draftItems.count == 1)
        #expect(viewModel.draftItems.first?.detectionSource == "manual")
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
        #expect(viewModel.failure == MealScanFailure(
            kind: .saveFailed,
            cause: .saveFailed,
            consumption: .used,
            retryBehavior: .retrySave
        ))
    }

    @Test("each repeated save failure advances the accessibility announcement token")
    func repeatedSaveFailuresAdvanceAnnouncementToken() async throws {
        let container = try TestHelpers.makeModelContainer()
        let repository = SpyMealLogRepository(saveError: ViewModelRepeatTestError.repositorySaveFailed)
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            mealLogRepository: repository
        )
        try await viewModel.scan(image: UIImage())

        await #expect(throws: ViewModelRepeatTestError.repositorySaveFailed) {
            try await viewModel.save()
        }
        let firstToken = viewModel.failureOccurrence

        await #expect(throws: ViewModelRepeatTestError.repositorySaveFailed) {
            try await viewModel.save()
        }

        #expect(firstToken > 0)
        #expect(viewModel.failureOccurrence > firstToken)
    }

    @Test("save rejects blank names, empty meals, and nonpositive portions before persistence")
    func invalidReviewedMealsNeverReachPersistence() async throws {
        let container = try TestHelpers.makeModelContainer()
        let repository = SpyMealLogRepository()
        let viewModel = MealScanViewModel(
            mealType: .lunch,
            modelContext: container.mainContext,
            pipeline: .mock(),
            mealLogRepository: repository
        )
        try await viewModel.scan(image: UIImage())

        viewModel.mealName = "   "
        do {
            try await viewModel.save()
            Issue.record("A blank meal name must not be persisted.")
        } catch {}
        #expect(repository.savedMeals.isEmpty)
        #expect(viewModel.phase == .review)

        viewModel.mealName = "Reviewed bowl"
        for item in viewModel.draftItems {
            viewModel.removeItem(id: item.id)
        }
        do {
            try await viewModel.save()
            Issue.record("A meal with no foods must not be persisted.")
        } catch {}
        #expect(repository.savedMeals.isEmpty)
        #expect(viewModel.phase == .review)

        viewModel.addManualFood(named: "Rice", grams: 0)
        do {
            try await viewModel.save()
            Issue.record("A meal with a zero portion must not be persisted.")
        } catch {}
        #expect(repository.savedMeals.isEmpty)
        #expect(viewModel.phase == .review)
    }

    @Test("save failure after exact cache reuse preserves edits and reports no scan used")
    func cachedSaveFailureInheritsNotUsedConsumption() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalized = makeNormalizedImage()
        let suggestion = makeRepeatSuggestion()
        let mealRepository = SpyMealLogRepository(saveError: ViewModelRepeatTestError.repositorySaveFailed)
        let viewModel = makeRepeatEnabledViewModel(
            context: container.mainContext,
            normalized: normalized,
            fingerprint: makeFingerprint(for: normalized),
            repeatCache: SpyMealScanRepeatCache(suggestion: suggestion),
            remote: SpyRemoteMealScanService(result: makeScanResult()),
            mealRepository: mealRepository
        )
        try await viewModel.prepareSelectedImage(UIImage())
        viewModel.mealName = "Edited cached bowl"

        await #expect(throws: ViewModelRepeatTestError.repositorySaveFailed) {
            try await viewModel.save()
        }

        #expect(viewModel.phase == .review)
        #expect(viewModel.mealName == "Edited cached bowl")
        #expect(viewModel.failure == MealScanFailure(
            kind: .saveFailed,
            cause: .saveFailed,
            consumption: .notUsed,
            retryBehavior: .retrySave
        ))
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
private final class RetryableThenSuccessfulRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var callCount = 0
    private(set) var receivedImages: [NormalizedMealScanImage] = []
    private(set) var receivedRequestIDs: [UUID] = []

    init(result: MealScanResult) {
        self.result = result
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        callCount += 1
        receivedImages.append(normalizedImage)
        receivedRequestIDs.append(requestID)
        if callCount == 1 {
            throw GeminiMealScanProxyError(
                statusCode: 503,
                error: "meal_scan_unavailable",
                reason: "storekit_verification_unavailable",
                quota: nil,
                retryable: true
            )
        }
        return MealScanOutcome(
            result: result,
            quota: nil,
            cacheDisposition: .fresh
        )
    }
}

@MainActor
private final class TimedRecoveryRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private var callCount = 0

    init(result: MealScanResult) {
        self.result = result
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        callCount += 1
        if callCount == 1 {
            throw GeminiMealScanProxyError(
                statusCode: 503,
                error: "meal_scan_unavailable",
                reason: "app_check_rejected",
                quota: nil,
                retryable: true,
                retryAfterSeconds: 120
            )
        }
        throw MealScanRemoteError.providerTimeoutAfterDispatch(
            requestID: requestID,
            retryAfterSeconds: 120
        )
    }
}

@MainActor
private final class ThrowingCachedOutcomeRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var callCount = 0

    init(result: MealScanResult) {
        self.result = result
    }

    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        throw MealScanFailure(
            kind: .ambiguousResult,
            consumption: .notUsed,
            retryBehavior: .retrySameRequest
        )
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        callCount += 1
        return MealScanOutcome(result: result, quota: nil, source: .fresh)
    }
}

@MainActor
private final class TransientCacheFailureRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var cachedOutcomeCallCount = 0
    private(set) var scanCallCount = 0
    private(set) var receivedRequestIDs: [UUID] = []

    init(result: MealScanResult) {
        self.result = result
    }

    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        cachedOutcomeCallCount += 1
        if cachedOutcomeCallCount == 1 {
            throw MealScanFailure(
                kind: .ambiguousResult,
                cause: .unclassified,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }
        return nil
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        scanCallCount += 1
        receivedRequestIDs.append(requestID)
        return MealScanOutcome(result: result, quota: nil, source: .fresh)
    }
}

@MainActor
private final class UsedThenOfflineRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var receivedRequestIDs: [UUID] = []

    init(result: MealScanResult) {
        self.result = result
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        receivedRequestIDs.append(requestID)
        if receivedRequestIDs.count == 1 {
            throw MealScanRemoteError.providerTimeoutAfterDispatch(
                requestID: requestID,
                retryAfterSeconds: nil
            )
        }
        throw MealScanRemoteError.offlineBeforeDispatch
    }
}

@MainActor
private final class QuotaThenRetryableRemoteMealScanService: RemoteMealScanServing {
    let result: MealScanResult
    private(set) var receivedRequestIDs: [UUID] = []

    init(result: MealScanResult) {
        self.result = result
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        receivedRequestIDs.append(requestID)
        switch receivedRequestIDs.count {
        case 1:
            return MealScanOutcome(
                result: result,
                quota: MealScanQuota(
                    tier: "paid",
                    used: 10,
                    limit: 10,
                    remaining: 0,
                    windowSeconds: 86_400,
                    resetAt: "2099-01-01T12:00:00.000Z",
                    retryAfterSeconds: nil
                ),
                cacheDisposition: .fresh
            )
        case 2:
            throw GeminiMealScanProxyError(
                statusCode: 503,
                error: "meal_scan_unavailable",
                reason: "app_check_rejected",
                quota: nil,
                retryable: true
            )
        default:
            return MealScanOutcome(
                result: result,
                quota: nil,
                cacheDisposition: .fresh
            )
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
