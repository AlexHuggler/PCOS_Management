import Foundation
import SwiftData
import StoreKit
import UIKit

enum GeminiMealScanParsingError: LocalizedError, Equatable {
    case invalidJSON
    case emptyEstimate

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "Gemini returned a meal estimate CycleBalance could not read."
        case .emptyEstimate:
            "Gemini did not return any foods to review."
        }
    }
}

enum GeminiMealScanMappingError: LocalizedError, Equatable {
    case missingNutritionEstimate(itemName: String)

    var errorDescription: String? {
        switch self {
        case .missingNutritionEstimate(let itemName):
            "CycleBalance did not receive complete nutrition for \(itemName). Nothing was added to your meal log."
        }
    }
}

struct GeminiMealEstimateResponse: Codable, Equatable, Sendable {
    var mealName: String
    var confidence: NutritionConfidence
    var warnings: [GeminiMealEstimateWarning]
    var items: [GeminiMealEstimateItem]

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case confidence
        case warnings
        case items
    }
}

struct GeminiMealEstimateItem: Codable, Equatable, Sendable {
    var displayName: String
    var canonicalQuery: String
    var estimatedGrams: Double
    var servingDescription: String?
    var confidence: NutritionConfidence
    var isMixedDish: Bool
    var warning: String?
    var nutritionFallback: GeminiMealEstimateNutritionFallback?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case canonicalQuery = "canonical_query"
        case estimatedGrams = "estimated_grams"
        case servingDescription = "serving_description"
        case confidence
        case isMixedDish = "is_mixed_dish"
        case warning
        case nutritionFallback = "nutrition_fallback"
    }
}

struct GeminiMealEstimateNutritionFallback: Codable, Equatable, Sendable {
    var caloriesKcal: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sugarGrams: Double
    var sodiumMg: Double

    enum CodingKeys: String, CodingKey {
        case caloriesKcal = "calories_kcal"
        case proteinGrams = "protein_grams"
        case carbsGrams = "carbs_grams"
        case fatGrams = "fat_grams"
        case fiberGrams = "fiber_grams"
        case sugarGrams = "sugar_grams"
        case sodiumMg = "sodium_mg"
    }

    var nutritionSnapshot: NutritionSnapshot {
        NutritionSnapshot(
            caloriesKcal: caloriesKcal,
            proteinGrams: proteinGrams,
            carbsGrams: carbsGrams,
            fatGrams: fatGrams,
            fiberGrams: fiberGrams,
            sugarGrams: sugarGrams,
            sodiumMg: sodiumMg
        )
    }
}

struct GeminiMealEstimateWarning: Codable, Equatable, Sendable {
    var code: String
    var message: String
}

struct GeminiMealScanResponseParser: Sendable {
    func parseResponseJSON(_ responseJSON: String) throws -> GeminiMealEstimateResponse {
        guard let data = responseJSON.data(using: .utf8) else {
            throw GeminiMealScanParsingError.invalidJSON
        }

        do {
            let response = try JSONDecoder().decode(GeminiMealEstimateResponse.self, from: data)
            guard !response.items.isEmpty else {
                throw GeminiMealScanParsingError.emptyEstimate
            }
            return response
        } catch let error as GeminiMealScanParsingError {
            throw error
        } catch {
            throw GeminiMealScanParsingError.invalidJSON
        }
    }
}

@MainActor
struct GeminiMealScanResultMapper {
    private let metabolicProfileService = MealMetabolicProfileService()

