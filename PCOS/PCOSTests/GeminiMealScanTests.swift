import Foundation
import SwiftData
import Testing
import UIKit
@testable import PCOS

@Suite("Gemini Meal Scan Remote Integration", .serialized)
@MainActor
struct GeminiMealScanTests {
    @Test("meal scan failure taxonomy is exact and carries recovery metadata")
    func mealScanFailureTaxonomyIsExact() {
        #expect(MealScanFailureKind.allCases == [
            .serviceDisabled,
            .offlineBeforeDispatch,
            .connectionInterruptedAfterDispatch,
            .appIntegrity,
            .entitlement,
            .quotaExhausted,
            .unreadableMeal,
            .ambiguousResult,
            .saveFailed,
        ])
        #expect(MealScanConsumptionState.allCases == [.notUsed, .used, .unknown])
        #expect(MealScanConsumptionState.notUsed.preservingStrongestTruth(with: .unknown) == .unknown)
        #expect(MealScanConsumptionState.unknown.preservingStrongestTruth(with: .used) == .used)
        #expect(MealScanConsumptionState.used.preservingStrongestTruth(with: .notUsed) == .used)
        #expect(MealScanRetryBehavior.allCases == [.none, .retrySameRequest, .checkSameRequest, .retrySave])
        #expect(MealScanFailureCause.allCases == [
            .featureDisabled,
            .serviceControlUnavailable,
            .budgetDispatchDisabled,
            .offline,
            .transportOutcomeUnknown,
            .appIntegrityRejected,
            .appIntegrityEvidenceUnavailable,
            .entitlementRejected,
            .entitlementEvidenceUnavailable,
            .requestRateLimited,
            .quotaExhausted,
            .invalidImage,
            .invalidRequest,
            .idempotencyConflict,
            .requestPending,
            .serverOutcomeUnknown,
            .providerResponseInvalid,
            .providerRequestFailed,
            .providerTimeout,
            .providerDispatchOutcomeUnknown,
            .saveFailed,
            .unclassified,
        ])
        #expect(MealScanAnalysisSource.allCases == [
            .exactPrevious,
            .localCache,
            .serverCache,
            .fresh,
        ])

        let quota = MealScanQuota(
            tier: "paid",
            used: 10,
            limit: 10,
            remaining: 0,
            windowSeconds: 86_400,
            resetAt: "2026-07-17T01:02:03.000Z",
            retryAfterSeconds: 120
        )
        #expect(MealScanFailure(
            kind: .quotaExhausted,
            cause: .quotaExhausted,
            consumption: .notUsed,
            recovery: .none,
            quota: quota
        ) == MealScanFailure(
            kind: .quotaExhausted,
            cause: .quotaExhausted,
            consumption: .notUsed,
            retryBehavior: .none,
            quota: quota,
            retryAfterSeconds: 120
        ))

        let pending = MealScanFailure(
            kind: .ambiguousResult,
            cause: .requestPending,
            consumption: .unknown,
            recovery: .checkSameRequest(afterSeconds: 9)
        )
        #expect(pending.retryBehavior == .checkSameRequest)
        #expect(pending.retryAfterSeconds == 9)
        #expect(pending.recovery == .checkSameRequest(afterSeconds: 9))
    }

    @Test("analysis source is the only source of successful consumption truth")
    func analysisSourceOwnsSuccessfulConsumptionTruth() {
        let result = Self.sourceTestResult
        let exactPrevious = MealScanOutcome(result: result, quota: nil, source: .exactPrevious)
        let local = MealScanOutcome(result: result, quota: nil, source: .localCache)
        let server = MealScanOutcome(result: result, quota: nil, source: .serverCache)
        let fresh = MealScanOutcome(result: result, quota: nil, source: .fresh)

        #expect(exactPrevious.consumption == .notUsed)
        #expect(local.consumption == .notUsed)
        #expect(server.consumption == .notUsed)
        #expect(fresh.consumption == .used)
        #expect(exactPrevious.cacheDisposition == .local)
        #expect(local.cacheDisposition == .local)
        #expect(server.cacheDisposition == .server)
        #expect(fresh.cacheDisposition == .fresh)

        let contradictoryLegacyOutcome = MealScanOutcome(
            result: result,
            quota: nil,
            cacheDisposition: .fresh,
            consumption: .notUsed
        )
        #expect(contradictoryLegacyOutcome.source == .fresh)
        #expect(contradictoryLegacyOutcome.consumption == .used)
    }

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

    @Test("proxy requires nonempty App Check evidence before URL transport")
    func proxyRequiresNonemptyAppCheckBeforeTransport() async throws {
        var transportCallCount = 0
        MockMealScanURLProtocol.handler = { request in
            transportCallCount += 1
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data()
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        let client = GeminiMealScanProxyClient(
            endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
            urlSession: .mealScanTestSession()
        )
        for token in [nil, "", " \n\t"] as [String?] {
            await #expect(throws: MealScanRemoteError.appIntegrityEvidenceUnavailable) {
                _ = try await client.estimateMeal(
                    request: .testDefault(firebaseAppCheckToken: token)
                )
            }
        }
        #expect(transportCallCount == 0)
    }

    @Test("transport failures are an ambiguous outcome for the same request ID")
    func transportFailurePreservesAmbiguousRequestID() async throws {
        let requestID = UUID(uuidString: "D9AC9B94-A0C2-4FF4-8F8E-FF06BD349A84")!
        MockMealScanURLProtocol.handler = { _ in
            throw URLError(.networkConnectionLost)
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected the transport loss to preserve an unknown outcome")
        } catch let error as MealScanRemoteError {
            guard case .outcomeUnknown(let actualRequestID) = error else {
                Issue.record("Expected outcomeUnknown, received \(error)")
                return
            }
            #expect(actualRequestID == requestID)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .transportOutcomeUnknown,
                consumption: .unknown,
                retryBehavior: .checkSameRequest
            ))
        }
    }

    @Test("definite pre-dispatch URL failures report offline without using a scan")
    func definitePreDispatchURLFailuresMapToOffline() async throws {
        for code in [
            URLError.notConnectedToInternet,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
        ] {
            MockMealScanURLProtocol.handler = { _ in
                throw URLError(code)
            }

            do {
                _ = try await GeminiMealScanProxyClient(
                    endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                    urlSession: .mealScanTestSession()
                ).estimateMeal(request: .testDefault())
                Issue.record("Expected \(code) to remain a definite pre-dispatch failure")
            } catch let error as MealScanRemoteError {
                #expect(error == .offlineBeforeDispatch)
                #expect(error.mealScanFailure == MealScanFailure(
                    kind: .offlineBeforeDispatch,
                    cause: .offline,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                ))
            }
        }
        MockMealScanURLProtocol.handler = nil
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

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected a confirmed provider timeout")
        } catch let error as MealScanRemoteError {
            guard case .providerTimeoutAfterDispatch(
                let actualRequestID,
                let retryAfterSeconds
            ) = error else {
                Issue.record("Expected providerTimeoutAfterDispatch, received \(error)")
                return
            }
            #expect(actualRequestID == requestID)
            #expect(retryAfterSeconds == nil)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .connectionInterruptedAfterDispatch,
                cause: .providerTimeout,
                consumption: .used,
                retryBehavior: .checkSameRequest
            ))
        }
    }

    @Test("server idempotency unknown is used and checks the same request")
    func serverIdempotencyUnknownMapsToUsedRecovery() async throws {
        let requestID = UUID(uuidString: "7B42E5CA-1866-4DB9-AE82-3D19D327B9F8")!
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
                  "error": "meal_scan_outcome_unknown",
                  "reason": "idempotency_state_unknown",
                  "retryable": false,
                  "retryAfterSeconds": 9,
                  "idempotency": {"state": "unknown"}
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected an unknown server idempotency state")
        } catch let error as MealScanRemoteError {
            guard case .serverOutcomeUnknown(
                let actualRequestID,
                let retryAfterSeconds
            ) = error else {
                Issue.record("Expected serverOutcomeUnknown, received \(error)")
                return
            }
            #expect(actualRequestID == requestID)
            #expect(retryAfterSeconds == 9)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .serverOutcomeUnknown,
                consumption: .used,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: 9
            ))
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

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected a pending idempotent request")
        } catch let error as MealScanRemoteError {
            #expect(error == .requestPending(requestID: requestID, retryAfterSeconds: 7))
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .requestPending,
                consumption: .unknown,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: 7
            ))
        }
    }

    @Test("principal dispatch contention retries the same request and reports no scan used")
    func principalDispatchContentionMapsToTimedRetryWithoutConsumption() async throws {
        let requestID = UUID(uuidString: "FD5A8503-B1FC-4A71-B81C-4F2BBE4B0F29")!
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
                  "reason": "principal_dispatch_in_progress",
                  "retryable": true,
                  "retryAfterSeconds": 11,
                  "idempotency": {"state": "pending"}
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected principal dispatch contention")
        } catch let error as MealScanRemoteError {
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .serviceDisabled,
                cause: .requestPending,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest,
                retryAfterSeconds: 11
            ))
        }
    }

    @Test("invalid success response leaves consumption unknown for the same request")
    func invalidSuccessResponseMapsToUnknownTransportFailure() async throws {
        let requestID = UUID(uuidString: "E82AD61C-4566-4E99-B57F-76D378520581")!
        MockMealScanURLProtocol.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("not-json".utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected an unknown response outcome")
        } catch let error as MealScanRemoteError {
            #expect(error == .outcomeUnknown(requestID: requestID))
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .transportOutcomeUnknown,
                consumption: .unknown,
                retryBehavior: .checkSameRequest
            ))
        }
    }

    @Test("undecodable non-success response stays unknown for the same request")
    func undecodableNonSuccessResponsePreservesUnknownRequestID() async throws {
        let requestID = UUID(uuidString: "D7FFDB45-E2F0-4DBF-9150-D33E3C208048")!
        MockMealScanURLProtocol.handler = { request in
            let body = try request.mealScanBodyData()
            let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(root["requestId"] as? String == requestID.uuidString.lowercased())
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 502,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html"]
                )!,
                Data("<html>bad gateway</html>".utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected an undecodable post-dispatch response to remain unknown")
        } catch let error as MealScanRemoteError {
            #expect(error == .outcomeUnknown(requestID: requestID))
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .transportOutcomeUnknown,
                consumption: .unknown,
                retryBehavior: .checkSameRequest
            ))
        } catch {
            Issue.record("Expected typed outcomeUnknown for the same request, received \(error)")
        }
    }

    @Test("provider dispatch unknown remains distinct through the proxy client")
    func providerDispatchUnknownRemainsDistinctThroughProxyClient() async throws {
        let requestID = UUID(uuidString: "20E9B584-6D29-4F67-B6E7-806D155D6C89")!
        MockMealScanURLProtocol.handler = { request in
            let body = try request.mealScanBodyData()
            let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(root["requestId"] as? String == requestID.uuidString.lowercased())
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "error": "meal_scan_outcome_unknown",
                  "reason": "provider_dispatch_outcome_unknown",
                  "retryable": false,
                  "retryAfterSeconds": 13,
                  "idempotency": {"state": "unknown"}
                }
                """.utf8)
            )
        }
        defer { MockMealScanURLProtocol.handler = nil }

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: .testDefault(requestID: requestID))
            Issue.record("Expected a distinct provider dispatch outcome")
        } catch let error as any MealScanFailureProviding {
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .providerDispatchOutcomeUnknown,
                consumption: .used,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: 13
            ))
        } catch {
            Issue.record("Expected a typed provider dispatch outcome, received \(error)")
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
        #expect(item.warning == nil)
        #expect(result.confidence == .low)
        #expect(result.warnings.isEmpty)
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

    @Test("cache access proactively removes every expired structured result")
    func cacheAccessPurgesExpiredRecords() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 2_000_000)
        context.insert(MealScanResultCacheRecord(
            cacheKey: "expired-unrelated-key",
            modelID: "gemini-3.1-flash-lite",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            responseJSON: "{}",
            confidenceScore: 0.5,
            sourceImageHash: "hash",
            createdAt: now.addingTimeInterval(-100),
            lastAccessedAt: now.addingTimeInterval(-100),
            expiresAt: now.addingTimeInterval(-1)
        ))
        try context.save()

        let cache = MealScanResultCache(modelContext: context)
        _ = try cache.cachedResponseJSON(for: "missing-key", now: now)

        let remaining = try context.fetch(FetchDescriptor<MealScanResultCacheRecord>())
        #expect(remaining.isEmpty)
    }

    @Test("cache supports explicit eviction of a corrupt structured result")
    func cacheSupportsExplicitEviction() throws {
        let container = try TestHelpers.makeModelContainer()
        let cache = MealScanResultCache(modelContext: container.mainContext)
        let now = Date(timeIntervalSince1970: 2_000_000)
        try cache.saveResponseJSON(
            "not-json",
            cacheKey: "corrupt-key",
            modelID: "server-model",
            schemaVersion: "meal-scan-gemini-v1",
            promptVersion: "meal-scan-prompt-v1",
            confidenceScore: 0,
            sourceImageHash: "hash",
            now: now
        )

        try cache.removeCachedResponse(for: "corrupt-key")

        #expect(try cache.cachedResponseJSON(for: "corrupt-key", now: now) == nil)
    }

    @Test("corrupt local cache is evicted before fresh transport continues")
    func corruptLocalCacheIsEvictedAndTransportContinues() async throws {
        let cache = CorruptMealScanResultCache()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: cache,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
            appCheckTokenProvider: RecordingLimitedUseAppCheckTokenProvider(),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(cache.readCount == 1)
        #expect(cache.removedCacheKeys.count == 1)
        #expect(cache.savedResponseJSON == Self.simpleResponseJSON)
        #expect(remote.callCount == 1)
        #expect(outcome.source == .fresh)
        #expect(outcome.consumption == .used)
    }

    @Test("persistent cache read errors are safe misses for cache lookup and scan")
    func persistentCacheReadErrorsAreSafeMisses() async throws {
        let cache = PersistentReadFailureMealScanResultCache()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: cache,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .online),
            appCheckTokenProvider: RecordingLimitedUseAppCheckTokenProvider(),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )
        let normalizedImage = NormalizedMealScanImage(
            jpegData: Data("normalized-image".utf8),
            sourceImageHash: MealScanImageNormalizer.sha256Hex(Data("normalized-image".utf8)),
            width: 10,
            height: 10
        )

        let cachedOutcome = try await service.cachedOutcome(
            normalizedImage: normalizedImage,
            mealType: .lunch
        )
        let scanOutcome = try await service.scan(
            normalizedImage: normalizedImage,
            mealType: .lunch,
            requestID: UUID(uuidString: "907926AF-6C71-468B-BE10-D20D44A6D4B1")!
        )

        #expect(cachedOutcome == nil)
        #expect(cache.readCount == 2)
        #expect(remote.callCount == 1)
        #expect(scanOutcome.source == .fresh)
        #expect(scanOutcome.consumption == .used)
    }

    @Test("failed corrupt cache eviction blocks transport as not used")
    func failedCorruptCacheEvictionBlocksTransportAsNotUsed() async throws {
        let cache = UnremovableCorruptMealScanResultCache()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: cache,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .online),
            appCheckTokenProvider: RecordingLimitedUseAppCheckTokenProvider(),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        do {
            _ = try await service.scan(
                image: UIImage(),
                mealType: .lunch,
                requestID: UUID(uuidString: "2EB200C8-429B-4460-9513-593F65F1CD1D")!
            )
            Issue.record("Expected failed corrupt-cache eviction to stop before transport")
        } catch let error as any MealScanFailureProviding {
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .ambiguousResult,
                cause: .unclassified,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            ))
        } catch {
            Issue.record("Expected a typed pre-dispatch cache failure, received \(error)")
        }

        #expect(cache.readCount == 1)
        #expect(cache.removeCount == 1)
        #expect(remote.callCount == 0)
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let first = try await service.scan(image: UIImage(), mealType: .lunch)
        let second = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(first.result.mealName == "Rice bowl")
        #expect(second.result.mealName == "Rice bowl")
        #expect(remote.callCount == 1)
        #expect(first.cacheDisposition == .fresh)
        #expect(first.consumption == .used)
        #expect(second.cacheDisposition == .local)
        #expect(second.consumption == .notUsed)
        #expect(second.result.modelVersion.contains("cache"))
    }

    @Test("exact local cache returns before connectivity is checked")
    func exactLocalCacheReturnsBeforeConnectivityCheck() async throws {
        let cache = StaticReadMealScanResultCache(responseJSON: Self.simpleResponseJSON)
        let connectivity = RecordingMealScanConnectivityChecker(status: .offline)
        let evidenceProvider = RecordingStoreKitEvidenceProvider()
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: cache,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: connectivity,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(outcome.cacheDisposition == .local)
        #expect(outcome.consumption == .notUsed)
        #expect(cache.readCount == 1)
        #expect(connectivity.callCount == 0)
        #expect(evidenceProvider.callCount == 0)
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 0)
        #expect(remote.callCount == 0)
    }

    @Test("confirmed offline fails before StoreKit, App Check, or transport")
    func confirmedOfflineFailsBeforeEvidenceAndTransport() async throws {
        let connectivity = RecordingMealScanConnectivityChecker(status: .offline)
        let evidenceProvider = RecordingStoreKitEvidenceProvider()
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider()
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: connectivity,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )

        do {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
            Issue.record("Expected confirmed offline to stop before dispatch")
        } catch let error as MealScanRemoteError {
            #expect(error == .offlineBeforeDispatch)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .offlineBeforeDispatch,
                cause: .offline,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            ))
        }

        #expect(connectivity.callCount == 1)
        #expect(evidenceProvider.callCount == 0)
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 0)
        #expect(remote.callCount == 0)
    }

    @Test("unknown connectivity proceeds through evidence, App Check, and transport in order")
    func unknownConnectivityProceedsInSecurityOrder() async throws {
        let recorder = MealScanCallSequenceRecorder()
        let connectivity = RecordingMealScanConnectivityChecker(
            status: .unknown,
            onCall: { recorder.record("connectivity") }
        )
        let evidenceProvider = RecordingStoreKitEvidenceProvider {
            recorder.record("storekit")
        }
        let appCheckTokenProvider = RecordingLimitedUseAppCheckTokenProvider {
            recorder.record("appcheck")
        }
        let remote = CountingRemoteMealScanEstimator(
            responseJSON: Self.simpleResponseJSON,
            onCall: { recorder.record("transport") }
        )
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: connectivity,
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(outcome.consumption == .used)
        #expect(recorder.events == ["connectivity", "storekit", "appcheck", "transport"])
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: evidenceProvider
        )
        let requestID = UUID()

        await #expect(throws: MealScanRemoteError.outcomeUnknown(requestID: requestID)) {
            _ = try await service.scan(image: UIImage(), mealType: .lunch, requestID: requestID)
        }
        _ = try await service.scan(image: UIImage(), mealType: .lunch, requestID: requestID)

        #expect(remote.receivedRequests.map(\.requestID) == [requestID, requestID])
        #expect(remote.receivedRequests[0].normalizedImageJPEGData == remote.receivedRequests[1].normalizedImageJPEGData)
        #expect(remote.receivedRequests[0].sourceImageHash == remote.receivedRequests[1].sourceImageHash)
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: ThrowingStoreKitEvidenceProvider()
        )

        do {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
            Issue.record("Expected missing StoreKit evidence to fail closed")
        } catch let error as MealScanRemoteError {
            #expect(error == .subscriptionEvidenceUnavailable)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .entitlement,
                cause: .entitlementEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            ))
        }
        #expect(remote.callCount == 0)
        #expect(appCheckTokenProvider.limitedUseTokenCallCount == 0)
    }

    @Test("App Check token failure is integrity not used before transport")
    func appCheckFailureMapsToIntegrityNotUsed() async throws {
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.simpleResponseJSON)
        let appCheckTokenProvider = ThrowingLimitedUseAppCheckTokenProvider()
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .online),
            appCheckTokenProvider: appCheckTokenProvider,
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        do {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
            Issue.record("Expected App Check acquisition to fail closed")
        } catch let error as MealScanRemoteError {
            #expect(error == .appIntegrityEvidenceUnavailable)
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .appIntegrity,
                cause: .appIntegrityEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            ))
        }

        #expect(appCheckTokenProvider.callCount == 1)
        #expect(remote.callCount == 0)
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        let outcome = try await service.scan(image: UIImage(), mealType: .lunch)

        #expect(outcome.cacheDisposition == .server)
        #expect(outcome.consumption == .notUsed)
    }

    @Test("fresh response mapping failure is unreadable and uses a scan")
    func freshResponseMappingFailureIsUnreadableAndUsed() async throws {
        let remote = CountingRemoteMealScanEstimator(responseJSON: Self.missingNutritionResponseJSON)
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .online),
            appCheckTokenProvider: RecordingLimitedUseAppCheckTokenProvider(),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        do {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
            Issue.record("Expected the completed fresh response to fail typed mapping")
        } catch let error as any MealScanFailureProviding {
            #expect(error.mealScanFailure.kind == .unreadableMeal)
            #expect(error.mealScanFailure.cause == .providerResponseInvalid)
            #expect(error.mealScanFailure.consumption == .used)
            #expect(error.mealScanFailure.retryBehavior == .none)
        } catch {
            Issue.record("Expected a typed unreadable provider result, received \(error)")
        }

        #expect(remote.callCount == 1)
    }

    @Test("server-cache mapping failure is unreadable without using a scan")
    func serverCacheMappingFailureIsUnreadableAndNotUsed() async throws {
        let remote = CountingRemoteMealScanEstimator(
            responseJSON: Self.missingNutritionResponseJSON,
            cacheHit: true
        )
        let service = GeminiRemoteMealScanService(
            remoteEstimator: remote,
            resultCache: nil,
            imageNormalizer: StubMealScanImageNormalizer(jpegData: Data("normalized-image".utf8)),
            nutritionLookupService: LocalFoodNutritionRepository(records: SampleNutritionFixtures.records),
            calculator: MealNutritionCalculator(),
            configuration: .testDefault,
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .online),
            appCheckTokenProvider: RecordingLimitedUseAppCheckTokenProvider(),
            storeKitEvidenceProvider: FixedStoreKitEvidenceProvider()
        )

        do {
            _ = try await service.scan(image: UIImage(), mealType: .lunch)
            Issue.record("Expected the server-cache response to fail typed mapping")
        } catch let error as any MealScanFailureProviding {
            #expect(error.mealScanFailure.kind == .unreadableMeal)
            #expect(error.mealScanFailure.cause == .providerResponseInvalid)
            #expect(error.mealScanFailure.consumption == .notUsed)
            #expect(error.mealScanFailure.retryBehavior == .none)
        } catch {
            Issue.record("Expected a typed unreadable server-cache result, received \(error)")
        }

        #expect(remote.callCount == 1)
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
            connectivityChecker: RecordingMealScanConnectivityChecker(status: .unknown),
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

        do {
            _ = try await GeminiMealScanProxyClient(
                endpointURL: URL(string: "https://proxy.example/v1/meal-scans/estimate")!,
                urlSession: .mealScanTestSession()
            ).estimateMeal(request: request)
            Issue.record("Expected the local image-size guard to reject the photo")
        } catch let error as MealScanRemoteError {
            #expect(error == .imageTooLarge(
                actualBytes: GeminiMealScanProxyClient.maximumImageBytes + 1,
                maximumBytes: GeminiMealScanProxyClient.maximumImageBytes
            ))
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .unreadableMeal,
                cause: .invalidImage,
                consumption: .notUsed,
                retryBehavior: .none
            ))
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
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .unreadableMeal,
                cause: .invalidImage,
                consumption: .notUsed,
                retryBehavior: .none
            ))
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
            #expect(request.value(forHTTPHeaderField: "X-CycleBalance-Canary-ID") == nil)
            #expect(request.value(forHTTPHeaderField: "X-CycleBalance-Canary-Operation") == nil)
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

    @Test("canary launch nonce is accepted only for a development-signed runtime")
    func canaryLaunchNonceRequiresDevelopmentSigning() throws {
        let canaryID = UUID(uuidString: "90B2AC63-E61F-49E1-A8B0-A5E85F154D4C")!
        let arguments = ["CycleBalance", MealScanCanaryCorrelation.launchArgument, canaryID.uuidString]

        let accepted = MealScanCanaryCorrelation.from(
            arguments: arguments,
            isDevelopmentSigned: true
        )
        #expect(accepted?.canaryID == canaryID)
        #expect(accepted?.headerValue == canaryID.uuidString.lowercased())

        #expect(MealScanCanaryCorrelation.from(
            arguments: arguments,
            isDevelopmentSigned: false
        ) == nil)
        #expect(MealScanCanaryCorrelation.from(
            arguments: ["CycleBalance", MealScanCanaryCorrelation.launchArgument, "not-a-uuid"],
            isDevelopmentSigned: true
        ) == nil)
        #expect(MealScanCanaryCorrelation.from(
            arguments: arguments + [MealScanCanaryCorrelation.launchArgument, canaryID.uuidString],
            isDevelopmentSigned: true
        ) == nil)
    }

    @Test("development canary sends content-free correlation and request operation headers")
    func developmentCanarySendsCorrelationHeaders() async throws {
        let canaryID = UUID(uuidString: "90B2AC63-E61F-49E1-A8B0-A5E85F154D4C")!
        let requestID = UUID(uuidString: "4D99A795-D22C-4F50-BBBA-461DA7A4D94C")!
        let correlation = MealScanCanaryCorrelation(canaryID: canaryID)
        MockMealScanURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "X-CycleBalance-Canary-ID") == canaryID.uuidString.lowercased())
            #expect(
                request.value(forHTTPHeaderField: "X-CycleBalance-Canary-Operation") ==
                correlation.operationTag(for: requestID)
            )
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("""
                {
                  "modelId": "gemini-3.1-flash-lite",
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
            urlSession: .mealScanTestSession(),
            canaryCorrelation: correlation
        ).estimateMeal(request: .testDefault(requestID: requestID))
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
            #expect(error.mealScanFailure == MealScanFailure(
                kind: .quotaExhausted,
                cause: .quotaExhausted,
                consumption: .notUsed,
                retryBehavior: .none,
                quota: error.quota,
                retryAfterSeconds: 120
            ))
        }
    }

    @Test("current server error and reason combinations map to exact causes and consumption truth")
    func currentServerErrorsMapToExactCausesAndConsumptionTruth() {
        let quota = MealScanQuota(
            tier: "subscriber",
            used: 10,
            limit: 10,
            remaining: 0,
            windowSeconds: 86_400,
            resetAt: "2026-07-17T01:02:03.000Z",
            retryAfterSeconds: 120
        )

        let mappings: [(GeminiMealScanProxyError, MealScanFailure)] = [
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_unavailable",
                    reason: "feature_disabled",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .featureDisabled,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_unavailable",
                    reason: "request_control_unavailable",
                    quota: nil,
                    retryable: true
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .serviceControlUnavailable,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_unavailable",
                    reason: "monthly_budget_exceeded",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .budgetDispatchDisabled,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 429,
                    error: "provider_dispatch_rate_limited",
                    reason: "global_provider_dispatch_limit_exceeded",
                    quota: nil,
                    retryable: true,
                    retryAfterSeconds: 17
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .requestRateLimited,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest,
                    retryAfterSeconds: 17
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 401,
                    error: "app_integrity_required",
                    reason: "app_check_rejected",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .appIntegrity,
                    cause: .appIntegrityRejected,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_unavailable",
                    reason: "integrity_service_timeout",
                    quota: nil,
                    retryable: true
                ),
                MealScanFailure(
                    kind: .appIntegrity,
                    cause: .appIntegrityEvidenceUnavailable,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 403,
                    error: "premium_entitlement_required",
                    reason: "subscription_inactive",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .entitlement,
                    cause: .entitlementRejected,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_unavailable",
                    reason: "storekit_verification_unavailable",
                    quota: nil,
                    retryable: true
                ),
                MealScanFailure(
                    kind: .entitlement,
                    cause: .entitlementEvidenceUnavailable,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 429,
                    error: "meal_scan_request_rate_limited",
                    reason: "principal_attempt_minute_limit_exceeded",
                    quota: nil,
                    retryable: true,
                    retryAfterSeconds: 17
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .requestRateLimited,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest,
                    retryAfterSeconds: 17
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 429,
                    error: "rolling_scan_quota_exceeded",
                    reason: "rolling_quota_exceeded",
                    quota: quota,
                    retryable: true
                ),
                MealScanFailure(
                    kind: .quotaExhausted,
                    cause: .quotaExhausted,
                    consumption: .notUsed,
                    retryBehavior: .none,
                    quota: quota,
                    retryAfterSeconds: 120
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 400,
                    error: "invalid_request",
                    reason: nil,
                    quota: nil,
                    retryable: false,
                    detail: "jpeg image could not be decoded"
                ),
                MealScanFailure(
                    kind: .unreadableMeal,
                    cause: .invalidImage,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 400,
                    error: "invalid_request",
                    reason: nil,
                    quota: nil,
                    retryable: false,
                    detail: "signedTransactionJWS is invalid"
                ),
                MealScanFailure(
                    kind: .entitlement,
                    cause: .entitlementRejected,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 400,
                    error: "invalid_json",
                    reason: "request_body_invalid",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .invalidRequest,
                    consumption: .notUsed,
                    retryBehavior: .none
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 409,
                    error: "idempotency_conflict",
                    reason: "request_body_mismatch",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .idempotencyConflict,
                    consumption: .unknown,
                    retryBehavior: .none
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 409,
                    error: "meal_scan_in_progress",
                    reason: "principal_dispatch_in_progress",
                    quota: nil,
                    retryable: true,
                    retryAfterSeconds: 11
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .requestPending,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest,
                    retryAfterSeconds: 11
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 409,
                    error: "meal_scan_in_progress",
                    reason: "duplicate_request_in_progress",
                    quota: nil,
                    retryable: true,
                    retryAfterSeconds: 7
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .requestPending,
                    consumption: .unknown,
                    retryBehavior: .checkSameRequest,
                    retryAfterSeconds: 7
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 502,
                    error: "meal_scan_parse_error",
                    reason: "provider_response_invalid",
                    quota: quota,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .unreadableMeal,
                    cause: .providerResponseInvalid,
                    consumption: .used,
                    retryBehavior: .none,
                    quota: quota,
                    retryAfterSeconds: 120
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 502,
                    error: "meal_scan_provider_error",
                    reason: "provider_request_failed",
                    quota: quota,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .providerRequestFailed,
                    consumption: .used,
                    retryBehavior: .checkSameRequest,
                    quota: quota,
                    retryAfterSeconds: 120
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 503,
                    error: "meal_scan_outcome_unknown",
                    reason: "provider_dispatch_outcome_unknown",
                    quota: nil,
                    retryable: false
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .providerDispatchOutcomeUnknown,
                    consumption: .used,
                    retryBehavior: .checkSameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 500,
                    error: "meal_scan_proxy_error",
                    reason: nil,
                    quota: nil,
                    retryable: nil
                ),
                MealScanFailure(
                    kind: .serviceDisabled,
                    cause: .serviceControlUnavailable,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            ),
            (
                GeminiMealScanProxyError(
                    statusCode: 500,
                    error: "future_proxy_failure",
                    reason: "future_reason",
                    quota: nil,
                    retryable: nil,
                    retryAfterSeconds: 17
                ),
                MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .unclassified,
                    consumption: .unknown,
                    retryBehavior: .checkSameRequest,
                    retryAfterSeconds: 17
                )
            ),
        ]

        for (proxyError, expectedFailure) in mappings {
            #expect(proxyError.mealScanFailure == expectedFailure)
        }
    }

    @Test("trial lifetime quota error does not promise a rolling reset")
    func trialLifetimeQuotaErrorDoesNotPromiseRollingReset() {
        let error = GeminiMealScanProxyError(
            statusCode: 429,
            error: "rolling_scan_quota_exceeded",
            reason: "trial_lifetime_quota_exceeded",
            quota: MealScanQuota(
                tier: "trial",
                used: 5,
                limit: 5,
                remaining: 0,
                windowSeconds: 86_400,
                resetAt: "2026-07-14T12:00:00.000Z",
                retryAfterSeconds: 86_400
            ),
            retryable: false
        )

        #expect(
            error.errorDescription == "You've used the lifetime trial AI photo analysis allowance. Scan a barcode or enter the meal manually."
        )
        #expect(error.errorDescription?.localizedCaseInsensitiveContains("rolling") == false)
        #expect(error.errorDescription?.localizedCaseInsensitiveContains("reset") == false)
    }

    @Test("quota tiers expose localized display labels and hide unknown backend tokens")
    func quotaTiersExposeLocalizedDisplayLabels() {
        func quota(tier: String) -> MealScanQuota {
            MealScanQuota(
                tier: tier,
                used: 0,
                limit: 10,
                remaining: 10,
                windowSeconds: 86_400,
                resetAt: nil,
                retryAfterSeconds: nil
            )
        }

        #expect(quota(tier: "paid").localizedTierDisplayName == "paid")
        #expect(quota(tier: "subscriber").localizedTierDisplayName == "paid")
        #expect(quota(tier: "trial").localizedTierDisplayName == "trial")
        #expect(quota(tier: "sandbox").localizedTierDisplayName == "sandbox")
        #expect(quota(tier: "future-backend-value").localizedTierDisplayName == "standard")
        #expect(quota(tier: "future-backend-value").localizedTierDisplayName != "future-backend-value")
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

    private static let missingNutritionResponseJSON = """
    {
      "meal_name": "Incomplete provider meal",
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

    private static let sourceTestResult = MealScanResult(
        mealName: "Source test meal",
        mealType: .lunch,
        detectedItems: [],
        nutrition: NutritionSnapshot(
            caloriesKcal: 0,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
            fiberGrams: 0
        ),
        metabolicProfile: MealMetabolicProfile(
            carbLoadCategory: .low,
            proteinAdequacy: .low,
            fiberAdequacy: .low,
            fatLevel: .low,
            estimatedGlycemicImpact: .low,
            mealBalanceScore: 0,
            explanation: "Test"
        ),
        confidence: .low,
        warnings: [],
        originalPredictionJSON: "{}",
        modelVersion: "test",
        pipelineVersion: "test"
    )

    fileprivate static let testSignedTransactionJWS = "eyJhbGciOiJFUzI1NiJ9.eyJ0eCI6InRlc3QifQ.signature"
}

@MainActor
private final class CountingRemoteMealScanEstimator: RemoteMealScanEstimating {
    private let responseJSON: String
    private let cacheHit: Bool
    private let onCall: (() -> Void)?
    var callCount = 0
    var receivedRequests: [RemoteMealScanRequest] = []
    var receivedFirebaseAppCheckTokens: [String?] = []

    init(
        responseJSON: String,
        cacheHit: Bool = false,
        onCall: (() -> Void)? = nil
    ) {
        self.responseJSON = responseJSON
        self.cacheHit = cacheHit
        self.onCall = onCall
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        onCall?()
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
private final class CorruptMealScanResultCache: MealScanResultCaching {
    private(set) var readCount = 0
    private(set) var removedCacheKeys: [String] = []
    private(set) var savedResponseJSON: String?

    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String? {
        readCount += 1
        return readCount == 1 ? "not-json" : nil
    }

    func removeCachedResponse(for cacheKey: String) throws {
        removedCacheKeys.append(cacheKey)
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
        savedResponseJSON = responseJSON
    }
}

@MainActor
private final class PersistentReadFailureMealScanResultCache: MealScanResultCaching {
    private(set) var readCount = 0

    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String? {
        readCount += 1
        throw CocoaError(.fileReadCorruptFile)
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
    ) throws {}
}

@MainActor
private final class UnremovableCorruptMealScanResultCache: MealScanResultCaching {
    private(set) var readCount = 0
    private(set) var removeCount = 0

    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String? {
        readCount += 1
        return "not-json"
    }

    func removeCachedResponse(for cacheKey: String) throws {
        removeCount += 1
        throw CocoaError(.fileWriteNoPermission)
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
    ) throws {}
}

@MainActor
private final class RecordingLimitedUseAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    var limitedUseTokenCallCount = 0
    private let onCall: (() -> Void)?

    init(onCall: (() -> Void)? = nil) {
        self.onCall = onCall
    }

    func limitedUseToken() async throws -> String {
        onCall?()
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
    private let onCall: (() -> Void)?

    init(onCall: (() -> Void)? = nil) {
        self.onCall = onCall
    }

    func signedTransactionJWS() async throws -> String {
        onCall?()
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

@MainActor
private final class ThrowingLimitedUseAppCheckTokenProvider: MealScanLimitedUseAppCheckTokenProviding {
    private(set) var callCount = 0

    func limitedUseToken() async throws -> String {
        callCount += 1
        throw URLError(.userAuthenticationRequired)
    }
}

@MainActor
private final class RecordingMealScanConnectivityChecker: MealScanConnectivityChecking {
    let status: MealScanConnectivityStatus
    private let onCall: (() -> Void)?
    private(set) var callCount = 0

    init(status: MealScanConnectivityStatus, onCall: (() -> Void)? = nil) {
        self.status = status
        self.onCall = onCall
    }

    func connectivityStatus() -> MealScanConnectivityStatus {
        onCall?()
        callCount += 1
        return status
    }
}

@MainActor
private final class StaticReadMealScanResultCache: MealScanResultCaching {
    private let responseJSON: String
    private(set) var readCount = 0

    init(responseJSON: String) {
        self.responseJSON = responseJSON
    }

    func cachedResponseJSON(for cacheKey: String, now: Date) throws -> String? {
        readCount += 1
        return responseJSON
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
    ) throws {}
}

@MainActor
private final class MealScanCallSequenceRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
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
        firebaseAppCheckToken: String? = "limited-use-token"
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

@Suite("Firebase App Check token provider without configured Firebase")
struct FirebaseMealScanAppCheckTokenProviderTests {
    @Test("Provider throws instead of crashing when Firebase was not configured for this build")
    @MainActor
    func limitedUseTokenThrowsWhenFirebaseIsNotConfigured() async {
        // The test host is a Debug build with the Gemini scanner disabled, so Firebase is never configured.
        let provider = FirebaseMealScanAppCheckTokenProvider()
        await #expect(throws: (any Error).self) {
            _ = try await provider.limitedUseToken()
        }
    }
}
