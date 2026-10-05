import Foundation

enum BillingBackendMode: String, Equatable, Sendable {
    static let launchArgumentKey = "billing.backendMode"

    case revenueCat = "revenuecat"
    case localStoreKit = "local_storekit"

    var debugDisplayName: String {
        switch self {
        case .revenueCat:
            String(localized: "RevenueCat", comment: "Debug label for the RevenueCat billing backend.")
        case .localStoreKit:
            String(localized: "Local StoreKit", comment: "Debug label for the local StoreKit billing backend.")
        }
    }

    static func current(processInfo: ProcessInfo = .processInfo) -> BillingBackendMode {
        if let override = overrideMode(in: processInfo.arguments) {
            return override
        }

        if isRunningTests(processInfo) {
            return .revenueCat
        }

#if DEBUG && targetEnvironment(simulator)
        return .localStoreKit
#else
        return .revenueCat
#endif
    }

    private static func overrideMode(in arguments: [String]) -> BillingBackendMode? {
        guard let index = arguments.firstIndex(of: "-\(launchArgumentKey)") else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return BillingBackendMode(rawValue: arguments[valueIndex].lowercased())
    }

    private static func isRunningTests(_ processInfo: ProcessInfo) -> Bool {
        let environment = processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if environment["XCInjectBundleInto"] != nil {
            return true
        }
        return processInfo.arguments.contains("UITestMode")
    }
}

struct BillingConfiguration: Sendable, Equatable {
    static let revenueCatPublicSDKKeyKey = "REVENUECAT_PUBLIC_SDK_KEY"
    static let revenueCatEntitlementIDKey = "REVENUECAT_ENTITLEMENT_ID"
    static let revenueCatOfferingIDKey = "REVENUECAT_OFFERING_ID"

    let backendMode: BillingBackendMode
    let revenueCatPublicSDKKey: String?
    let revenueCatEntitlementID: String
    let revenueCatOfferingID: String
    let productIDs: [String]

    static func from(
        bundle: Bundle = .main,
        productIDs: [String],
        backendMode: BillingBackendMode? = nil
    ) -> BillingConfiguration {
        BillingConfiguration(
            backendMode: backendMode ?? BillingBackendMode.current(),
            revenueCatPublicSDKKey: sanitized(bundle.object(forInfoDictionaryKey: revenueCatPublicSDKKeyKey) as? String),
            revenueCatEntitlementID: sanitized(bundle.object(forInfoDictionaryKey: revenueCatEntitlementIDKey) as? String) ?? "CycleBalance Unlimited",
            revenueCatOfferingID: sanitized(bundle.object(forInfoDictionaryKey: revenueCatOfferingIDKey) as? String) ?? "default",
            productIDs: productIDs
        )
    }

    static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }

        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            let unquoted = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return unquoted.isEmpty ? nil : unquoted
        }

        return trimmed
    }
}

enum BillingPurchaseOutcome: Equatable, Sendable {
    case success
    case pending
    case cancelled
}

enum BillingClientError: LocalizedError, Equatable {
    case missingRevenueCatAPIKey
    case offeringNotFound(String)
    case productNotLoaded(String)
    case productsUnavailable
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .missingRevenueCatAPIKey:
            String(localized: "RevenueCat is not configured. Add `REVENUECAT_PUBLIC_SDK_KEY` in Config/LocalSecrets.xcconfig.", comment: "Billing configuration error shown in the paywall.")
        case .offeringNotFound(let offeringID):
            String(localized: "RevenueCat offering '\(offeringID)' was not found.", comment: "Billing configuration error shown in the paywall.")
        case .productNotLoaded(let productID):
            String(localized: "The selected product '\(productID)' is not available for purchase yet.", comment: "Billing error shown when a subscription product cannot be loaded.")
        case .productsUnavailable:
            String(localized: "No subscription products are available right now.", comment: "Billing error shown when no subscription products are available.")
        case .verificationFailed:
            String(localized: "The purchase could not be verified.", comment: "Billing error shown when StoreKit transaction verification fails.")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingRevenueCatAPIKey:
            String(localized: "Set your RevenueCat public SDK key and relaunch the app.", comment: "Recovery suggestion for a missing RevenueCat API key.")
        case .offeringNotFound:
            String(localized: "Verify RevenueCat has an offering with the configured identifier and mapped packages.", comment: "Recovery suggestion for a missing RevenueCat offering.")
        case .productNotLoaded:
            String(localized: "Reload the paywall and try again.", comment: "Recovery suggestion for a paywall product loading failure.")
        case .productsUnavailable:
            String(localized: "Verify your products exist in App Store Connect and RevenueCat.", comment: "Recovery suggestion for a missing product configuration.")
        case .verificationFailed:
            String(localized: "Try the purchase again or reset the StoreKit test session.", comment: "Recovery suggestion for a failed local StoreKit verification.")
        }
    }
}

@MainActor
protocol PremiumBillingClient: AnyObject {
    var backendMode: BillingBackendMode { get }
    var lastStatusMessage: String? { get }
    var revenueCatAppUserID: String? { get }

    func configureIfNeeded() throws
    func loadProducts() async throws -> [BillingProduct]
    func purchase(productID: String) async throws -> BillingPurchaseOutcome
    func restorePurchases() async throws
    func currentEntitlements() async throws -> Set<String>
    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>>
}

extension PremiumBillingClient {
    var revenueCatAppUserID: String? { nil }
}
