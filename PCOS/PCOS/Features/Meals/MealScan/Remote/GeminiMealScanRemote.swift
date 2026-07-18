import CryptoKit
import Foundation
import Network
import SwiftData
import StoreKit
import UIKit

enum GeminiMealScanParsingError: LocalizedError, Equatable {
    case invalidJSON
    case emptyEstimate

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            L10n.string(
                "Gemini returned a meal estimate CycleBalance could not read.",
                defaultValue: "Gemini returned a meal estimate CycleBalance could not read."
            )
        case .emptyEstimate:
            L10n.string(
                "Gemini did not return any foods to review.",
                defaultValue: "Gemini did not return any foods to review."
            )
        }
    }
}

enum GeminiMealScanMappingError: LocalizedError, Equatable {
    case missingNutritionEstimate(itemName: String)

    var errorDescription: String? {
        switch self {
        case .missingNutritionEstimate(let itemName):
            L10n.format(
                "CycleBalance did not receive complete nutrition for %@. Nothing was added to your meal log.",
                defaultValue: "CycleBalance did not receive complete nutrition for %@. Nothing was added to your meal log.",
                itemName
            )
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
            warning: item.warning,
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
        L10n.string(
            "CycleBalance could not find a verified active monthly or annual subscription.",
            defaultValue: "CycleBalance could not find a verified active monthly or annual subscription."
        )
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

enum MealScanConnectivityStatus: Equatable, Sendable {
    case online
    case offline
    case unknown
}

@MainActor
protocol MealScanConnectivityChecking: AnyObject {
    func connectivityStatus() -> MealScanConnectivityStatus
}

final class NetworkMealScanConnectivityChecker: MealScanConnectivityChecking, @unchecked Sendable {
    static let shared = NetworkMealScanConnectivityChecker()

    private let monitor: NWPathMonitor
    private let lock = NSLock()
    private var latestStatus: MealScanConnectivityStatus = .unknown

    private init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateStatus(for: path.status)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.cyclebalance.meal-scan-connectivity"))
    }

    deinit {
        monitor.cancel()
    }

    func connectivityStatus() -> MealScanConnectivityStatus {
        lock.lock()
        defer { lock.unlock() }
        return latestStatus
    }

    private func updateStatus(for status: NWPath.Status) {
        let resolvedStatus: MealScanConnectivityStatus
        switch status {
        case .satisfied:
            resolvedStatus = .online
        case .unsatisfied:
            resolvedStatus = .offline
        case .requiresConnection:
            resolvedStatus = .unknown
        @unknown default:
            resolvedStatus = .unknown
        }

        lock.lock()
        latestStatus = resolvedStatus
        lock.unlock()
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

    var localizedTierDisplayName: String {
        switch tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "paid", "subscriber":
            L10n.string("paid", defaultValue: "paid")
        case "trial":
            L10n.string("trial", defaultValue: "trial")
        case "sandbox", "test":
            L10n.string("sandbox", defaultValue: "sandbox")
        default:
            L10n.string("standard", defaultValue: "standard")
        }
    }
}

struct MealScanOutcome: Equatable, Sendable {
    var result: MealScanResult
    var quota: MealScanQuota?
    var source: MealScanAnalysisSource

    var cacheDisposition: MealScanCacheDisposition {
        switch source {
        case .exactPrevious, .localCache:
            .local
        case .serverCache:
            .server
        case .fresh:
            .fresh
        }
    }

    var consumption: MealScanConsumptionState {
        source.consumption
    }

    init(
        result: MealScanResult,
        quota: MealScanQuota?,
        source: MealScanAnalysisSource
    ) {
        self.result = result
        self.quota = quota
        self.source = source
    }

    init(
        result: MealScanResult,
        quota: MealScanQuota?,
        cacheDisposition: MealScanCacheDisposition,
        consumption _: MealScanConsumptionState? = nil
    ) {
        self.result = result
        self.quota = quota
        source = switch cacheDisposition {
        case .fresh: .fresh
        case .server: .serverCache
        case .local: .localCache
        }
    }
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

struct GeminiMealScanProxyError: LocalizedError, Equatable, Sendable, MealScanFailureProviding {
    var statusCode: Int
    var error: String
    var reason: String?
    var quota: MealScanQuota?
    var retryable: Bool?
    var retryAfterSeconds: Int? = nil
    var detail: String? = nil
    var idempotencyState: String? = nil

    var mealScanFailure: MealScanFailure {
        let errorKey = error.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reasonKey = reason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let detailKey = detail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let retryTiming = retryAfterSeconds ?? quota?.retryAfterSeconds

        func failure(
            kind: MealScanFailureKind,
            cause: MealScanFailureCause,
            consumption: MealScanConsumptionState,
            retryBehavior: MealScanRetryBehavior
        ) -> MealScanFailure {
            MealScanFailure(
                kind: kind,
                cause: cause,
                consumption: consumption,
                retryBehavior: retryBehavior,
                quota: quota,
                retryAfterSeconds: retryTiming
            )
        }

        if errorKey == "feature_disabled" || reasonKey == "feature_disabled" {
            return failure(
                kind: .serviceDisabled,
                cause: .featureDisabled,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        let configurationReasons = Set([
            "storekit_verifier_unconfigured",
            "subscription_status_unconfigured",
            "revenuecat_subscription_unconfigured",
            "app_check_verifier_unconfigured",
        ])
        if configurationReasons.contains(reasonKey ?? "") {
            return failure(
                kind: .serviceDisabled,
                cause: .serviceControlUnavailable,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        let budgetReasons = Set([
            "monthly_budget_exceeded",
            "trial_dispatch_disabled_by_budget",
        ])
        if budgetReasons.contains(reasonKey ?? "") {
            return failure(
                kind: .serviceDisabled,
                cause: .budgetDispatchDisabled,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        let unavailableEntitlementReasons = Set([
            "storekit_verification_unavailable",
            "subscription_status_unavailable",
            "revenuecat_subscription_unavailable",
            "revenuecat_subscription_not_synced",
        ])
        if unavailableEntitlementReasons.contains(reasonKey ?? "") {
            return failure(
                kind: .entitlement,
                cause: .entitlementEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if reasonKey == "integrity_service_timeout" {
            return failure(
                kind: .appIntegrity,
                cause: .appIntegrityEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if errorKey == "meal_scan_unavailable" {
            return failure(
                kind: .serviceDisabled,
                cause: .serviceControlUnavailable,
                consumption: .notUsed,
                retryBehavior: retryable == true ? .retrySameRequest : .none
            )
        }

        if errorKey == "app_integrity_required"
            || errorKey.contains("app_integrity")
            || reasonKey?.hasPrefix("app_check_") == true
            || reasonKey == "integrity_failed" {
            return failure(
                kind: .appIntegrity,
                cause: .appIntegrityRejected,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if errorKey == "premium_entitlement_required"
            || errorKey.contains("entitlement") {
            return failure(
                kind: .entitlement,
                cause: .entitlementRejected,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if errorKey == "meal_scan_request_rate_limited"
            || errorKey == "provider_dispatch_rate_limited" {
            return failure(
                kind: .serviceDisabled,
                cause: .requestRateLimited,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if errorKey == "rolling_scan_quota_exceeded"
            || errorKey == "quota_exceeded"
            || reasonKey?.contains("quota_exceeded") == true {
            return failure(
                kind: .quotaExhausted,
                cause: .quotaExhausted,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        if errorKey == "invalid_request" {
            if detailKey?.contains("signedtransactionjws") == true {
                return failure(
                    kind: .entitlement,
                    cause: .entitlementRejected,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            }
            let imageDetail = ["jpeg", "image", "pixel", "canonical"]
                .contains { detailKey?.contains($0) == true }
            return failure(
                kind: imageDetail ? .unreadableMeal : .ambiguousResult,
                cause: imageDetail ? .invalidImage : .invalidRequest,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        if errorKey == "invalid_json" {
            return failure(
                kind: .ambiguousResult,
                cause: .invalidRequest,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        if errorKey == "request_too_large"
            || errorKey == "image_too_large"
            || reasonKey == "image_too_large" {
            return failure(
                kind: .unreadableMeal,
                cause: .invalidImage,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        if errorKey == "idempotency_conflict" {
            return failure(
                kind: .ambiguousResult,
                cause: .idempotencyConflict,
                consumption: .unknown,
                retryBehavior: .none
            )
        }

        if errorKey == "meal_scan_in_progress" {
            if reasonKey == "principal_dispatch_in_progress" {
                return failure(
                    kind: .serviceDisabled,
                    cause: .requestPending,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            }
            return failure(
                kind: .ambiguousResult,
                cause: .requestPending,
                consumption: .unknown,
                retryBehavior: .checkSameRequest
            )
        }

        if errorKey == "meal_scan_parse_error" {
            return failure(
                kind: .unreadableMeal,
                cause: .providerResponseInvalid,
                consumption: .used,
                retryBehavior: .none
            )
        }

        if errorKey == "meal_scan_provider_error" {
            return failure(
                kind: .ambiguousResult,
                cause: .providerRequestFailed,
                consumption: .used,
                retryBehavior: .checkSameRequest
            )
        }

        if errorKey == "gemini_timeout"
            || errorKey == "provider_timeout"
            || reasonKey == "provider_timeout" {
            return failure(
                kind: .connectionInterruptedAfterDispatch,
                cause: .providerTimeout,
                consumption: .used,
                retryBehavior: .checkSameRequest
            )
        }

        if errorKey == "meal_scan_outcome_unknown" {
            return failure(
                kind: .ambiguousResult,
                cause: reasonKey == "provider_dispatch_outcome_unknown"
                    ? .providerDispatchOutcomeUnknown
                    : .serverOutcomeUnknown,
                consumption: .used,
                retryBehavior: .checkSameRequest
            )
        }

        if errorKey == "meal_scan_proxy_error" {
            return failure(
                kind: .serviceDisabled,
                cause: .serviceControlUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        }

        if errorKey == "not_found" {
            return failure(
                kind: .serviceDisabled,
                cause: .invalidRequest,
                consumption: .notUsed,
                retryBehavior: .none
            )
        }

        return failure(
            kind: .ambiguousResult,
            cause: .unclassified,
            consumption: .unknown,
            retryBehavior: .checkSameRequest
        )
    }

    var errorDescription: String? {
        switch error {
        case "rolling_scan_quota_exceeded":
            if reason == "trial_lifetime_quota_exceeded" {
                return L10n.string(
                    "You've used the lifetime trial AI photo analysis allowance. Scan a barcode or enter the meal manually.",
                    defaultValue: "You've used the lifetime trial AI photo analysis allowance. Scan a barcode or enter the meal manually."
                )
            }
            if let quota {
                return L10n.format(
                    "You've used all %lld fresh AI photo analyses in the current rolling 24-hour %@ allowance. Scan a barcode or enter the meal manually while the window resets.",
                    defaultValue: "You've used all %lld fresh AI photo analyses in the current rolling 24-hour %@ allowance. Scan a barcode or enter the meal manually while the window resets.",
                    Int64(quota.limit),
                    quota.localizedTierDisplayName
                )
            }
            return L10n.string(
                "You've used all fresh AI photo analyses in the current rolling 24-hour allowance. Scan a barcode or enter the meal manually while the window resets.",
                defaultValue: "You've used all fresh AI photo analyses in the current rolling 24-hour allowance. Scan a barcode or enter the meal manually while the window resets."
            )
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

enum MealScanRemoteError: LocalizedError, Equatable, Sendable, MealScanFailureProviding {
    case imageTooLarge(actualBytes: Int, maximumBytes: Int)
    case requestBodyTooLarge(actualBytes: Int, maximumBytes: Int)
    case subscriptionEvidenceUnavailable
    case appIntegrityEvidenceUnavailable
    case offlineBeforeDispatch
    case outcomeUnknown(requestID: UUID)
    case providerTimeoutAfterDispatch(requestID: UUID, retryAfterSeconds: Int?)
    case providerDispatchOutcomeUnknown(requestID: UUID, retryAfterSeconds: Int?)
    case serverOutcomeUnknown(requestID: UUID, retryAfterSeconds: Int?)
    case requestPending(requestID: UUID, retryAfterSeconds: Int?)
    case principalDispatchInProgress(requestID: UUID, retryAfterSeconds: Int?)

    var mealScanFailure: MealScanFailure {
        switch self {
        case .imageTooLarge, .requestBodyTooLarge:
            MealScanFailure(
                kind: .unreadableMeal,
                cause: .invalidImage,
                consumption: .notUsed,
                retryBehavior: .none
            )
        case .subscriptionEvidenceUnavailable:
            MealScanFailure(
                kind: .entitlement,
                cause: .entitlementEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        case .appIntegrityEvidenceUnavailable:
            MealScanFailure(
                kind: .appIntegrity,
                cause: .appIntegrityEvidenceUnavailable,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        case .offlineBeforeDispatch:
            MealScanFailure(
                kind: .offlineBeforeDispatch,
                cause: .offline,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest
            )
        case .outcomeUnknown:
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .transportOutcomeUnknown,
                consumption: .unknown,
                retryBehavior: .checkSameRequest
            )
        case .providerTimeoutAfterDispatch(_, let retryAfterSeconds):
            MealScanFailure(
                kind: .connectionInterruptedAfterDispatch,
                cause: .providerTimeout,
                consumption: .used,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: retryAfterSeconds
            )
        case .providerDispatchOutcomeUnknown(_, let retryAfterSeconds):
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .providerDispatchOutcomeUnknown,
                consumption: .used,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: retryAfterSeconds
            )
        case .serverOutcomeUnknown(_, let retryAfterSeconds):
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .serverOutcomeUnknown,
                consumption: .used,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: retryAfterSeconds
            )
        case .requestPending(_, let retryAfterSeconds):
            MealScanFailure(
                kind: .ambiguousResult,
                cause: .requestPending,
                consumption: .unknown,
                retryBehavior: .checkSameRequest,
                retryAfterSeconds: retryAfterSeconds
            )
        case .principalDispatchInProgress(_, let retryAfterSeconds):
            MealScanFailure(
                kind: .serviceDisabled,
                cause: .requestPending,
                consumption: .notUsed,
                retryBehavior: .retrySameRequest,
                retryAfterSeconds: retryAfterSeconds
            )
        }
    }

    var errorDescription: String? {
        switch self {
        case .imageTooLarge:
            L10n.string(
                "That photo could not be reduced to the secure upload limit. Try another photo or enter the meal manually.",
                defaultValue: "That photo could not be reduced to the secure upload limit. Try another photo or enter the meal manually."
            )
        case .requestBodyTooLarge:
            L10n.string(
                "That photo request is too large to send. Try another photo or enter the meal manually.",
                defaultValue: "That photo request is too large to send. Try another photo or enter the meal manually."
            )
        case .subscriptionEvidenceUnavailable:
            L10n.string(
                "CycleBalance could not verify an active App Store subscription for this analysis.",
                defaultValue: "CycleBalance could not verify an active App Store subscription for this analysis."
            )
        case .appIntegrityEvidenceUnavailable:
            L10n.string(
                "CycleBalance could not verify this app install. Update the app and try again.",
                defaultValue: "CycleBalance could not verify this app install. Update the app and try again."
            )
        case .offlineBeforeDispatch:
            L10n.string(
                "You're offline. Reconnect and try this photo again.",
                defaultValue: "You're offline. Reconnect and try this photo again."
            )
        case .outcomeUnknown:
            L10n.string(
                "CycleBalance could not confirm whether this analysis completed. Checking again with the same request is safe; starting a new analysis may use another fresh analysis.",
                defaultValue: "CycleBalance could not confirm whether this analysis completed. Checking again with the same request is safe; starting a new analysis may use another fresh analysis."
            )
        case .providerTimeoutAfterDispatch:
            L10n.string(
                "The connection was interrupted after analysis started. Check this photo again before starting a new analysis.",
                defaultValue: "The connection was interrupted after analysis started. Check this photo again before starting a new analysis."
            )
        case .providerDispatchOutcomeUnknown, .serverOutcomeUnknown:
            L10n.string(
                "CycleBalance could not confirm the previous result. Check this photo again before starting a new analysis.",
                defaultValue: "CycleBalance could not confirm the previous result. Check this photo again before starting a new analysis."
            )
        case .requestPending(_, let retryAfterSeconds):
            if let retryAfterSeconds {
                L10n.format(
                    "This analysis is still processing. Check the same request again in about %lld seconds.",
                    defaultValue: "This analysis is still processing. Check the same request again in about %lld seconds.",
                    Int64(retryAfterSeconds)
                )
            } else {
                L10n.string(
                    "This analysis is still processing. Check the same request again shortly.",
                    defaultValue: "This analysis is still processing. Check the same request again shortly."
                )
            }
        case .principalDispatchInProgress:
            L10n.string(
                "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually.",
                defaultValue: "Photo estimates are unavailable right now. Scan a barcode or enter the meal manually."
            )
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

    static func from(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> GeminiRemoteMealScanConfiguration? {
        let bundledRawURL = BillingConfiguration.sanitized(
            bundle.object(forInfoDictionaryKey: proxyBaseURLKey) as? String
        )

#if DEBUG
        let rawURL = arguments.contains("UITestMode")
            ? BillingConfiguration.sanitized(environment[proxyBaseURLKey]) ?? bundledRawURL
            : bundledRawURL
#else
        let rawURL = bundledRawURL
#endif

        guard let rawURL,
              let baseURL = URL(string: rawURL)
        else {
            return nil
        }

        return GeminiRemoteMealScanConfiguration(
            proxyEndpointURL: baseURL.appendingPathComponent("v1/meal-scans/estimate")
        )
    }
}

struct MealScanCanaryCorrelation: Equatable, Sendable {
    static let launchArgument = "--cyclebalance-meal-scan-canary-id"

    let canaryID: UUID

    var headerValue: String {
        canaryID.uuidString.lowercased()
    }

    static func from(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        isDevelopmentSigned: Bool = Self.isDevelopmentSignedRuntime()
    ) -> MealScanCanaryCorrelation? {
        guard isDevelopmentSigned else { return nil }

        let matchingIndexes = arguments.indices.filter { arguments[$0] == launchArgument }
        guard matchingIndexes.count == 1,
              let valueIndex = matchingIndexes.first.map({ arguments.index(after: $0) }),
              arguments.indices.contains(valueIndex),
              let canaryID = UUID(uuidString: arguments[valueIndex])
        else {
            return nil
        }

        return MealScanCanaryCorrelation(canaryID: canaryID)
    }

    func operationTag(for requestID: UUID) -> String {
        Self.sha256Hex(requestID.uuidString.lowercased())
    }

    private static func isDevelopmentSignedRuntime() -> Bool {
        guard let profileURL = Bundle.main.url(
            forResource: "embedded",
            withExtension: "mobileprovision"
        ),
              let profileData = try? Data(contentsOf: profileURL),
              let plistStart = profileData.range(of: Data("<?xml".utf8)),
              let plistEnd = profileData.range(
                  of: Data("</plist>".utf8),
                  options: .backwards
              ),
              plistStart.lowerBound < plistEnd.upperBound,
              let profile = try? PropertyListSerialization.propertyList(
                  from: profileData[plistStart.lowerBound..<plistEnd.upperBound],
                  options: [],
                  format: nil
              ) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any]
        else {
            return false
        }
        return (entitlements["get-task-allow"] as? Bool) == true
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
final class GeminiMealScanProxyClient: RemoteMealScanEstimating {
    static let maximumImageBytes = 1_500_000
    static let maximumRequestBodyBytes = 2_200_000

    private let endpointURL: URL
    private let urlSession: URLSession
    private let canaryCorrelation: MealScanCanaryCorrelation?

    init(
        endpointURL: URL,
        urlSession: URLSession = .shared,
        canaryCorrelation: MealScanCanaryCorrelation? = MealScanCanaryCorrelation.from()
    ) {
        self.endpointURL = endpointURL
        self.urlSession = urlSession
        self.canaryCorrelation = canaryCorrelation
    }

    func estimateMeal(request: RemoteMealScanRequest) async throws -> RemoteMealScanEstimate {
        guard request.normalizedImageJPEGData.count <= Self.maximumImageBytes else {
            throw MealScanRemoteError.imageTooLarge(
                actualBytes: request.normalizedImageJPEGData.count,
                maximumBytes: Self.maximumImageBytes
            )
        }

        guard let firebaseAppCheckToken = request.firebaseAppCheckToken?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !firebaseAppCheckToken.isEmpty
        else {
            throw MealScanRemoteError.appIntegrityEvidenceUnavailable
        }

        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(firebaseAppCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        let canaryOperationTag: String?
        if let canaryCorrelation {
            canaryOperationTag = canaryCorrelation.operationTag(for: request.requestID)
            urlRequest.setValue(
                canaryCorrelation.headerValue,
                forHTTPHeaderField: "X-CycleBalance-Canary-ID"
            )
            urlRequest.setValue(
                canaryOperationTag,
                forHTTPHeaderField: "X-CycleBalance-Canary-Operation"
            )
        } else {
            canaryOperationTag = nil
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
            if let canaryOperationTag {
                print("CYCLEBALANCE_CANARY_OPERATION tag=\(canaryOperationTag)")
            }
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where Self.isDefinitePreDispatchFailure(error.code) {
            throw MealScanRemoteError.offlineBeforeDispatch
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
            if payload.reason == "principal_dispatch_in_progress" {
                return MealScanRemoteError.principalDispatchInProgress(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            if payload.error == "meal_scan_in_progress" || payload.idempotency?.state == "pending" {
                return MealScanRemoteError.requestPending(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            if payload.error == "meal_scan_outcome_unknown", payload.reason == "provider_timeout" {
                return MealScanRemoteError.providerTimeoutAfterDispatch(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            if payload.error == "meal_scan_outcome_unknown",
               payload.reason == "provider_dispatch_outcome_unknown" {
                return MealScanRemoteError.providerDispatchOutcomeUnknown(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            if payload.error == "meal_scan_outcome_unknown" {
                return MealScanRemoteError.serverOutcomeUnknown(
                    requestID: requestID,
                    retryAfterSeconds: payload.retryAfterSeconds
                )
            }
            return GeminiMealScanProxyError(
                statusCode: statusCode,
                error: payload.error,
                reason: payload.reason,
                quota: payload.quota,
                retryable: payload.retryable,
                retryAfterSeconds: payload.retryAfterSeconds,
                detail: payload.detail,
                idempotencyState: payload.idempotency?.state
            )
        }

        return MealScanRemoteError.outcomeUnknown(requestID: requestID)
    }

    private static func isDefinitePreDispatchFailure(_ code: URLError.Code) -> Bool {
        switch code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            true
        default:
            false
        }
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
    private let connectivityChecker: any MealScanConnectivityChecking
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
        connectivityChecker: any MealScanConnectivityChecking = NetworkMealScanConnectivityChecker.shared,
        appCheckTokenProvider: (any MealScanLimitedUseAppCheckTokenProviding)? = nil,
        storeKitEvidenceProvider: any MealScanStoreKitEvidenceProviding = StoreKitMealScanEvidenceProvider()
    ) {
        self.remoteEstimator = remoteEstimator
        self.resultCache = resultCache
        self.imageNormalizer = imageNormalizer
        self.nutritionLookupService = nutritionLookupService
        self.calculator = calculator
        self.configuration = configuration
        self.connectivityChecker = connectivityChecker
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

        if connectivityChecker.connectivityStatus() == .offline {
            throw MealScanRemoteError.offlineBeforeDispatch
        }

        let signedTransactionJWS: String
        do {
            signedTransactionJWS = try await storeKitEvidenceProvider.signedTransactionJWS()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MealScanRemoteError.subscriptionEvidenceUnavailable
        }

        let firebaseAppCheckToken: String?
        do {
            firebaseAppCheckToken = try await appCheckTokenProvider?.limitedUseToken()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MealScanRemoteError.appIntegrityEvidenceUnavailable
        }
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

        let result: MealScanResult
        do {
            result = try await mapper.map(
                response: estimate.response,
                originalResponseJSON: estimate.originalResponseJSON,
                mealType: mealType,
                modelID: estimate.modelID,
                pipelineVersion: MealScanPipeline.pipelineVersion,
                nutritionLookupService: nutritionLookupService,
                calculator: calculator
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MealScanFailure(
                kind: .unreadableMeal,
                cause: .providerResponseInvalid,
                consumption: estimate.cacheHit ? .notUsed : .used,
                retryBehavior: .none,
                quota: estimate.quota
            )
        }
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
            source: estimate.cacheHit ? .serverCache : .fresh
        )
    }

    func cachedOutcome(
        normalizedImage: NormalizedMealScanImage,
        mealType: MealType
    ) async throws -> MealScanOutcome? {
        let cacheKey = cacheKey(for: normalizedImage, mealType: mealType)
        guard let resultCache else {
            return nil
        }

        let cachedJSON: String
        do {
            guard let responseJSON = try resultCache.cachedResponseJSON(
                for: cacheKey,
                now: Date()
            ) else {
                return nil
            }
            cachedJSON = responseJSON
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }

        do {
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
            return MealScanOutcome(
                result: result,
                quota: nil,
                source: .localCache
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                try resultCache.removeCachedResponse(for: cacheKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MealScanFailure(
                    kind: .ambiguousResult,
                    cause: .unclassified,
                    consumption: .notUsed,
                    retryBehavior: .retrySameRequest
                )
            }
            return nil
        }
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
    var detail: String?
    var quota: MealScanQuota?
    var retryable: Bool?
    var retryAfterSeconds: Int?
    var idempotency: ProxyIdempotencyPayload?
}

private struct ProxyIdempotencyPayload: Decodable {
    var state: String?
}
