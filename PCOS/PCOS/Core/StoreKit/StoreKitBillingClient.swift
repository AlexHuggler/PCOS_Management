import Foundation
import StoreKit
import os

@MainActor
final class StoreKitBillingClient: PremiumBillingClient {
    let backendMode: BillingBackendMode = .localStoreKit
    private(set) var lastStatusMessage: String?

    private let configuration: BillingConfiguration
    private var productsByID: [String: Product] = [:]

    init(configuration: BillingConfiguration) {
        self.configuration = configuration
    }

    func configureIfNeeded() throws {
        lastStatusMessage = nil
    }

    func currentEntitlements() async throws -> Set<String> {
        lastStatusMessage = nil
        return try await Self.activeEntitlementProductIDs(for: configuration.productIDs)
    }

    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>> {
        let productIDs = configuration.productIDs

        return AsyncStream { continuation in
            let updatesTask = Task {
                for await _ in Transaction.updates {
                    guard !Task.isCancelled else { break }

                    do {
                        let entitlements = try await Self.activeEntitlementProductIDs(for: productIDs)
                        continuation.yield(entitlements)
                    } catch {
                        Logger.storeKit.error("Failed to refresh StoreKit entitlement update: \(error.localizedDescription, privacy: .public)")
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                updatesTask.cancel()
            }
        }
    }

    func loadProducts() async throws -> [BillingProduct] {
        let products = try await Product.products(for: configuration.productIDs)
        guard !products.isEmpty else {
            throw BillingClientError.productsUnavailable
        }

        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })

        let orderedProducts = configuration.productIDs.compactMap { productsByID[$0] }
        return orderedProducts.map(Self.makeBillingProduct(from:))
    }

    func purchase(productID: String) async throws -> BillingPurchaseOutcome {
        let product = try await loadProduct(productID: productID)
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await transaction.finish()
            return .success
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    private func loadProduct(productID: String) async throws -> Product {
        if let cachedProduct = productsByID[productID] {
            return cachedProduct
        }

        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw BillingClientError.productNotLoaded(productID)
        }

        productsByID[productID] = product
        return product
    }

    private static func activeEntitlementProductIDs(for productIDs: [String]) async throws -> Set<String> {
        let allowedProductIDs = Set(productIDs)
        var activeProductIDs: Set<String> = []

        for await entitlement in Transaction.currentEntitlements {
            let transaction = try checkVerified(entitlement)
            guard allowedProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }

            activeProductIDs.insert(transaction.productID)
        }

        return activeProductIDs
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw BillingClientError.verificationFailed
        }
    }

    private static func makeBillingProduct(from product: Product) -> BillingProduct {
        BillingProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            price: product.price,
            subscriptionPeriod: makeBillingPeriod(from: product.subscription?.subscriptionPeriod),
            currencyCode: product.priceFormatStyle.currencyCode
        )
    }

    private static func makeBillingPeriod(from subscriptionPeriod: Product.SubscriptionPeriod?) -> BillingPeriod? {
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
