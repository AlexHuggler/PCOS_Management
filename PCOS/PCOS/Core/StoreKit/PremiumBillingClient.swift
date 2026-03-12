import Foundation

struct BillingConfiguration: Sendable, Equatable {
    static let revenueCatPublicSDKKeyKey = "REVENUECAT_PUBLIC_SDK_KEY"
    static let revenueCatEntitlementIDKey = "REVENUECAT_ENTITLEMENT_ID"
    static let revenueCatOfferingIDKey = "REVENUECAT_OFFERING_ID"

    let revenueCatPublicSDKKey: String?
    let revenueCatEntitlementID: String
    let revenueCatOfferingID: String
    let productIDs: [String]

    static func from(
        bundle: Bundle = .main,
        productIDs: [String]
    ) -> BillingConfiguration {
        BillingConfiguration(
            revenueCatPublicSDKKey: sanitized(bundle.object(forInfoDictionaryKey: revenueCatPublicSDKKeyKey) as? String),
            revenueCatEntitlementID: sanitized(bundle.object(forInfoDictionaryKey: revenueCatEntitlementIDKey) as? String) ?? "premium",
            revenueCatOfferingID: sanitized(bundle.object(forInfoDictionaryKey: revenueCatOfferingIDKey) as? String) ?? "default",
            productIDs: productIDs
        )
    }

    private static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}

enum BillingPurchaseResult: Equatable, Sendable {
    case purchased(productID: String)
    case userCancelled
    case pending
}

enum BillingClientError: LocalizedError, Equatable {
    case missingRevenueCatAPIKey
    case offeringNotFound(String)
    case productNotLoaded(String)
    case productsUnavailable

    var errorDescription: String? {
        switch self {
        case .missingRevenueCatAPIKey:
            "RevenueCat is not configured. Add `REVENUECAT_PUBLIC_SDK_KEY` in Config/LocalSecrets.xcconfig."
        case .offeringNotFound(let offeringID):
            "RevenueCat offering '\(offeringID)' was not found."
        case .productNotLoaded(let productID):
            "The selected product '\(productID)' is not available for purchase yet."
        case .productsUnavailable:
            "No subscription products are available right now."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingRevenueCatAPIKey:
            "Set your RevenueCat public SDK key and relaunch the app."
        case .offeringNotFound:
            "Verify RevenueCat has an offering with the configured identifier and mapped packages."
        case .productNotLoaded:
            "Reload the paywall and try again."
        case .productsUnavailable:
            "Verify your products exist in App Store Connect and RevenueCat."
        }
    }
}

@MainActor
protocol PremiumBillingClient: AnyObject {
    var mode: BillingBackendMode { get }
    func configureIfNeeded() throws
    func loadProducts() async throws -> [BillingProduct]
    func purchase(_ product: BillingProduct) async throws -> BillingPurchaseResult
    func restorePurchases() async throws -> Set<String>
    func currentEntitlements() async throws -> Set<String>
    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>>
}
