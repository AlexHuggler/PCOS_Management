import Foundation
import SwiftData
import Testing
import UIKit
@testable import PCOS

@Suite("Gemini Meal Scan Remote Integration", .serialized)
@MainActor
struct GeminiMealScanTests {
    @Test("proxy request matches the backend allowlist and carries StoreKit evidence")
    func proxyRequestMatchesBackendAllowlist() async throws {
        let requestID = UUID(uuidString: "4D99A795-D22C-4F50-BBBA-461DA7A4D94C")!
        MockMealScanURLProtocol.handler = { request in
            let body = try request.mealScanBodyData()
            let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(root.keys) == [
                "requestId", "signedTransactionJWS", "mealType", "locale",
                "schemaVersion", "promptVersion", "image"
            ])
            #expect(root["requestId"] as? String == requestID.uuidString.lowercased())
            #expect(root["signedTransactionJWS"] as? String == Self.testSignedTransactionJWS)
            #expect(root["modelId"] == nil)
            #expect(root["revenueCatAppUserId"] == nil)

            let image = try #require(root["image"] as? [String: Any])
            #expect(Set(image.keys) == ["mimeType", "base64", "sha256"])

            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "modelId": "server-selected-model",
                  "cacheHit": false,
                  "quota": {
                    "tier": "subscriber",
                    "used": 8,
                    "limit": 10,
                    "remaining": 2,
                    "windowSeconds": 86400,
                    "resetAt": "2026-07-14T01:02:03.000Z",
                    "retryAfterSeconds": 120
                  },
                  "estimate": \(Self.simpleResponseJSON)
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        let estimate = try await GeminiMealScanProxyClient(
            endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
            urlSession: .mealScanTestSession()
        ).estimateMeal(
            request: RemoteMealScanRequest(
                requestID: requestID,
                signedTransactionJWS: Self.testSignedTransactionJWS,
                normalizedImageJPEGData: Data("normalized-image".utf8),
                sourceImageHash: MealScanImageNormalizer.sha256Hex(Data("normalized-image".utf8)),
                mealType: .lunch,
                localeIdentifier: "en_US",
                schemaVersion: "meal-scan-gemini-v1",
                promptVersion: "meal-scan-prompt-v1",
                firebaseAppCheckToken: "limited-use-token"
            )
        )

        #expect(estimate.quota == MealScanQuota(
            tier: "subscriber",
            used: 8,
            limit: 10,
            remaining: 2,
            windowSeconds: 86_400,
            resetAt: "2026-07-14T01:02:03.000Z",
            retryAfterSeconds: 120
        ))
    }

    @Test("transport failures are an ambiguous outcome for the same request ID")
    func transportFailurePreservesAmbiguousRequestID() async throws {
        let requestID = UUID(uuidString: "D9AC9B94-A0C2-4FF4-8F8E-FF06BD349A84")!
        MockMealScanURLProtocol.handler = { _ in
            throw URLError(.networkConnectionLost)
        }
        defer { MockMealScanURLProtocol.handler = nil }

        await #expect(throws: MealScanRemoteError.outcomeUnknown(requestID: requestID)) {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
        }
    }

    @Test("proxy unknown outcome preserves the same typed request ID")
    func proxyUnknownOutcomePreservesRequestID() async throws {
        let requestID = UUID(uuidString: "D66D6E94-37C7-4F2F-87C7-1C1E9CD209E2")!
        MockMealScanURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 504,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "error": "meal_scan_outcome_unknown",
                  "reason": "provider_timeout",
                  "retryable": false,
                  "idempotency": {"state": "unknown"}
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        await #expect(throws: MealScanRemoteError.outcomeUnknown(requestID: requestID)) {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
        }
    }

    @Test("proxy pending idempotency state preserves the same typed request ID")
    func proxyPendingOutcomePreservesRequestID() async throws {
        let requestID = UUID(uuidString: "A1982D27-4F32-4935-A772-62A9C65A0F7D")!
        MockMealScanURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 409,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "error": "meal_scan_in_progress",
                  "reason": "idempotent_request_pending",
                  "retryable": true,
                  "retryAfterSeconds": 7,
                  "idempotency": {"state": "pending"}
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        await #expect(throws: MealScanRemoteError.requestPending(
            requestID: requestID,
            retryAfterSeconds: 7
        )) {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
        }
    }

    @Test("Production configuration exposes no client model selection")
    func productionConfigurationHasServerOwnedModelSelection() {
        #expect(GeminiRemoteMealScanConfiguration.localCacheNamespace == "meal-scan-proxy-v1")
    }

    @Test("AI estimate provenance is additive and preserves existing persisted source values")
    func aiEstimateProvenancePreservesExistingValues() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(NutritionDataSource.self, from: Data("\"appFixture\"".utf8)) == .appFixture)
        #expect(try decoder.decode(NutritionDataSource.self, from: Data("\"userManual\"".utf8)) == .userManual)
        #expect(try decoder.decode(NutritionDataSource.self, from: Data("\"ai_estimate\"".utf8)) == .aiEstimate)
        #expect(NutritionDataSource.aiEstimate.rawValue == "ai_estimate")
    }

    @Test("Gemini mapper keeps cloud nutrition authoritative over bundled fixtures")
    func mapperKeepsCloudNutritionAuthoritative() async throws {
        let responseJSON = """
        {
          "meal_name": "Rice bowl",
          "confidence": "medium",
          "warnings": [
            {"code": "hidden_oil", "message": "Oil or sauce may not be visible."}
          ],
          "items": [
            {
              "display_name": "Plain rice",
              "canonical_query": "plain rice",
              "estimated_grams": 158,
              "serving_description": "about 1 cup cooked",
              "confidence": "medium",
              "is_mixed_dish": false,
              "nutrition_fallback": {
                "calories_kcal": 999,
                "protein_grams": 1,
                "carbs_grams": 1,
                "fat_grams": 1,
                "fiber_grams": 0,
                "sugar_grams": 0,
                "sodium_mg": 0
              }
            }
          ]
        }
        """
        let response = try GeminiMealScanResponseParser().parseResponseJSON(responseJSON)

        let result = try await GeminiMealScanResultMapper().map(
            response: response,
            originalResponseJSON: responseJSON,
            mealType: .lunch,
            modelID: "gemini-2.5-flash-lite",
            pipelineVersion: "test-pipeline",
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator()
        )

        let item = try #require(result.detectedItems.first)
        #expect(item.canonicalFoodId == "gemini-estimate-plain-rice")
        #expect(item.nutritionSource == .aiEstimate)
        #expect(item.nutrition.caloriesKcal == 999)
        #expect(item.detectionSource == "gemini_cloud_estimate")
        #expect(result.warnings.contains("Oil or sauce may not be visible."))
        #expect(result.originalPredictionJSON == responseJSON)
    }

    @Test("Gemini parser rejects invalid JSON")
    func parserRejectsInvalidJSON() throws {
        #expect(throws: GeminiMealScanParsingError.self) {
            _ = try GeminiMealScanResponseParser().parseResponseJSON("{not-json")
        }
    }

    @Test("Gemini fallback nutrition remains low confidence when no local match exists")
    func fallbackNutritionIsLowConfidence() async throws {
        let responseJSON = """
        {
          "meal_name": "Mystery bowl",
          "confidence": "high",
          "warnings": [],
          "items": [
            {
              "display_name": "Restaurant special",
              "canonical_query": "not in local fixtures",
              "estimated_grams": 220,
              "serving_description": "one bowl",
              "confidence": "high",
              "is_mixed_dish": true,
              "nutrition_fallback": {
                "calories_kcal": 420,
                "protein_grams": 18,
                "carbs_grams": 54,
                "fat_grams": 14,
                "fiber_grams": 6,
                "sugar_grams": 8,
                "sodium_mg": 680
              }
            }
          ]
        }
        """
        let response = try GeminiMealScanResponseParser().parseResponseJSON(responseJSON)

        let result = try await GeminiMealScanResultMapper().map(
            response: response,
            originalResponseJSON: responseJSON,
            mealType: .dinner,
            modelID: "gemini-2.5-flash-lite",
            pipelineVersion: "test-pipeline",
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator()
        )

        let item = try #require(result.detectedItems.first)
        #expect(item.canonicalFoodId == "gemini-estimate-restaurant-special")
        #expect(item.nutritionSource == .aiEstimate)
        #expect(item.confidence == .low)
        #expect(item.warning?.localizedCaseInsensitiveContains("Gemini estimate") == true)
        #expect(result.confidence == .low)
    }

    @Test("Gemini mapper rejects an item without cloud nutrition")
    func mapperRejectsMissingCloudNutrition() async throws {
        let responseJSON = """
        {
          "meal_name": "Unknown plate",
          "confidence": "medium",
          "warnings": [],
          "items": [
            {
              "display_name": "Unknown food",
              "canonical_query": "unknown food",
              "estimated_grams": 100,
              "serving_description": null,
              "confidence": "medium",
              "is_mixed_dish": false,
              "nutrition_fallback": null
            }
          ]
        }
        """
        let response = try GeminiMealScanResponseParser().parseResponseJSON(responseJSON)

        await #expect(throws: GeminiMealScanMappingError.missingNutritionEstimate(
            itemName: "Unknown food"
        )) {
            _ = try await GeminiMealScanResultMapper().map(
                response: response,
                originalResponseJSON: responseJSON,
                mealType: .lunch,
                modelID: "server-selected-model",
                pipelineVersion: "test-pipeline",
                nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
                calculator: MealNutritionCalculator()
            )
        }
    }

    @Test("image normalizer strips metadata and caps long edge near 960 pixels")
    func imageNormalizerCapsLongEdge() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 1_200)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_200))
        }

        let normalized = try MealScanImageNormalizer(maxLongEdge: 960).normalizeJPEGData(from: source)
        let decoded = try #require(UIImage(data: normalized.jpegData))

        #expect(max(decoded.size.width, decoded.size.height) <= 961)
        #expect(normalized.jpegData.count < 800_000)
        #expect(normalized.sourceImageHash == MealScanImageNormalizer.sha256Hex(normalized.jpegData))
    }

    @Test("cache key is stable and includes every prompt-affecting input")
    func cacheKeyIsStable() throws {
        let imageData = Data("same-image".utf8)

        let first = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            normalizedImageData: imageData,
            mealType: .lunch,
            localeIdentifier: "en_US",
            appBuild: "15"
        )
        let second = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            normalizedImageData: imageData,
            mealType: .lunch,
            localeIdentifier: "en_US",
            appBuild: "15"
        )
        let differentPrompt = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v2",
            normalizedImageData: imageData,
            mealType: .lunch,
            localeIdentifier: "en_US",
            appBuild: "15"
        )
        let differentMealType = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            normalizedImageData: imageData,
            mealType: .dinner,
            localeIdentifier: "en_US",
            appBuild: "15"
        )

        #expect(first == second)
        #expect(first != differentPrompt)
        #expect(first != differentMealType)
        #expect(first.count == 64)
    }

    @Test("cached remote estimator avoids repeat proxy calls")
    func cachedRemoteEstimatorAvoidsRepeatProxyCalls() async throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: MealScanResultCache(modelContext: context),
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let first = try await service.scan(image: UIImage(), mealType: .lunch)
        let second = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(first.result.mealName == "Rice bowl")
        #expect(second.result.mealName == "Rice bowl")
        #expect(remote.callCount == 1)
        #expect(first.cacheDisposition == .fresh)
        #expect(second.cacheDisposition == .local)
        #expect(second.result.modelVersion.contains("cache"))
    }

    @Test("same photo with a different meal type does not reuse a cached estimate")
    func mealTypeSeparatesCachedRemoteEstimates() async throws {
        let container = try TestHelpers.makeModelContainer()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: MealScanResultCache(modelContext: container.mainContext),
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        _ = try await service.scan(image: UIImage(), mealType: .lunch)
        _ = try await service.scan(image: UIImage(), mealType: .dinner)

        #expect(remote.callCount == 2)
    }

    @Test("normalized remote scan uses supplied bytes and recomputes their exact hash")
    func normalizedRemoteScanUsesSuppliedImage() async throws {
        let suppliedImage = NormalizedMealScanImage(
            jpegData: Data("caller-normalized-image".utf8),
            sourceImageHash: "caller-supplied-hash",
            width: 320,
            height: 240
        )
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let imageNormalizer = RecordingMealScanImageNormalizer()
        let service: any RemoteMealScanServing = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: imageNormalizer,
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let requestID = UUID()
        _ = try await service.scan(
            normalizedImage: suppliedImage,
            mealType: .dinner,
            requestID: requestID
        )

        let request = try #require(remote.receivedRequests.first)
        #expect(request.normalizedImageJPEGData == suppliedImage.jpegData)
        #expect(request.sourceImageHash == MealScanImageNormalizer.sha256Hex(suppliedImage.jpegData))
        #expect(request.mealType == .dinner)
        #expect(request.requestID == requestID)
        #expect(request.signedTransactionJWS == Self.testSignedTransactionJWS)
        #expect(imageNormalizer.callCount == 0)
    }

    @Test("normalized remote scan obtains App Check only after a cache miss")
    func normalizedRemoteScanObtainsAppCheckOnlyAfterCacheMiss() async throws {
        let container = try TestHelpers.makeModelContainer()
        let normalizedImage = NormalizedMealScanImage(
            jpegData: Data("caller-normalized-image".utf8),
            sourceImageHash: "caller-supplied-hash",
            width: 320,
            height: 240
        )
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let evidenceProvider = RecordingStoreKitEvidenceProvider()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: MealScanResultCache(modelContext: container.mainContext),
            imageNormalizer: RecordingMealScanImageNormalizer(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )

        _ = try await service.scan(normalizedImage: normalizedImage, mealType: .lunch, requestID: UUID())
        _ = try await service.scan(normalizedImage: normalizedImage, mealType: .lunch, requestID: UUID())

        #expect(remote.callCount == 1)
        #expect(remote.receivedFirebaseAppCheckTokens == ["limited-use-token-1"])
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 1)
        #expect(evidenceProvider.callCount == 1)
    }

    @Test("each uncached remote scan obtains one limited-use App Check token")
    func uncachedRemoteScansObtainOneLimitedUseAppCheckTokenEach() async throws {
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        _ = try await service.scan(image: UIImage(), mealType: .lunch)
        _ = try await service.scan(image: UIImage(), mealType: .dinner)

        #expect(remote.callCount == 2)
        #expect(remote.receivedFirebaseAppCheckTokens == ["limited-use-token-1", "limited-use-token-2"])
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 2)
    }

    @Test("same request retry refetches verified StoreKit evidence and refreshes App Check")
    func sameRequestRetryRefetchesEvidenceAndRefreshesAppCheck() async throws {
        let remote = AmbiguousThenSuccessRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let evidenceProvider = RecordingStoreKitEvidenceProvider()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )
        let requestID = UUID()

        await #expect(throws: MealScanRemoteError.outcomeUnknown(requestID: requestID)) {
            _ = try await service.scan(image: UIImage(), mealType: .lunch, requestID: requestID)
        }
        _ = try await service.scan(image: UIImage(), mealType: .lunch, requestID: requestID)

        #expect(remote.receivedRequests.map(\.requestID) == [requestID, requestID])
        #expect(remote.receivedRequests.map(\.signedTransactionJWS) == [
            "header.evidence-1.signature", "header.evidence-2.signature"
        ])
        #expect(remote.receivedFirebaseAppCheckTokens == ["limited-use-token-1", "limited-use-token-2"])
        #expect(evidenceProvider.callCount == 2)

        _ = try await service.scan(image: UIImage(), mealType: .lunch, requestID: requestID)
        #expect(remote.receivedRequests.last?.signedTransactionJWS == "header.evidence-3.signature")
        #expect(evidenceProvider.callCount == 3)
    }

    @Test("StoreKit evidence failure prevents App Check and proxy dispatch")
    func storeKitEvidenceFailureFailsClosedBeforeDispatch() async throws {
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: ThrowingStoreKitEvidenceProvider()
        )

        await #expect(throws: MealScanRemoteError.subscriptionEvidenceUnavailable) {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
        }
        #expect(remote.callCount == 0)
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 0)
    }

    @Test("server cache maps to a server cache outcome")
    func serverCacheMapsToServerDisposition() async throws {
        let remote = CountingRemoteMealScanEstimator(
            responseJSON: Self.simpleResponseJSON,
            cacheHit: true
        )
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(outcome.cacheDisposition == .server)
    }

    @Test("local cache write failure preserves a valid paid outcome")
    func cacheWriteFailurePreservesPaidOutcome() async throws {
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: ThrowingWriteMealScanResultCache(),
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(outcome.cacheDisposition == .fresh)
        #expect(outcome.quota?.remaining == 9)
        #expect(outcome.result.mealName == "Rice bowl")
        #expect(remote.callCount == 1)
    }

    @Test("proxy rejects an oversized canonical JPEG before transport")
    func proxyRejectsOversizedCanonicalJPEG() async throws {
        var request = RemoteMealScanRequest.testDefault()
        request.normalizedImageJPEGData = Data(
            repeating: 0x01,
            count: GeminiMealScanProxyClient.maximumImageBytes + 1
        )

        await #expect(throws: MealScanRemoteError.imageTooLarge(
            actualBytes: GeminiMealScanProxyClient.maximumImageBytes + 1,
            maximumBytes: GeminiMealScanProxyClient.maximumImageBytes
        )) {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: request)
        }
    }

    @Test("proxy rejects an encoded request body over 2.2 MB before transport")
    func proxyRejectsOversizedRequestBody() async throws {
        var request = RemoteMealScanRequest.testDefault()
        request.normalizedImageJPEGData = Data(
            repeating: 0x01,
            count: GeminiMealScanProxyClient.maximumImageBytes
        )
        request.signedTransactionJWS = "header." + String(repeating: "x", count: 300_000) + ".signature"

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: request)
            Issue.record("Expected the body-size guard to reject the request")
        } catch let error as MealScanRemoteError {
            guard case .requestBodyTooLarge(let actualBytes, let maximumBytes) = error else {
                Issue.record("Expected requestBodyTooLarge, received \(error)")
                return
            }
            #expect(actualBytes > maximumBytes)
            #expect(maximumBytes == 2_200_000)
        }
    }

    @Test("proxy client exposes quota and usage metadata on success")
    func proxyClientMapsQuotaAndUsageMetadata() async throws {
        MockMealScanURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "limited-use-token")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "modelId": "gemini-2.5-flash-lite",
                  "cacheHit": false,
                  "usage": {
                    "inputTokens": 2448,
                    "outputTokens": 750,
                    "totalTokens": 3198,
                    "estimatedCostUSD": 0.0005448
                  },
                  "quota": {
                    "tier": "subscriber",
                    "used": 8,
                    "limit": 10,
                    "remaining": 2,
                    "windowSeconds": 86400,
                    "resetAt": "2026-07-14T01:02:03.000Z",
                    "retryAfterSeconds": 120
                  },
                  "estimate": \(Self.simpleResponseJSON)
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        let estimate = try await GeminiMealScanProxyClient(
            endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
            urlSession: .mealScanTestSession()
        ).estimateMeal(request: .testDefault(firebaseAppCheckToken: "limited-use-token"))

        #expect(estimate.modelID == "gemini-2.5-flash-lite")
        #expect(estimate.cacheHit == false)
        #expect(estimate.usage?.inputTokens == 2448)
        #expect(estimate.usage?.outputTokens == 750)
        #expect(estimate.usage?.estimatedCostUSD == 0.0005448)
        #expect(estimate.quota.tier == "subscriber")
        #expect(estimate.quota.remaining == 2)
        #expect(estimate.quota.windowSeconds == 86_400)
    }

    @Test("proxy client sends its Firebase App Check token in the proxy contract header")
    func proxyClientSendsFirebaseAppCheckHeader() async throws {
        MockMealScanURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "x-cyclebalance-app-integrity") == nil)
            #expect(request.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "limited-use-token")
            #expect(request.value(forHTTPHeaderField: "x-cyclebalance-app-attest-key-id") == nil)
            #expect(request.value(forHTTPHeaderField: "x-cyclebalance-app-attest-attestation") == nil)
            #expect(request.value(forHTTPHeaderField: "x-cyclebalance-app-attest-assertion") == nil)
            #expect(request.value(forHTTPHeaderField: "x-cyclebalance-app-attest-challenge") == nil)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "modelId": "gemini-2.5-flash-lite",
                  "quota": {
                    "tier": "paid",
                    "used": 1,
                    "limit": 10,
                    "remaining": 9,
                    "windowSeconds": 86400,
                    "resetAt": null,
                    "retryAfterSeconds": null
                  },
                  "estimate": \(Self.simpleResponseJSON)
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        _ = try await GeminiMealScanProxyClient(
            endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
            urlSession: .mealScanTestSession()
        ).estimateMeal(
            request: .testDefault(
                firebaseAppCheckToken: "limited-use-token"
            )
        )
    }

    @Test("proxy client throws user safe quota errors")
    func proxyClientThrowsUserSafeQuotaErrors() async throws {
        MockMealScanURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "error": "rolling_scan_quota_exceeded",
                  "reason": "rolling_window_exceeded",
                  "quota": {
                    "tier": "subscriber",
                    "used": 10,
                    "limit": 10,
                    "remaining": 0,
                    "windowSeconds": 86400,
                    "resetAt": "2026-07-14T01:02:03.000Z",
                    "retryAfterSeconds": 120
                  }
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(firebaseAppCheckToken: "limited-use-token"))
            #expect(Bool(false), "Expected quota error")
        } catch let error as GeminiMealScanProxyError {
            #expect(error.statusCode == 429)
            #expect(error.error == "rolling_scan_quota_exceeded")
            #expect(error.reason == "rolling_window_exceeded")
            #expect(error.quota?.remaining == 0)
            #expect(error.errorDescription?.localizedCaseInsensitiveContains("rolling 24-hour") == true)
        }
    }

    private static let simpleResponseJSON = """
    {
      "meal_name": "Rice bowl",
      "confidence": "medium",
      "warnings": [],
      "items": [
        {
          "display_name": "Plain rice",
          "canonical_query": "plain rice",
          "estimated_grams": 158,
          "serving_description": "about 1 cup cooked",
          "confidence": "medium",
          "is_mixed_dish": false,
          "nutrition_fallback": {
            "calories_kcal": 205,
            "protein_grams": 4.2,
            "carbs_grams": 44.5,
            "fat_grams": 0.4,
            "fiber_grams": 0.6,
            "sugar_grams": 0.1,
            "sodium_mg": 2
          }
        }
      ]
    }
    """

    fileprivate static let testSignedTransactionJWS = "eyJhbGciOiJFUzI1NiJ9.eyJ0eCI6InRlc3QifQ.signature"
}

