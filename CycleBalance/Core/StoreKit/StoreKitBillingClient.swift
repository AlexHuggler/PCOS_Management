import Foundation
import StoreKit
import os

@MainActor
final class StoreKitBillingClient: PremiumBillingClient {
    typealias UpdatesStreamFactory = () -> AsyncStream<Void>
    typealias EntitlementRefresher = () async throws -> Set<String>

    let mode: BillingBackendMode = .localStoreKit

    private let productIDs: [String]
    private var productsByID: [String: Product] = [:]
    private let updatesStreamFactory: UpdatesStreamFactory
    private let entitlementRefresherOverride: EntitlementRefresher?
    private var lastKnownEntitlements: Set<String> = []

    init(
        configuration: BillingConfiguration,
        updatesStreamFactory: @escaping UpdatesStreamFactory = StoreKitBillingClient.defaultUpdatesStream,
        entitlementRefresher: EntitlementRefresher? = nil
    ) {
        self.productIDs = configuration.productIDs
        self.updatesStreamFactory = updatesStreamFactory
        self.entitlementRefresherOverride = entitlementRefresher
    }

    func configureIfNeeded() throws {}

    func loadProducts() async throws -> [BillingProduct] {
        let products = try await Product.products(for: productIDs)
        let sortedProducts = products.sorted { $0.price < $1.price }
        productsByID = Dictionary(uniqueKeysWithValues: sortedProducts.map { ($0.id, $0) })
        let mappedProducts = sortedProducts.map(BillingProduct.init(storeKitProduct:))

        guard !mappedProducts.isEmpty else {
            throw BillingClientError.productsUnavailable
        }

        return mappedProducts
    }

    func purchase(_ product: BillingProduct) async throws -> BillingPurchaseResult {
        guard let storeProduct = productsByID[product.id] else {
            throw BillingClientError.productNotLoaded(product.id)
        }

        let result = try await storeProduct.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return .purchased(productID: transaction.productID)
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws -> Set<String> {
        try await AppStore.sync()
        return try await currentEntitlements()
    }

    func currentEntitlements() async throws -> Set<String> {
        var activePurchases: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else {
                continue
            }

            if transaction.revocationDate != nil {
                continue
            }

            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }

            activePurchases.insert(transaction.productID)
        }

        lastKnownEntitlements = activePurchases
        return activePurchases
    }

    func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>> {
        AsyncStream { continuation in
            let updateTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                for await _ in self.updatesStreamFactory() {
                    guard !Task.isCancelled else { break }
                    do {
                        let entitlements = try await self.refreshEntitlements()
                        self.lastKnownEntitlements = entitlements
                        continuation.yield(entitlements)
                    } catch {
                        Logger.storeKit.error(
                            "Failed to refresh StoreKit entitlements from updates stream: \(error.localizedDescription, privacy: .public)"
                        )
                        continuation.yield(self.lastKnownEntitlements)
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                updateTask.cancel()
            }
        }
    }

    private func refreshEntitlements() async throws -> Set<String> {
        if let entitlementRefresherOverride {
            return try await entitlementRefresherOverride()
        }
        return try await currentEntitlements()
    }

    nonisolated private static func defaultUpdatesStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in Transaction.updates {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            value
        case .unverified(_, let error):
            throw error
        }
    }
}

private extension BillingProduct {
    init(storeKitProduct: Product) {
        self.init(
            id: storeKitProduct.id,
            displayName: storeKitProduct.displayName,
            displayPrice: storeKitProduct.displayPrice,
            price: storeKitProduct.price,
            subscriptionPeriod: storeKitProduct.subscription.flatMap {
                BillingPeriod(storeKitSubscriptionPeriod: $0.subscriptionPeriod)
            }
        )
    }
}

private extension BillingPeriod {
    init?(storeKitSubscriptionPeriod: Product.SubscriptionPeriod) {
        let unit: BillingPeriodUnit

        switch storeKitSubscriptionPeriod.unit {
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

        self.init(unit: unit, value: storeKitSubscriptionPeriod.value)
    }
}