    func map(
        response: GeminiMealEstimateResponse,
        originalResponseJSON: String,
        mealType: MealType,
        modelID: String,
        pipelineVersion: String,
        nutritionLookupService _: any NutritionLookupService,
        calculator: any MealNutritionCalculating
    ) async throws -> MealScanResult {
        let drafts = try response.items.map(cloudEstimateDraft(for:))

        let total = calculator.aggregateMealNutrition(items: drafts)
        let warnings = response.warnings.map(\.message) + response.items.compactMap(\.warning)
        let itemConfidence = MealScanConfidenceScorer.aggregate(drafts.map(\.confidence))
        let confidence = minConfidence(itemConfidence, response.confidence)
        let profile = metabolicProfileService.profile(
            for: total,
            confidence: confidence,
            hiddenIngredientEstimate: warnings.isEmpty ? .no : .notSure,
            visibleWarnings: warnings
        )

        return MealScanResult(
            mealName: response.mealName,
            mealType: mealType,
            detectedItems: drafts,
            nutrition: total,
            metabolicProfile: profile,
            confidence: confidence,
            warnings: warnings,
            originalPredictionJSON: originalResponseJSON,
            modelVersion: modelID,
            pipelineVersion: pipelineVersion
        )
    }

    private func cloudEstimateDraft(for item: GeminiMealEstimateItem) throws -> MealFoodItemDraft {
        guard let nutritionFallback = item.nutritionFallback else {
            throw GeminiMealScanMappingError.missingNutritionEstimate(itemName: item.displayName)
        }
        let nutrition = nutritionFallback.nutritionSnapshot
        let slug = item.displayName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return MealFoodItemDraft(
            displayName: item.displayName,
            canonicalFoodId: "gemini-estimate-\(slug.isEmpty ? "food" : slug)",
            nutritionSource: .aiEstimate,
            estimatedGrams: item.estimatedGrams,
            servingDescription: item.servingDescription,
            nutrition: nutrition,
            confidence: .low,
            warning: item.warning ?? "Gemini estimate only; review and edit before saving.",
            detectionSource: "gemini_cloud_estimate",
            portionEstimationMethod: .servingSizeHeuristic,
            isMixedDish: item.isMixedDish
        )
    }

    private func minConfidence(_ lhs: NutritionConfidence, _ rhs: NutritionConfidence) -> NutritionConfidence {
        lhs.rank <= rhs.rank ? lhs : rhs
    }
}

struct RemoteMealScanRequest: Equatable, Sendable {
    var requestID: UUID
    var signedTransactionJWS: String
    var normalizedImageJPEGData: Data
    var sourceImageHash: String
    var mealType: MealType
    var localeIdentifier: String
    var schemaVersion: String
    var promptVersion: String
    var firebaseAppCheckToken: String?
}

@MainActor
protocol MealScanLimitedUseAppCheckTokenProviding {
    func limitedUseToken() async throws -> String
}

@MainActor
protocol MealScanStoreKitEvidenceProviding {
    func signedTransactionJWS() async throws -> String
}

enum MealScanStoreKitEvidenceError: LocalizedError, Equatable, Sendable {
    case noVerifiedActiveSubscription

    var errorDescription: String? {
        "CycleBalance could not find a verified active monthly or annual subscription."
    }
}

@MainActor
struct StoreKitMealScanEvidenceProvider: MealScanStoreKitEvidenceProviding {
    func signedTransactionJWS() async throws -> String {
        let allowedProductIDs = Set([
            SubscriptionManager.monthlyProductID,
            SubscriptionManager.yearlyProductID
        ])
        var bestEvidence: (expirationDate: Date, purchaseDate: Date, jws: String)?

        for await verification in Transaction.currentEntitlements {
            switch verification {
            case .unverified:
                continue
            case .verified(let transaction):
                guard allowedProductIDs.contains(transaction.productID),
                      transaction.productType == .autoRenewable,
                      transaction.revocationDate == nil,
                      !transaction.isUpgraded,
                      let expirationDate = transaction.expirationDate,
                      expirationDate > Date()
                else {
                    continue
                }
                if bestEvidence == nil
                    || expirationDate > bestEvidence!.expirationDate
                    || (expirationDate == bestEvidence!.expirationDate
                        && transaction.purchaseDate > bestEvidence!.purchaseDate) {
                    bestEvidence = (
                        expirationDate,
                        transaction.purchaseDate,
                        verification.jwsRepresentation
                    )
                }
            }
        }

        guard let bestEvidence else {
            throw MealScanStoreKitEvidenceError.noVerifiedActiveSubscription
        }
        return bestEvidence.jws
    }
}

