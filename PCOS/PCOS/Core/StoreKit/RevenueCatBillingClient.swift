import Foundation
import RevenueCat
import StoreKit

@MainActor
protocol RevenueCatPurchasing: AnyObject {
    var isConfigured: Bool { get }
    var appUserID: String { get }
    func configure(apiKey: String)
    func loadOffering(offeringID: String) async throws -> Offering
    func purchase(package: Package) async throws -> BillingPurchaseOutcome
    func restorePurchases() async throws
    func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String>
    func entitlementStatusNote(entitlementID: String, fallbackProductIDs: [String]) async throws -> String?
    func makeEntitlementUpdatesStream(entitlementID: String, fallbackProductIDs: [String]) -> AsyncStream<Set<String>>
}

@MainActor
final class RevenueCatBillingClient: PremiumBillingClient {
    let backendMode: BillingBackendMode = .revenueCat
    private(set) var lastStatusMessage: String?
    var revenueCatAppUserID: String? { revenueCat.appUserID }

    private let configuration: BillingConfiguration
    private let revenueCat: any RevenueCatPurchasing
    private var packagesByProductID: [String: Package] = [:]

    init(
        configuration: BillingConfiguration,
        revenueCat: any RevenueCatPurchasing = LiveRevenueCatPurchasing()
    ) {
        self.configuration = configuration
        self.revenueCat = revenueCat
    }

    func configureIfNeeded() throws {
        guard let key = configuration.revenueCatPublicSDKKey else {
            throw BillingClientError.missingRevenueCatAPIKey
        }

        lastStatusMessage = nil

        if !revenueCat.isConfigured {
            revenueCat.configure(apiKey: key)
        }
    }

    func loadOffering() async throws -> Offering {
        try configureIfNeeded()
        return try await revenueCat.loadOffering(offeringID: configuration.revenueCatOfferingID)
    }

    func loadProducts() async throws -> [BillingProduct] {
        try configureIfNeeded()
        let offering = try await revenueCat.loadOffering(offeringID: configuration.revenueCatOfferingID)
        let resolvedPackages = try Self.resolvePackages(
            from: offering,
            productIDs: configuration.productIDs
        )
        packagesByProductID = resolvedPackages
        lastStatusMessage = nil

        return configuration.productIDs.compactMap { productID in
            resolvedPackages[productID].map(Self.makeBillingProduct(from:))
        }
    }

    func purchase(productID: String) async throws -> BillingPurchaseOutcome {
        try configureIfNeeded()
        let package = try await loadPackage(productID: productID)
        let outcome = try await revenueCat.purchase(package: package)
        lastStatusMessage = nil
        return outcome
    }

    func restorePurchases() async throws {
        try configureIfNeeded()
        try await revenueCat.restorePurchases()
        lastStatusMessage = nil
    }

    func currentEntitlements() async throws -> Set<String> {
        try configureIfNeeded()
        let customerInfoProductIDs = try await revenueCat.currentEntitlements(
            entitlementID: configuration.revenueCatEntitlementID,
            fallbackProductIDs: configuration.productIDs
        )
        lastStatusMessage = try await revenueCat.entitlementStatusNote(
            entitlementID: configuration.revenueCatEntitlementID,
            fallbackProductIDs: configuration.productIDs
        )
        return customerInfoProductIDs
    }

    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>> {
        let entitlementID = configuration.revenueCatEntitlementID
        let fallbackProductIDs = configuration.productIDs

        return AsyncStream { continuation in
            let updatesTask = Task {
                for await entitlements in revenueCat.makeEntitlementUpdatesStream(
                    entitlementID: entitlementID,
                    fallbackProductIDs: fallbackProductIDs
                ) {
                    guard !Task.isCancelled else { break }
                    self.lastStatusMessage = nil
                    continuation.yield(entitlements)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                updatesTask.cancel()
            }
        }
    }

    private func loadPackage(productID: String) async throws -> Package {
        if let package = packagesByProductID[productID] {
            return package
        }

        _ = try await loadProducts()

        guard let package = packagesByProductID[productID] else {
            throw BillingClientError.productNotLoaded(productID)
        }

        return package
    }

    private static func resolvePackages(
        from offering: Offering,
        productIDs: [String]
    ) throws -> [String: Package] {
        var packagesByProductID: [String: Package] = [:]

        for productID in productIDs {
            guard let package = offering.availablePackages.first(where: {
                $0.storeProduct.productIdentifier == productID
            }) else {
                throw BillingClientError.productNotLoaded(productID)
            }

            packagesByProductID[productID] = package
        }

        return packagesByProductID
    }

    private static func makeBillingProduct(from package: Package) -> BillingProduct {
        let product = package.storeProduct
        return BillingProduct(
            id: product.productIdentifier,
            displayName: product.localizedTitle,
            displayPrice: product.localizedPriceString,
            price: product.price,
            subscriptionPeriod: makeBillingPeriod(from: product.subscriptionPeriod),
            currencyCode: product.currencyCode
        )
    }

    private static func makeBillingPeriod(from subscriptionPeriod: RevenueCat.SubscriptionPeriod?) -> BillingPeriod? {
        guard let subscriptionPeriod else { return nil }

        let unit: BillingPeriodUnit
        switch subscriptionPeriod.unit {
        case .day:
            unit = .day
        case .week:
            unit = .week
        case .month:
            unit = .month
        case .year:
            unit = .year
        @unknown default:
            unit = .month
        }

        return BillingPeriod(unit: unit, value: subscriptionPeriod.value)
    }
}

@MainActor
final class LiveRevenueCatPurchasing: RevenueCatPurchasing {
    var isConfigured: Bool { Purchases.isConfigured }
    var appUserID: String { Purchases.shared.appUserID }

