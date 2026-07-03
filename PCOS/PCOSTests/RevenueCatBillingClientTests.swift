import Foundation
import RevenueCat
import Testing
@testable import PCOS

@Suite("RevenueCatBillingClient")
@MainActor
struct RevenueCatBillingClientTests {
    private enum MockProviderError: Error {
        case placeholder
    }

    final class MockRevenueCatPurchasing: RevenueCatPurchasing {
        var isConfigured = false
        var appUserID = "$RCAnonymousID:test-user"
        var configuredAPIKey: String?
        var entitlements: Set<String> = []
        var statusNote: String?
        var lastOfferingID: String?
        var loadOfferingCallCount = 0
        var lastEntitlementID: String?
        var lastFallbackProductIDs: [String] = []
        var lastPurchasedPackage: Package?
        var purchaseResult: Result<BillingPurchaseOutcome, Error> = .success(.success)
        var restoreCallCount = 0
        var loadOfferingResult: Result<Offering, Error> = .failure(MockProviderError.placeholder)

        func configure(apiKey: String) {
            isConfigured = true
            configuredAPIKey = apiKey
        }

        func loadOffering(offeringID: String) async throws -> Offering {
            lastOfferingID = offeringID
            loadOfferingCallCount += 1
            return try loadOfferingResult.get()
        }

        func purchase(package: Package) async throws -> BillingPurchaseOutcome {
            lastPurchasedPackage = package
            return try purchaseResult.get()
        }

        func restorePurchases() async throws {
            restoreCallCount += 1
        }

        func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
            lastEntitlementID = entitlementID
            lastFallbackProductIDs = fallbackProductIDs
            return entitlements
        }

        func entitlementStatusNote(entitlementID: String, fallbackProductIDs: [String]) async throws -> String? {
            lastEntitlementID = entitlementID
            lastFallbackProductIDs = fallbackProductIDs
            return statusNote
        }

        func makeEntitlementUpdatesStream(entitlementID: String, fallbackProductIDs: [String]) -> AsyncStream<Set<String>> {
            lastEntitlementID = entitlementID
            lastFallbackProductIDs = fallbackProductIDs
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
    }

    @Test("Missing SDK key surfaces a setup error")
    func missingSDKKeyThrows() async {
        let provider = MockRevenueCatPurchasing()
        let client = RevenueCatBillingClient(
            configuration: BillingConfiguration(
                backendMode: .revenueCat,
                revenueCatPublicSDKKey: nil,
                revenueCatEntitlementID: "CycleBalance Unlimited",
                revenueCatOfferingID: "default",
                productIDs: [SubscriptionManager.monthlyProductID]
            ),
            revenueCat: provider
        )

        do {
            _ = try await client.loadProducts()
            Issue.record("Expected missing SDK key error")
        } catch let error as BillingClientError {
            #expect(error == .missingRevenueCatAPIKey)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Paywall products load from the configured offering and map into billing products")
    func loadProductsUsesConfiguredOfferingIdentifier() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.loadOfferingResult = .success(makeOffering())

        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        let products = try await client.loadProducts()

        #expect(provider.isConfigured)
        #expect(provider.configuredAPIKey == "appl_test_key")
        #expect(provider.lastOfferingID == "default")
        #expect(products.map(\.id) == [SubscriptionManager.monthlyProductID, SubscriptionManager.yearlyProductID])
        #expect(products.first?.displayPrice == "$9.99")
        #expect(products.last?.displayPrice == "$79.99")
        #expect(products.first?.subscriptionPeriod == BillingPeriod(unit: .month, value: 1))
        #expect(products.last?.subscriptionPeriod == BillingPeriod(unit: .year, value: 1))
    }

    @Test("Purchase resolves package by product id and reuses cached packages")
    func purchaseUsesResolvedPackage() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.loadOfferingResult = .success(makeOffering())

        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        _ = try await client.loadProducts()
        let outcome = try await client.purchase(productID: SubscriptionManager.yearlyProductID)

        #expect(outcome == .success)
        #expect(provider.loadOfferingCallCount == 1)
        #expect(provider.lastPurchasedPackage?.storeProduct.productIdentifier == SubscriptionManager.yearlyProductID)
    }

    @Test("Purchase loads products on demand if the package cache is empty")
    func purchaseLoadsProductsOnDemand() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.loadOfferingResult = .success(makeOffering())

        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        let outcome = try await client.purchase(productID: SubscriptionManager.monthlyProductID)