enum MealScanCacheDisposition: String, Codable, Equatable, Sendable {
    case fresh
    case server
    case local
}

struct MealScanQuota: Codable, Equatable, Sendable {
    var tier: String
    var used: Int
    var limit: Int
    var remaining: Int
    var windowSeconds: Int
    var resetAt: String?
    var retryAfterSeconds: Int?
}

struct MealScanOutcome: Equatable, Sendable {
    var result: MealScanResult
    var quota: MealScanQuota?
    var cacheDisposition: MealScanCacheDisposition
}

struct RemoteMealScanEstimate: Equatable, Sendable {
    var response: GeminiMealEstimateResponse
    var originalResponseJSON: String
    var modelID: String
    var quota: MealScanQuota
    var usage: RemoteMealScanUsage?
    var cacheHit: Bool = false
}

struct RemoteMealScanUsage: Codable, Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var estimatedCostUSD: Double?
}

struct GeminiMealScanProxyError: LocalizedError, Equatable, Sendable {
    var statusCode: Int
    var error: String
    var reason: String?
    var quota: MealScanQuota?
    var retryable: Bool?

    var errorDescription: String? {
        switch error {
        case "rolling_scan_quota_exceeded":
            if let quota {
                return "You've used all \(quota.limit) fresh AI photo analyses in the current rolling 24-hour \(quota.tier) allowance. Scan a barcode or enter the meal manually while the window resets."
            }
            return "You've used all fresh AI photo analyses in the current rolling 24-hour allowance. Scan a barcode or enter the meal manually while the window resets."
        case "premium_entitlement_required":
            return L10n.string("Photo meal estimates require an active trial or subscription.", defaultValue: "Photo meal estimates require an active trial or subscription.")
        case "app_integrity_required":
            return L10n.string("CycleBalance could not verify this app install. Update the app and try again.", defaultValue: "CycleBalance could not verify this app install. Update the app and try again.")
        case "meal_scan_unavailable":
            return L10n.string(
                "Photo estimates are temporarily unavailable. Close Photo Estimate to scan a barcode, or enter the meal manually.",
                defaultValue: "Photo estimates are temporarily unavailable. Close Photo Estimate to scan a barcode, or enter the meal manually."
            )
        case "gemini_timeout":
            return L10n.string(
                "The photo estimate timed out. Try again, close Photo Estimate to scan a barcode, or enter the meal manually.",
                defaultValue: "The photo estimate timed out. Try again, close Photo Estimate to scan a barcode, or enter the meal manually."
            )
        case "request_too_large":
            return L10n.string("That photo is too large to estimate. Try another photo or enter the meal manually.", defaultValue: "That photo is too large to estimate. Try another photo or enter the meal manually.")
        default:
            return L10n.string(
                "Photo estimates are unavailable right now. Close Photo Estimate to scan a barcode, or enter the meal manually.",
                defaultValue: "Photo estimates are unavailable right now. Close Photo Estimate to scan a barcode, or enter the meal manually."
            )
        }
    }
}

enum MealScanRemoteError: LocalizedError, Equatable, Sendable {
    case imageTooLarge(actualBytes: Int, maximumBytes: Int)
    case requestBodyTooLarge(actualBytes: Int, maximumBytes: Int)
    case subscriptionEvidenceUnavailable
    case outcomeUnknown(requestID: UUID)
    case requestPending(requestID: UUID, retryAfterSeconds: Int?)

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            "That photo could not be reduced to the secure upload limit. Try another photo or enter the meal manually."
        case .requestBodyTooLarge:
            "That photo request is too large to send. Try another photo or enter the meal manually."
        case .subscriptionEvidenceUnavailable:
            "CycleBalance could not verify an active App Store subscription for this analysis."
        case .outcomeUnknown:
            "CycleBalance could not confirm whether this analysis completed. Checking again with the same request is safe; starting a new analysis may use another fresh analysis."
        case .requestPending(_, let retryAfterSeconds):
            if let retryAfterSeconds {
                "This analysis is still processing. Check the same request again in about \(retryAfterSeconds) seconds."
            } else {
                "This analysis is still processing. Check the same request again shortly."
            }
        }
    }
}