    func configure(apiKey: String) {
        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: apiKey)
        }
    }

    func loadOffering(offeringID: String) async throws -> Offering {
        let offerings = try await Purchases.shared.offerings()
        return try Self.resolveOffering(from: offerings, offeringID: offeringID)
    }

    func purchase(package: Package) async throws -> BillingPurchaseOutcome {
        do {
            let purchaseResult = try await Purchases.shared.purchase(package: package)
            return purchaseResult.userCancelled ? .cancelled : .success
        } catch {
            if Self.isPendingPurchaseError(error) {
                return .pending
            }

            if Self.isCancelledPurchaseError(error) {
                return .cancelled
            }

            throw error
        }
    }

    func restorePurchases() async throws {
        _ = try await Purchases.shared.restorePurchases()
    }

    func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
        let customerInfo = try await Purchases.shared.customerInfo()
        return Self.activeEntitlementProductIDs(
            from: customerInfo,
            entitlementID: entitlementID,
            fallbackProductIDs: fallbackProductIDs
        )
    }

    func entitlementStatusNote(entitlementID: String, fallbackProductIDs: [String]) async throws -> String? {
        let customerInfo = try await Purchases.shared.customerInfo()
        return Self.entitlementStatusNote(
            from: customerInfo,
            entitlementID: entitlementID,
            fallbackProductIDs: fallbackProductIDs
        )
    }

    func makeEntitlementUpdatesStream(entitlementID: String, fallbackProductIDs: [String]) -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            let updatesTask = Task {
                for await customerInfo in Purchases.shared.customerInfoStream {
                    guard !Task.isCancelled else { break }
                    continuation.yield(
                        Self.activeEntitlementProductIDs(
                            from: customerInfo,
                            entitlementID: entitlementID,
                            fallbackProductIDs: fallbackProductIDs
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                updatesTask.cancel()
            }
        }
    }

    private static func resolveOffering(from offerings: Offerings, offeringID: String) throws -> Offering {
        let offering = offerings.all[offeringID] ?? offerings.current
        guard let offering else {
            throw BillingClientError.offeringNotFound(offeringID)
        }

        guard !offering.availablePackages.isEmpty else {
            throw BillingClientError.productsUnavailable
        }

        return offering
    }

    private static func activeEntitlementProductIDs(
        from customerInfo: CustomerInfo,
        entitlementID: String,
        fallbackProductIDs: [String]
    ) -> Set<String> {
        guard customerInfo.entitlements[entitlementID]?.isActive == true else {
            return []
        }

        let activeSubscriptions = Set(customerInfo.activeSubscriptions)
        if activeSubscriptions.isEmpty {
            return Set(fallbackProductIDs)
        }

        return activeSubscriptions
    }

    private static func entitlementStatusNote(
        from customerInfo: CustomerInfo,
        entitlementID: String,
        fallbackProductIDs: [String]
    ) -> String? {
#if DEBUG
        let entitlementIsActive = customerInfo.entitlements[entitlementID]?.isActive == true
        let activeSubscriptions = customerInfo.activeSubscriptions.sorted()

        guard !entitlementIsActive, !activeSubscriptions.isEmpty else {
            return nil
        }

        let productList = activeSubscriptions.joined(separator: ", ")
        return String(
            localized: "RevenueCat saw active subscriptions (\(productList)) but entitlement '\(entitlementID)' is inactive. Verify the entitlement mapping for these product IDs: \(fallbackProductIDs.joined(separator: ", ")).",
            comment: "Debug billing message shown when RevenueCat sees active subscriptions but the configured entitlement is inactive."
        )
#else
        return nil
#endif
    }

    private static func isCancelledPurchaseError(_ error: Error) -> Bool {
        if let errorCode = error as? RevenueCat.ErrorCode {
            return errorCode == .purchaseCancelledError
        }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain, nsError.code == SKError.paymentCancelled.rawValue {
            return true
        }

        return nsError.code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue
    }

    private static func isPendingPurchaseError(_ error: Error) -> Bool {
        if let errorCode = error as? RevenueCat.ErrorCode {
            return errorCode == .paymentPendingError
        }

        let nsError = error as NSError
        return nsError.code == RevenueCat.ErrorCode.paymentPendingError.rawValue
    }
}
