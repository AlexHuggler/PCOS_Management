import Foundation
import SwiftData
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
        nutritionLookupService: any NutritionLookupService,
        calculator: any MealNutritionCalculating
    ) async throws -> MealScanResult {
        var drafts: [MealFoodItemDraft] = []

        for item in response.items {
            let localMatches = try await nutritionLookupService.searchFood(query: item.canonicalQuery)
            if let food = localMatches.first {
                drafts.append(
                    MealFoodItemDraft(
                        displayName: item.displayName,
                        canonicalFoodId: food.id,
                        nutritionSource: food.source,
                        estimatedGrams: item.estimatedGrams,
                        servingDescription: item.servingDescription ?? food.servingDescription,
                        nutrition: calculator.calculateItemNutrition(food: food, grams: item.estimatedGrams),
                        confidence: item.confidence,
                        warning: item.warning,
                        detectionSource: "gemini_local_match",
                        portionEstimationMethod: .servingSizeHeuristic,
                        isMixedDish: item.isMixedDish
                    )
                )
            } else {
                drafts.append(fallbackDraft(for: item))
            }
        }

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

    private func fallbackDraft(for item: GeminiMealEstimateItem) -> MealFoodItemDraft {
        let nutrition = item.nutritionFallback?.nutritionSnapshot ?? NutritionSnapshot()
        let slug = item.displayName
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return MealFoodItemDraft(
            displayName: item.displayName,
            canonicalFoodId: "gemini-fallback-\(slug.isEmpty ? "food" : slug)",
            nutritionSource: .userManual,
            estimatedGrams: item.estimatedGrams,
            servingDescription: item.servingDescription,
            nutrition: nutrition,
            confidence: .low,
            warning: item.warning ?? "Gemini estimate only; review and edit before saving.",
            detectionSource: "gemini_fallback",
            portionEstimationMethod: .servingSizeHeuristic,
            isMixedDish: item.isMixedDish
        )
    }

    private func minConfidence(_ lhs: NutritionConfidence, _ rhs: NutritionConfidence) -> NutritionConfidence {
        lhs.rank <= rhs.rank ? lhs : rhs
    }
}

struct RemoteMealScanRequest: Equatable, Sendable {
    var normalizedImageJPEGData: Data
    var sourceImageHash: String
    var mealType: MealType
    var localeIdentifier: String
    var modelID: String
    var schemaVersion: String
    var promptVersion: String
    var revenueCatAppUserID: String?
    var firebaseAppCheckToken: String?
}

@MainActor
protocol MealScanLimitedUseAppCheckTokenProviding {
    func limitedUseToken() async throws -> String
}

struct RemoteMealScanEstimate: Equatable, Sendable {
    var response: GeminiMealEstimateResponse
    var originalResponseJSON: String
    var modelID: String
    var quota: RemoteMealScanQuota?
    var usage: RemoteMealScanUsage?
    var cacheHit: Bool = false
}

struct RemoteMealScanQuota: Codable, Equatable, Sendable {
    var accessTier: String?
    var used: Int?
    var limit: Int?
    var softLimit: Int?
    var remainingToday: Int?
    var trialUsed: Int?
    var trialLimit: Int?
    var remainingTrial: Int?
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
    var quota: RemoteMealScanQuota?
    var retryable: Bool?

    var errorDescription: String? {
        switch error {
        case "daily_scan_quota_exceeded":
            if reason == "trial_quota_exceeded" || quota?.remainingTrial == 0 {
                return "You've reached the 14-day trial photo estimate limit. Barcode lookup and manual meal logging are still available."
            }
            return "You've reached today's photo estimate limit. Barcode lookup and manual meal logging are still available."
        case "premium_entitlement_required":
            return "AI meal estimates require an active trial or subscription."
        case "app_integrity_required":
            return "CycleBalance could not verify this app install. Update the app and try again."
        case "meal_scan_unavailable":
            return "Photo estimates are temporarily unavailable. Barcode lookup and manual meal logging are still available."
        case "gemini_timeout":
            return "The photo estimate timed out. Try again, scan a barcode, or enter the meal manually."
        case "request_too_large":
            return "That photo is too large to estimate. Try another photo or enter the meal manually."
        default:
            return "Photo estimates are unavailable right now. Barcode lookup and manual meal logging are still available."
        }
    }
}

@MainActor
protocol RemoteMealScanEstimating: AnyObject {
    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate
}

struct GeminiRemoteMealScanConfiguration: Equatable, Sendable {
    static let proxyBaseURLKey = "MEAL_SCAN_PROXY_BASE_URL"
    static let defaultModelID = "gemini-2.5-flash-lite"
    static let schemaVersion = "meal-scan-gemini-v1"
    static let promptVersion = "meal-scan-prompt-v1"

    var modelID: String
    var schemaVersion: String
    var promptVersion: String
    var localeIdentifier: String
    var appBuild: String
    var proxyEndpointURL: URL?
    var revenueCatAppUserID: String?

    init(
        modelID: String = Self.defaultModelID,
        schemaVersion: String = Self.schemaVersion,
        promptVersion: String = Self.promptVersion,
        localeIdentifier: String = Locale.current.identifier,
        appBuild: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
        proxyEndpointURL: URL? = nil,
        revenueCatAppUserID: String? = nil
    ) {
        self.modelID = modelID
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.localeIdentifier = localeIdentifier
        self.appBuild = appBuild
        self.proxyEndpointURL = proxyEndpointURL
        self.revenueCatAppUserID = revenueCatAppUserID
    }