@MainActor
protocol RemoteMealScanEstimating: AnyObject {
    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate
}

struct GeminiRemoteMealScanConfiguration: Equatable, Sendable {
    static let proxyBaseURLKey = "MEAL_SCAN_PROXY_BASE_URL"
    static let schemaVersion = "meal-scan-gemini-v1"
    static let promptVersion = "meal-scan-prompt-v1"
    static let localCacheNamespace = "meal-scan-proxy-v1"

    var schemaVersion: String
    var promptVersion: String
    var localeIdentifier: String
    var appBuild: String
    var proxyEndpointURL: URL?

    init(
        schemaVersion: String = Self.schemaVersion,
        promptVersion: String = Self.promptVersion,
        localeIdentifier: String = Locale.current.identifier,
        appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
        proxyEndpointURL: URL? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.localeIdentifier = localeIdentifier
        self.appBuild = appBuild
        self.proxyEndpointURL = proxyEndpointURL
    }

    static func from(bundle: Bundle = .main) -> GeminiRemoteMealScanConfiguration? {
        guard let rawURL = BillingConfiguration.sanitized(
            bundle.object(forInfoDictionaryKey: proxyBaseURLKey) as? String
        ),
              let baseURL = URL(string: rawURL)
        else {
            return nil
        }

        return GeminiRemoteMealScanConfiguration(
            proxyEndpointURL: baseURL.appendingPathComponent("v1/meal-scans/estimate")
        )
    }
}

@MainActor
final class GeminiMealScanProxyClient: RemoteMealScanEstimating {
    static let maximumImageBytes = 1_500_000
    static let maximumRequestBodyBytes = 2_200_000

    private let endpointURL: URL
    private let urlSession: URLSession

