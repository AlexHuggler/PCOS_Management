import Foundation
import SwiftData
import Testing
import UIKit
@testable import PCOS

@Suite("Gemini Meal Scan Remote Integration", .serialized)
@MainActor
struct GeminiMealScanTests {
    @Test("Gemini parser maps local nutrition over fallback values")
    func parserPrefersLocalNutritionForMatchedFoods() async throws {
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
        #expect(item.canonicalFoodId == "rice-white-cooked")
        #expect(item.nutritionSource == .appFixture)
        #expect(item.nutrition.caloriesKcal != 999)
        #expect(Int(item.nutrition.caloriesKcal.rounded()) == 205)
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
        #expect(item.canonicalFoodId == "gemini-fallback-restaurant-special")
        #expect(item.nutritionSource == .userManual)
        #expect(item.confidence == .low)
        #expect(item.warning?.localizedCaseInsensitiveContains("Gemini estimate") == true)
        #expect(result.confidence == .low)
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

    @Test("cache key is stable and includes model schema prompt and image hash")
    func cacheKeyIsStable() throws {
        let imageData = Data("same-image".utf8)

        let first = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            normalizedImageData: imageData,
            localeIdentifier: "en_US",
            appBuild: "15"
        )
        let second = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            normalizedImageData: imageData,
            localeIdentifier: "en_US",
            appBuild: "15"
        )
        let differentPrompt = MealScanResultCache.cacheKey(
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v2",
            normalizedImageData: imageData,
            localeIdentifier: "en_US",
            appBuild: "15"
        )

        #expect(first == second)
        #expect(first != differentPrompt)
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
            configuration: .testDefault
        )

        let first = try await service.scan(image: UIImage(), mealType: .lunch)
        let second = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(first.mealName == "Rice bowl")
        #expect(second.mealName == "Rice bowl")
        #expect(remote.callCount == 1)
        #expect(second.modelVersion.contains("cache"))
    }

    @Test("normalized remote scan uses supplied bytes and hash without renormalizing")
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
            configuration: .testDefault
        )

        _ = try await service.scan(normalizedImage: suppliedImage, mealType: .dinner)

        let request = try #require(remote.receivedRequests.first)
        #expect(request.normalizedImageJPEGData == suppliedImage.jpegData)
        #expect(request.sourceImageHash == suppliedImage.sourceImageHash)
        #expect(request.mealType == .dinner)
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
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: MealScanResultCache(modelContext: container.mainContext),
            imageNormalizer: RecordingMealScanImageNormalizer(),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            appCheckTokenProvider: appCheckTokenProvider
        )

        _ = try await service.scan(normalizedImage: normalizedImage, mealType: .lunch)
        _ = try await service.scan(normalizedImage: normalizedImage, mealType: .lunch)

        #expect(remote.callCount == 1)
        #expect(remote.receivedFirebaseAppCheckTokens == ["limited-use-token-1"])
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 1)
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
            appCheckTokenProvider: appCheckTokenProvider
        )

        _ = try await service.scan(image: UIImage(), mealType: .lunch)
        _ = try await service.scan(image: UIImage(), mealType: .dinner)

        #expect(remote.callCount == 2)
        #expect(remote.receivedFirebaseAppCheckTokens == ["limited-use-token-1", "limited-use-token-2"])
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 2)
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
                    "accessTier": "trial",
                    "used": 3,
                    "limit": 5,
                    "softLimit": 5,
                    "remainingToday": 2,
                    "trialUsed": 11,
                    "trialLimit": 25,
                    "remainingTrial": 14
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
        #expect(estimate.quota?.accessTier == "trial")
        #expect(estimate.quota?.remainingToday == 2)
        #expect(estimate.quota?.remainingTrial == 14)
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
                  "error": "daily_scan_quota_exceeded",
                  "reason": "trial_quota_exceeded",
                  "quota": {
                    "accessTier": "trial",
                    "used": 25,
                    "limit": 5,
                    "softLimit": 5,
                    "remainingToday": 0,
                    "trialUsed": 25,
                    "trialLimit": 25,
                    "remainingTrial": 0
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
            #expect(error.error == "daily_scan_quota_exceeded")
            #expect(error.reason == "trial_quota_exceeded")
            #expect(error.quota?.remainingTrial == 0)
            #expect(error.errorDescription?.localizedCaseInsensitiveContains("photo estimate limit") == true)
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
          "nutrition_fallback": null
        }
      ]
    }
    """
}

@MainActor
private final class CountingRemoteMealScanEstimator: RemoteMealScanEstimating {
    private let responseJSON: String
    var callCount = 0
    var receivedRequests: [RemoteMealScanRequest] = []
    var receivedFirebaseAppCheckTokens: [String?] = []

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        callCount += 1
        receivedRequests.append(request)
        receivedFirebaseAppCheckTokens.append(request.firebaseAppCheckToken)
        return RemoteMealScanEstimate(
            response: try GeminiMealScanResponseParser().parseResponseJSON(responseJSON),
            originalResponseJSON: responseJSON,
            modelID: request.modelID
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
private final class RecordingLimitedUseAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    var limitedUseTokenCallCount = 0

    func limitedUseToken() async throws -> String {
        limitedUseTokenCallCount += 1
        return "limited-use-token-\(limitedUseTokenCallCount)"
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
        modelID: "gemini-2.5-flash-lite",
        schemaVersion: "meal-scan-gemini-v1",
        promptVersion: "meal-scan-prompt-v1",
        localeIdentifier: "en_US",
        appBuild: "15"
    )
}

private extension RemoteMealScanRequest {
    static func testDefault(
        firebaseAppCheckToken: String?
    ) -> RemoteMealScanRequest {
        RemoteMealScanRequest(
            normalizedImageJPEGData: Data("normalized-image".utf8),
            sourceImageHash: MealScanImageNormalizer.sha256Hex(Data("normalized-image".utf8)),
            mealType: .lunch,
            localeIdentifier: "en_US",
            modelID: "gemini-2.5-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            revenueCatAppUserID: "rc-user",
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