@MainActor
private final class CountingRemoteMealScanEstimator: RemoteMealScanEstimating {
    private let responseJSON: String
    private let cacheHit: Bool
    var callCount = 0
    var receivedRequests: [RemoteMealScanRequest] = []
    var receivedFirebaseAppCheckTokens: [String?] = []

    init(responseJSON: String, cacheHit: Bool = false) {
        self.responseJSON = responseJSON
        self.cacheHit = cacheHit
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        callCount += 1
        receivedRequests.append(request)
        receivedFirebaseAppCheckTokens.append(request.firebaseAppCheckToken)
        return RemoteMealScanEstimate(
            response: try GeminiMealScanResponseParser().parseResponseJSON(responseJSON),
            originalResponseJSON: responseJSON,
            modelID: "server-selected-model",
            quota: MealScanQuota(
                tier: "paid",
                used: 1,
                limit: 10,
                remaining: 9,
                windowSeconds: 86_400,
                resetAt: nil,
                retryAfterSeconds: nil
            ),
            cacheHit: cacheHit
        )
    }
}

@MainActor
private final class AmbiguousThenSuccessRemoteMealScanEstimator: RemoteMealScanEstimating {
    private let responseJSON: String
    var receivedRequests: [RemoteMealScanRequest] = []
    var receivedFirebaseAppCheckTokens: [String?] = []

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        receivedRequests.append(request)
        receivedFirebaseAppCheckTokens.append(request.firebaseAppCheckToken)
        if receivedRequests.count == 1 {
            throw MealScanRemoteError.outcomeUnknown(requestID: request.requestID)
        }
        return RemoteMealScanEstimate(
            response: try GeminiMealScanResponseParser().parseResponseJSON(responseJSON),
            originalResponseJSON: responseJSON,
            modelID: "server-selected-model",
            quota: MealScanQuota(
                tier: "paid",
                used: 1,
                limit: 10,
                remaining: 9,
                windowSeconds: 86_400,
                resetAt: nil,
                retryAfterSeconds: nil
            )
        )
    }
}