    init(endpointURL: URL, urlSession: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.urlSession = urlSession
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        guard request.normalizedImageJPEGData.count <= Self.maximumImageBytes else {
            throw MealScanRemoteError.imageTooLarge(
                actualBytes: request.normalizedImageJPEGData.count,
                maximumBytes: Self.maximumImageBytes
            )
        }

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let firebaseAppCheckToken = request.firebaseAppCheckToken {
            urlRequest.setValue(firebaseAppCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        let payload = ProxyRequestPayload(
            requestId: request.requestID.uuidString.lowercased(),
            signedTransactionJWS: request.signedTransactionJWS,
            mealType: request.mealType.rawValue,
            locale: request.localeIdentifier,
            schemaVersion: request.schemaVersion,
            promptVersion: request.promptVersion,
            image: ProxyImagePayload(
                mimeType: "image/jpeg",
                base64: request.normalizedImageJPEGData.base64EncodedString(),
                sha256: request.sourceImageHash
            )
        )
        let body = try JSONEncoder().encode(payload)
        guard body.count <= Self.maximumRequestBodyBytes else {
            throw MealScanRemoteError.requestBodyTooLarge(
                actualBytes: body.count,
                maximumBytes: Self.maximumRequestBodyBytes
            )
        }
        urlRequest.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MealScanRemoteError.outcomeUnknown(requestID: request.requestID)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MealScanRemoteError.outcomeUnknown(requestID: request.requestID)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(
                from: data,
                statusCode: httpResponse.statusCode,
                requestID: request.requestID
            )
        }

        let proxyResponse: ProxyResponsePayload
        do {
            proxyResponse = try JSONDecoder().decode(ProxyResponsePayload.self, from: data)
        } catch {
            throw MealScanRemoteError.outcomeUnknown(requestID: request.requestID)
        }
        let originalJSON: String
        if let rawEstimateJSON = proxyResponse.rawEstimateJSON {
            originalJSON = rawEstimateJSON
        } else {
            let encodedEstimate = try JSONEncoder().encode(proxyResponse.estimate)
            originalJSON = String(data: encodedEstimate, encoding: .utf8) ?? "{}"
        }
        return RemoteMealScanEstimate(
            response: proxyResponse.estimate,
            originalResponseJSON: originalJSON,
            modelID: proxyResponse.modelId,
            quota: proxyResponse.quota,
            usage: proxyResponse.usage,
            cacheHit: proxyResponse.cacheHit ?? false
        )
    }

    private func proxyError(
        from data: Data,
        statusCode: Int,
        requestID: UUID
    ) -> any Error {
        if let payload = try? JSONDecoder().decode(ProxyErrorPayload.self, from: data) {
            if payload.error == "meal_scan_in_progress" || payload.idempotency?.state == "pending" {
                return MealScanRemoteError.requestPending(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            if payload.error == "meal_scan_outcome_unknown" || payload.idempotency?.state == "unknown" {
                return MealScanRemoteError.outcomeUnknown(requestID: requestID)
            }
            return GeminiMealScanProxyError(
                statusCode: statusCode,
                error: payload.error,
                reason: payload.reason,
                quota: payload.quota,
                retryable: payload.retryable
            )
        }

        return GeminiMealScanProxyError(
            statusCode: statusCode,
            error: "meal_scan_proxy_error",
            reason: nil,
            quota: nil,
            retryable: nil
        )
    }
}

@MainActor
protocol RemoteMealScanServing: AnyObject {
    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome?

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome

}

extension RemoteMealScanServing {
    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        nil
    }

}

@MainActor
final class GeminiRemoteMealScanService: RemoteMealScanServing {
    private let remoteEstimator: any RemoteMealScanEstimating
    private let resultCache: (any MealScanResultCaching)?
    private let imageNormalizer: any MealScanImageNormalizing
    private let nutritionLookupService: any NutritionLookupService
    private let calculator: any MealNutritionCalculating
    private let configuration: GeminiRemoteMealScanConfiguration
    private let appCheckTokenProvider: (any MealScanLimitedUseAppCheckTokenProviding)?
    private let storeKitEvidenceProvider: any MealScanStoreKitEvidenceProviding
    private let parser = GeminiMealScanResponseParser()
    private let mapper = GeminiMealScanResultMapper()

    init(
        remoteEstimator: any RemoteMealScanEstimating,
        resultCache: (any MealScanResultCaching)?,
        imageNormalizer: any MealScanImageNormalizing,
        nutritionLookupService: any NutritionLookupService,
        calculator: any MealNutritionCalculating,
        configuration: GeminiRemoteMealScanConfiguration,
        appCheckTokenProvider: (any MealScanLimitedUseAppCheckTokenProviding)? = nil,
        storeKitEvidenceProvider: any MealScanStoreKitEvidenceProviding = StoreKitMealScanEvidenceProvider()
    ) {
        self.remoteEstimator = remoteEstimator
        self.resultCache = resultCache
        self.imageNormalizer = imageNormalizer
        self.nutritionLookupService = nutritionLookupService
        self.calculator = calculator
        self.configuration = configuration
        self.appCheckTokenProvider = appCheckTokenProvider
        self.storeKitEvidenceProvider = storeKitEvidenceProvider
    }

    func scan(
        image: UIImage,
        mealType: MealType,
        requestID: UUID = UUID()
    ) async throws -> MealScanOutcome {
        let normalized = try imageNormalizer.normalizeJPEGData(from: image)
        return try await scan(normalizedImage: normalized, mealType: mealType, requestID: requestID)
    }

    func scan(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType,
        requestID: UUID
    ) async throws -> MealScanOutcome {
        let cacheKey = cacheKey(for: normalizedImage, mealType: mealType)

        if let cachedOutcome = try await cachedOutcome(
            normalizedImage: normalizedImage,
            mealType: mealType
        ) {
            return cachedOutcome
        }

        let signedTransactionJWS: String
        do {
            signedTransactionJWS = try await storeKitEvidenceProvider.signedTransactionJWS()
        } catch {
            throw MealScanRemoteError.subscriptionEvidenceUnavailable
        }

        let firebaseAppCheckToken = try await appCheckTokenProvider?.limitedUseToken()
        let estimate = try await remoteEstimator.estimateMeal(
            request: RemoteMealScanRequest(
                requestID: requestID,
                signedTransactionJWS: signedTransactionJWS,
                normalizedImageJPEGData: normalizedImage.jpegData,
                sourceImageHash: MealScanImageNormalizer.sha256Hex(normalizedImage.jpegData),
                mealType: mealType,
                localeIdentifier: configuration.localeIdentifier,
                schemaVersion: configuration.schemaVersion,
                promptVersion: configuration.promptVersion,
                firebaseAppCheckToken: firebaseAppCheckToken
            )
        )

        let result = try await mapper.map(
            response: estimate.response,
            originalResponseJSON: estimate.originalResponseJSON,
            mealType: mealType,
            modelID: estimate.modelID,
            pipelineVersion: MealScanPipeline.pipelineVersion,
            nutritionLookupService: nutritionLookupService,
            calculator: calculator
        )
        try? resultCache?.saveResponseJSON(
            estimate.originalResponseJSON,
            cacheKey: cacheKey,
            modelID: estimate.modelID,
            schemaVersion: configuration.schemaVersion,
            promptVersion: configuration.promptVersion,
            confidenceScore: result.confidence.score,
            sourceImageHash: MealScanImageNormalizer.sha256Hex(normalizedImage.jpegData),
            now: Date()
        )
        return MealScanOutcome(
            result: result,
            quota: estimate.quota,
            cacheDisposition: estimate.cacheHit ? .server : .fresh
        )
    }

    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        let cacheKey = cacheKey(for: normalizedImage, mealType: mealType)
        guard let cachedJSON = try resultCache?.cachedResponseJSON(for: cacheKey, now: Date()) else {
            return nil
        }
        let response = try parser.parseResponseJSON(cachedJSON)
        let result = try await mapper.map(
            response: response,
            originalResponseJSON: cachedJSON,
            mealType: mealType,
            modelID: "\(GeminiRemoteMealScanConfiguration.localCacheNamespace)-local-cache",
            pipelineVersion: MealScanPipeline.pipelineVersion,
            nutritionLookupService: nutritionLookupService,
            calculator: calculator
        )
        return MealScanOutcome(result: result, quota: nil, cacheDisposition: .local)
    }

    private func cacheKey(
        for normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) -> String {
        MealScanResultCache.cacheKey(
            modelID: GeminiRemoteMealScanConfiguration.localCacheNamespace,
            schemaVersion: configuration.schemaVersion,
            promptVersion: configuration.promptVersion,
            normalizedImageData: normalizedImage.jpegData,
            mealType: mealType,
            localeIdentifier: configuration.localeIdentifier,
            appBuild: configuration.appBuild
        )
    }
}

private struct ProxyRequestPayload: Encodable {
    var requestId: String
    var signedTransactionJWS: String
    var mealType: String
    var locale: String
    var schemaVersion: String
    var promptVersion: String
    var image: ProxyImagePayload
}

private struct ProxyImagePayload: Encodable {
    var mimeType: String
    var base64: String
    var sha256: String
}

private struct ProxyResponsePayload: Decodable {
    var estimate: GeminiMealEstimateResponse
    var rawEstimateJSON: String?
    var modelId: String
    var quota: MealScanQuota
    var usage: RemoteMealScanUsage?
    var cacheHit: Bool?
}

private struct ProxyErrorPayload: Decodable {
    var error: String
    var reason: String?
    var quota: MealScanQuota?
    var retryable: Bool?
    var retryAfterSeconds: Int?
    var idempotency: ProxyIdempotencyPayload?
}

private struct ProxyIdempotencyPayload: Decodable {
    var state: String?
}
