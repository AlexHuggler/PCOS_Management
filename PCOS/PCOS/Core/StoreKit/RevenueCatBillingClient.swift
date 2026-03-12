import Foundation
import RevenueCat

@MainActor
protocol RevenueCatPurchasing: AnyObject {
    var isConfigured: Bool { get }
    func configure(apiKey: String)
    func loadProducts(offeringID: String) async throws -> [BillingProduct]
    func purchase(productID: String) async throws -> BillingPurchaseResult
    func restorePurchases(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String>
    func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String>
    func makeEntitlementUpdatesStream(entitlementID: String, fallbackProductIDs: [String]) -> AsyncStream<Set<String>>
}

@MainActor
final class RevenueCatBillingClient: PremiumBillingClient {
    let mode: BillingBackendMode = .revenuecat

    private let configuration: BillingConfiguration
    private let revenueCat: any RevenueCatPurchasing

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

        if !revenueCat.isConfigured {
            revenueCat.configure(apiKey: key)
        }
    }

    func loadProducts() async throws -> [BillingProduct] {
        try configureIfNeeded()
        return try await revenueCat.loadProducts(offeringID: configuration.revenueCatOfferingID)
    }

    func purchase(_ product: BillingProduct) async throws -> BillingPurchaseResult {
        try configureIfNeeded()
        return try await revenueCat.purchase(productID: product.id)
    }

    func restorePurchases() async throws -> Set<String> {
        try configureIfNeeded()
        return try await revenueCat.restorePurchases(
            entitlementID: configuration.revenueCatEntitlementID,
            fallbackProductIDs: configuration.productIDs
        )
    }

    func currentEntitlements() async throws -> Set<String> {
        try configureIfNeeded()
        return try await revenueCat.currentEntitlements(
            entitlementID: configuration.revenueCatEntitlementID,
            fallbackProductIDs: configuration.productIDs
        )
    }

    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>> {
        revenueCat.makeEntitlementUpdatesStream(
            entitlementID: configuration.revenueCatEntitlementID,
            fallbackProductIDs: configuration.productIDs
        )
    }
}

@MainActor
final class LiveRevenueCatPurchasing: RevenueCatPurchasing {
    private var packagesByProductID: [String: Package] = [:]

    var isConfigured: Bool { Purchases.isConfigured }

    func configure(apiKey: String) {
        if !Purchases.isConfigured {
            Purchases.configure(withAPIKey: apiKey)
        }
    }

    func loadProducts(offeringID: String) async throws -> [BillingProduct] {
        let offerings = try await Purchases.shared.offerings()

        let offering = offerings.all[offeringID] ?? offerings.current
        guard let offering else {
            throw BillingClientError.offeringNotFound(offeringID)
        }

        let sortedPackages = offering.availablePackages.sorted {
            $0.storeProduct.price < $1.storeProduct.price
        }

        packagesByProductID = Dictionary(uniqueKeysWithValues: sortedPackages.map { ($0.storeProduct.productIdentifier, $0) })

        let products = sortedPackages.map(BillingProduct.init(revenueCatPackage:))
        guard !products.isEmpty else {
            throw BillingClientError.productsUnavailable
        }
        return products
    }

    func purchase(productID: String) async throws -> BillingPurchaseResult {
        guard let package = packagesByProductID[productID] else {
            throw BillingClientError.productNotLoaded(productID)
        }

        let purchaseResult = try await Purchases.shared.purchase(package: package)
        if purchaseResult.userCancelled {
            return .userCancelled
        }

        return .purchased(productID: productID)
    }

    func restorePurchases(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
        let customerInfo = try await Purchases.shared.restorePurchases()
        return Self.activeEntitlementProductIDs(
            from: customerInfo,
            entitlementID: entitlementID,
            fallbackProductIDs: fallbackProductIDs
        )
    }

    func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
        let customerInfo = try await Purchases.shared.customerInfo()
        return Self.activeEntitlementProductIDs(
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
}

private extension BillingProduct {
    init(revenueCatPackage: Package) {
        self.init(
            id: revenueCatPackage.storeProduct.productIdentifier,
            displayName: revenueCatPackage.storeProduct.localizedTitle,
            displayPrice: revenueCatPackage.storeProduct.localizedPriceString,
            price: revenueCatPackage.storeProduct.price,
            subscriptionPeriod: revenueCatPackage.storeProduct.subscriptionPeriod.flatMap(BillingPeriod.init(revenueCatSubscriptionPeriod:))
        )
    }
}

private extension BillingPeriod {
    init?(revenueCatSubscriptionPeriod: SubscriptionPeriod) {
        let unit: BillingPeriodUnit

        switch revenueCatSubscriptionPeriod.unit {
        case .day:
            unit = .day
        case .week:
            unit = .week
        case .month:
            unit = .month
        case .year:
            unit = .year
        @unknown default:
            return nil
        }

        self.init(unit: unit, value: revenueCatSubscriptionPeriod.value)
    }
}