private final class RecordingMealScanImageNormalizer: MealScanImageNormalizing, @unchecked Sendable {
    private(set) var callCount = 0

    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        callCount += 1
        return NormalizedMealScanImage(
            jpegData: Data("unexpected-renormalized-image".utf8),
            sourceImageHash: "unexpected-renormalized-hash",
            width: 1,
            height: 1
        )
    }
}

@MainActor
private final class ThrowingWriteMealScanResultCache: MealScanResultCaching {
    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String? {
        nil
    }

    func saveResponseJSON(
        _ responseJSON: String,
        cacheKey: String,
        modelID: String,
        schemaVersion: String,
        promptVersion: String,
        confidenceScore: Double,
        sourceImageHash: String,
        now: Date
    ) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

@MainActor
private final class RecordingLimitedUseAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    var limitedUseTokenCallCount = 0

    func limitedUseToken() async throws -> String {
        limitedUseTokenCallCount += 1
        return "limited-use-token-\(limitedUseTokenCallCount)"
    }
}

@MainActor
private struct FixedStoreKitEvidenceProvider: MealScanStoreKitEvidenceProviding {
    func signedTransactionJWS() async throws -> String {
        GeminiMealScanTests.testSignedTransactionJWS
    }
}

@MainActor
private final class RecordingStoreKitEvidenceProvider: MealScanStoreKitEvidenceProviding {
    private(set) var callCount = 0