    static func from(
        bundle: Bundle = .main,
        revenueCatAppUserID: String?
    ) -> GeminiRemoteMealScanConfiguration? {
        guard let rawURL = BillingConfiguration.sanitized(
            bundle.object(forInfoDictionaryKey: proxyBaseURLKey) as? String
        ),
              let baseURL = URL(string: rawURL)
        else {
            return nil
        }

        return GeminiRemoteMealScanConfiguration(
            proxyEndpointURL: baseURL.appendingPathComponent("v1/meal-scans/estimate"),
            revenueCatAppUserID: revenueCatAppUserID
        )
    }
}

@MainActor
final class GeminiMealScanProxyClient: RemoteMealScanEstimating {
    private let endpointURL: URL
    private let urlSession: URLSession

    init(endpointURL: URL, urlSession: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.urlSession = urlSession
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let firebaseAppCheckToken = request.firebaseAppCheckToken {
            urlRequest.setValue(firebaseAppCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        let payload = ProxyRequestPayload(
            revenueCatAppUserId: request.revenueCatAppUserID,
            mealType: request.mealType.rawValue,
            locale: request.localeIdentifier,
            modelId: request.modelID,
            schemaVersion: request.schemaVersion,
            promptVersion: request.promptVersion,
            image: ProxyImagePayload(
                mimeType: "image/jpeg",
                base64: request.normalizedImageJPEGData.base64EncodedString(),
                sha256: request.sourceImageHash
            )
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(from: data, statusCode: httpResponse.statusCode)
        }

        let proxyResponse = try JSONDecoder().decode(ProxyResponsePayload.self, from: data)
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

    private func proxyError(from data: Data, statusCode: Int) -> GeminiMealScanProxyError {
        if let payload = try? JSONDecoder().decode(ProxyErrorPayload.self, from: data) {
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
final class GeminiRemoteMealScanService {
    private let remoteEstimator: any RemoteMealScanEstimating
    private let resultCache: MealScanResultCache?
    private let imageNormalizer: any MealScanImageNormalizing
    private let nutritionLookupService: any NutritionLookupService
    private let calculator: any MealNutritionCalculating
    private let configuration: GeminiRemoteMealScanConfiguration
    private let appCheckTokenProvider: (any MealScanLimitedUseAppCheckTokenProviding)?
    private let parser = GeminiMealScanResponseParser()
    private let mapper = GeminiMealScanResultMapper()

    init(
        remoteEstimator: any RemoteMealScanEstimating,
        resultCache: MealScanResultCache?,
        imageNormalizer: any MealScanImageNormalizing,
        nutritionLookupService: any NutritionLookupService,
        calculator: any MealNutritionCalculating,
        configuration: GeminiRemoteMealScanConfiguration,
        appCheckTokenProvider: (any MealScanLimitedUseAppCheckTokenProviding)? = nil
    ) {
        self.remoteEstimator = remoteEstimator
        self.resultCache = resultCache
        self.imageNormalizer = imageNormalizer
        self.nutritionLookupService = nutritionLookupService
        self.calculator = calculator
        self.configuration = configuration
        self.appCheckTokenProvider = appCheckTokenProvider
    }

    func scan(image: UIImage, mealType: MealType) async throws -> MealScanResult {
        let normalized = try imageNormalizer.normalizeJPEGData(from: image)
        let cacheKey = MealScanResultCache.cacheKey(
            modelID: configuration.modelID,
            schemaVersion: configuration.schemaVersion,
            promptVersion: configuration.promptVersion,
            normalizedImageData: normalized.jpegData,
            localeIdentifier: configuration.localeIdentifier,
            appBuild: configuration.appBuild
        )

        if let cachedJSON = try resultCache?.cachedResponseJSON(for: cacheKey) {
            let response = try parser.parseResponseJSON(cachedJSON)
            return try await mapper.map(
                response: response,
                originalResponseJSON: cachedJSON,
                mealType: mealType,
                modelID: "\(configuration.modelID)-cache",
                pipelineVersion: MealScanPipeline.pipelineVersion,
                nutritionLookupService: nutritionLookupService,
                calculator: calculator
            )
        }

        let firebaseAppCheckToken = try await appCheckTokenProvider?.limitedUseToken()

        let estimate = try await remoteEstimator.estimateMeal(
            request: RemoteMealScanRequest(
                normalizedImageJPEGData: normalized.jpegData,
                sourceImageHash: normalized.sourceImageHash,
                mealType: mealType,
                localeIdentifier: configuration.localeIdentifier,
                modelID: configuration.modelID,
                schemaVersion: configuration.schemaVersion,
                promptVersion: configuration.promptVersion,
                revenueCatAppUserID: configuration.revenueCatAppUserID,
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
        try resultCache?.saveResponseJSON(
            estimate.originalResponseJSON,
            cacheKey: cacheKey,
            modelID: estimate.modelID,
            schemaVersion: configuration.schemaVersion,
            promptVersion: configuration.promptVersion,
            confidenceScore: result.confidence.score,
            sourceImageHash: normalized.sourceImageHash
        )
        return result
    }
}

private struct ProxyRequestPayload: Encodable {
    var revenueCatAppUserId: String?
    var mealType: String
    var locale: String
    var modelId: String
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
    var quota: RemoteMealScanQuota?
    var usage: RemoteMealScanUsage?
    var cacheHit: Bool?
}

private struct ProxyErrorPayload: Decodable {
    var error: String
    var reason: String?
    var quota: RemoteMealScanQuota?
    var retryable: Bool?
}