        #expect(outcome == .success)
        #expect(provider.loadOfferingCallCount == 1)
        #expect(provider.lastPurchasedPackage?.storeProduct.productIdentifier == SubscriptionManager.monthlyProductID)
    }

    @Test("Purchase returns cancellation and pending states from RevenueCat")
    func purchaseReturnsNonSuccessOutcomes() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.loadOfferingResult = .success(makeOffering())
        provider.purchaseResult = .success(.cancelled)

        let cancelledClient = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )
        let cancelledOutcome = try await cancelledClient.purchase(productID: SubscriptionManager.monthlyProductID)
        #expect(cancelledOutcome == .cancelled)

        provider.purchaseResult = .success(.pending)
        let pendingOutcome = try await cancelledClient.purchase(productID: SubscriptionManager.monthlyProductID)
        #expect(pendingOutcome == .pending)
    }

    @Test("Restore purchases delegates to RevenueCat")
    func restorePurchasesDelegates() async throws {
        let provider = MockRevenueCatPurchasing()
        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        try await client.restorePurchases()

        #expect(provider.restoreCallCount == 1)
    }

    @Test("Entitlement requests use configured entitlement and fallback products")
    func entitlementRequestsUseConfiguredValues() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.entitlements = [SubscriptionManager.yearlyProductID]
        provider.statusNote = "entitlement mismatch"

        let fallbackProducts = [
            SubscriptionManager.monthlyProductID,
            SubscriptionManager.yearlyProductID,
        ]

        let client = RevenueCatBillingClient(
            configuration: BillingConfiguration(
                backendMode: .revenueCat,
                revenueCatPublicSDKKey: "appl_test_key",
                revenueCatEntitlementID: "CycleBalance Unlimited",
                revenueCatOfferingID: "default",
                productIDs: fallbackProducts
            ),
            revenueCat: provider
        )

        let entitlementSet = try await client.currentEntitlements()

        #expect(provider.lastEntitlementID == "CycleBalance Unlimited")
        #expect(provider.lastFallbackProductIDs == fallbackProducts)
        #expect(entitlementSet == [SubscriptionManager.yearlyProductID])
        #expect(client.lastStatusMessage == "entitlement mismatch")
    }

    @Test("RevenueCat debug app user id is exposed for QA diagnostics")
    func exposesRevenueCatAppUserID() {
        let provider = MockRevenueCatPurchasing()
        provider.appUserID = "$RCAnonymousID:qa-user"
        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        #expect(client.revenueCatAppUserID == "$RCAnonymousID:qa-user")
    }

    @Test("Product loading fails when the configured offering is missing a required product")
    func loadProductsFailsForMissingConfiguredPackage() async {
        let provider = MockRevenueCatPurchasing()
        provider.loadOfferingResult = .success(
            makeOffering(includeYearlyPackage: false)
        )
        let client = RevenueCatBillingClient(
            configuration: makeConfiguration(),
            revenueCat: provider
        )

        do {
            _ = try await client.loadProducts()
            Issue.record("Expected missing product error")
        } catch let error as BillingClientError {
            #expect(error == .productNotLoaded(SubscriptionManager.yearlyProductID))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    private func makeConfiguration() -> BillingConfiguration {
        BillingConfiguration(
            backendMode: .revenueCat,
            revenueCatPublicSDKKey: "appl_test_key",
            revenueCatEntitlementID: "CycleBalance Unlimited",
            revenueCatOfferingID: "default",
            productIDs: [
                SubscriptionManager.monthlyProductID,
                SubscriptionManager.yearlyProductID,
            ]
        )
    }

    private func makeOffering(includeYearlyPackage: Bool = true) -> Offering {
        let offeringIdentifier = "default"
        var packages = [
            Package(
                identifier: "monthly",
                packageType: .monthly,
                storeProduct: makeStoreProduct(
                    localizedTitle: "CycleBalance Premium Monthly",
                    price: 9.99,
                    localizedPriceString: "$9.99",
                    productIdentifier: SubscriptionManager.monthlyProductID,
                    subscriptionPeriod: .init(value: 1, unit: .month)
                ),
                offeringIdentifier: offeringIdentifier,
                webCheckoutUrl: nil
            ),
        ]

        if includeYearlyPackage {
            packages.append(
                Package(
                    identifier: "annual",
                    packageType: .annual,
                    storeProduct: makeStoreProduct(
                        localizedTitle: "CycleBalance Annual",
                        price: 79.99,
                        localizedPriceString: "$79.99",
                        productIdentifier: SubscriptionManager.yearlyProductID,
                        subscriptionPeriod: .init(value: 1, unit: .year)
                    ),
                    offeringIdentifier: offeringIdentifier,
                    webCheckoutUrl: nil
                )
            )
        }

        return Offering(
            identifier: offeringIdentifier,
            serverDescription: "CycleBalance Default Offering",
            metadata: [:],
            availablePackages: packages,
            webCheckoutUrl: nil
        )
    }

    private func makeStoreProduct(
        localizedTitle: String,
        price: Decimal,
        localizedPriceString: String,
        productIdentifier: String,
        subscriptionPeriod: RevenueCat.SubscriptionPeriod
    ) -> StoreProduct {
        TestStoreProduct(
            localizedTitle: localizedTitle,
            price: price,
            currencyCode: "USD",
            localizedPriceString: localizedPriceString,
            productIdentifier: productIdentifier,
            productType: .autoRenewableSubscription,
            localizedDescription: localizedTitle,
            subscriptionGroupIdentifier: "cyclebalance",
            subscriptionPeriod: subscriptionPeriod,
            locale: Locale(identifier: "en_US")
        )
        .toStoreProduct()
    }
}