    func signedTransactionJWS() async throws -> String {
        callCount += 1
        return "header.evidence-\(callCount).signature"
    }
}

@MainActor
private struct ThrowingStoreKitEvidenceProvider: MealScanStoreKitEvidenceProviding {
    func signedTransactionJWS() async throws -> String {
        throw MealScanStoreKitEvidenceError.noVerifiedActiveSubscription
    }
}

private struct StubMealScanImageNormalizer: MealScanImageNormalizing {
    let jpegData: Data

    func normalizeJPEGData(from image: UIImage) throws -> NormalizedMealScanImage {
        NormalizedMealScanImage(
            jpegData: jpegData,
            sourceImageHash: MealScanImageNormalizer.sha256Hex(jpegData),
            width: 10,
            height: 10
        )
    }
}

private extension GeminiRemoteMealScanConfiguration {
    static let testDefault = GeminiRemoteMealScanConfiguration(
        schemaVersion: "meal-scan-gemini-v1",
        promptVersion: "meal-scan-prompt-v1",
        localeIdentifier: "en_US",
        appBuild: "15"
    )
}

private extension RemoteMealScanRequest {
    static func testDefault(
        requestID: UUID = UUID(),
        firebaseAppCheckToken: String? = nil
    ) -> RemoteMealScanRequest {
        RemoteMealScanRequest(
            requestID: requestID,
            signedTransactionJWS: "eyJhbGciOiJFUzI1NiJ9.eyJ0eCI6InRlc3QifQ.signature",
            normalizedImageJPEGData: Data("normalized-image".utf8),
            sourceImageHash: MealScanImageNormalizer.sha256Hex(Data("normalized-image".utf8)),
            mealType: .lunch,
            localeIdentifier: "en_US",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            firebaseAppCheckToken: firebaseAppCheckToken
        )
    }
}

private final class MockMealScanURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    static func mealScanTestSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockMealScanURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    func mealScanBodyData() throws -> Data {
        if let httpBody {
            return httpBody
        }
        let stream = try #require(httpBodyStream)
        stream.open()
        defer { stream.close() }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if count == 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}
