import Foundation
import Testing
@testable import PCOS

@Suite("SubscriptionManager")
@MainActor
struct SubscriptionManagerTests {
    final class MockBillingClient: PremiumBillingClient {
        var backendMode: BillingBackendMode = .revenueCat
        var lastStatusMessage: String?
        var entitlements: Set<String> = []
        var shouldThrowOnConfigure = false
        var checkSubscriptionStatusCallCount = 0
        var loadProductsCallCount = 0
        var purchaseCallCount = 0
        var restoreCallCount = 0
        var loadedProducts: [BillingProduct] = []
        var purchaseOutcome: BillingPurchaseOutcome = .success
        var lastPurchasedProductID: String?
        var entitlementContinuation: AsyncStream<Set<String>>.Continuation?

        func configureIfNeeded() throws {
            if shouldThrowOnConfigure {
                throw BillingClientError.missingRevenueCatAPIKey
            }
        }

        func currentEntitlements() async throws -> Set<String> {
            checkSubscriptionStatusCallCount += 1
            return entitlements
        }

        func loadProducts() async throws -> [BillingProduct] {
            loadProductsCallCount += 1
            return loadedProducts
        }

        func purchase(productID: String) async throws -> BillingPurchaseOutcome {
            purchaseCallCount += 1
            lastPurchasedProductID = productID
            return purchaseOutcome
        }

        func restorePurchases() async throws {
            restoreCallCount += 1
        }

        func makeEntitlementUpdatesStream() -> AsyncStream<Set<String>> {
            AsyncStream { continuation in
                self.entitlementContinuation = continuation
            }
        }

        func pushEntitlementUpdate(_ entitlements: Set<String>) {
            self.entitlements = entitlements
            entitlementContinuation?.yield(entitlements)
        }

        func finishEntitlementUpdates() {
            entitlementContinuation?.finish()
            entitlementContinuation = nil
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

    private func makeManager(client: MockBillingClient? = nil) -> SubscriptionManager {
        let mockClient = client ?? MockBillingClient()
        return SubscriptionManager(
            configuration: makeConfiguration(),
            clientFactory: { _ in mockClient }
        )
    }

    private func waitForEntitlementStreamReady(client: MockBillingClient) async {
        for _ in 0..<50 {
            if client.entitlementContinuation != nil {
                return
            }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("isPremium is false when no purchases exist")
    func isPremiumFalseByDefault() {
        let manager = makeManager()
        #expect(!manager.isPremium)
    }

    @Test("purchasedProductIDs starts empty")
    func purchasedIDsStartEmpty() {
        let manager = makeManager()
        #expect(manager.purchasedProductIDs.isEmpty)
    }

    @Test("Monthly product ID is correct")
    func monthlyProductID() {
        #expect(SubscriptionManager.monthlyProductID == "cyclebalance.premium.monthly")
    }

    @Test("Yearly product ID is correct")
    func yearlyProductID() {
        #expect(SubscriptionManager.yearlyProductID == "cyclebalance.premium.annual")
    }

    @Test("Client factory receives RevenueCat configuration values")
    func clientFactoryReceivesRevenueCatConfigurationValues() {
        var capturedConfiguration: BillingConfiguration?

        _ = SubscriptionManager(
            configuration: makeConfiguration(),
            clientFactory: { configuration in
                capturedConfiguration = configuration
                return MockBillingClient()
            }
        )

        #expect(capturedConfiguration?.revenueCatPublicSDKKey == "appl_test_key")
        #expect(capturedConfiguration?.backendMode == .revenueCat)
        #expect(capturedConfiguration?.revenueCatEntitlementID == "CycleBalance Unlimited")
        #expect(capturedConfiguration?.revenueCatOfferingID == "default")
        #expect(
            capturedConfiguration?.productIDs == [
                SubscriptionManager.monthlyProductID,
                SubscriptionManager.yearlyProductID,
            ]
        )
    }

    @Test("Billing configuration sanitizes quoted xcconfig values")
    func billingConfigurationSanitizesQuotedValues() {
        #expect(BillingConfiguration.sanitized("\"CycleBalance Unlimited\"") == "CycleBalance Unlimited")
        #expect(BillingConfiguration.sanitized("\"default\"") == "default")
        #expect(BillingConfiguration.sanitized(" appl_test_key ") == "appl_test_key")
        #expect(BillingConfiguration.sanitized("$(REVENUECAT_ENTITLEMENT_ID)") == nil)
    }

    @Test("checkSubscriptionStatus refreshes current entitlements")
    func checkSubscriptionStatusRefreshesEntitlements() async throws {
        let client = MockBillingClient()
        client.entitlements = [SubscriptionManager.monthlyProductID]
        client.lastStatusMessage = "diagnostic"
        let manager = makeManager(client: client)

        await manager.checkSubscriptionStatus()

        #expect(client.checkSubscriptionStatusCallCount == 1)
        #expect(manager.purchasedProductIDs == [SubscriptionManager.monthlyProductID])
        #expect(manager.isPremium)
        #expect(manager.statusMessage == "diagnostic")
    }

    @Test("loadProducts delegates through the shared billing client")
    func loadProductsDelegatesToBillingClient() async throws {
        let client = MockBillingClient()
        client.loadedProducts = [
            BillingProduct(
                id: SubscriptionManager.monthlyProductID,
                displayName: "CycleBalance Premium Monthly",
                displayPrice: "$6.99",
                price: 6.99,
                subscriptionPeriod: BillingPeriod(unit: .month, value: 1)
            ),
        ]
        client.lastStatusMessage = "products ready"

        let manager = makeManager(client: client)
        let products = try await manager.loadProducts()

        #expect(client.loadProductsCallCount == 1)
        #expect(products == client.loadedProducts)
        #expect(manager.statusMessage == "products ready")
    }

    @Test("purchase delegates to the active billing client")
    func purchaseDelegatesToBillingClient() async throws {
        let client = MockBillingClient()
        client.purchaseOutcome = .pending
        client.lastStatusMessage = "purchase pending"

        let manager = makeManager(client: client)
        let outcome = try await manager.purchase(productID: SubscriptionManager.yearlyProductID)

        #expect(client.purchaseCallCount == 1)
        #expect(client.lastPurchasedProductID == SubscriptionManager.yearlyProductID)
        #expect(outcome == .pending)
        #expect(manager.statusMessage == "purchase pending")
    }

    @Test("restorePurchases delegates to the active billing client")
    func restorePurchasesDelegatesToBillingClient() async throws {
        let client = MockBillingClient()
        client.lastStatusMessage = "restored"

        let manager = makeManager(client: client)
        try await manager.restorePurchases()

        #expect(client.restoreCallCount == 1)
        #expect(manager.statusMessage == "restored")
    }

    @Test("stopEntitlementListener stops entitlement updates after stop")
    func stopEntitlementListenerStopsUpdates() async throws {
        let client = MockBillingClient()
        let manager = makeManager(client: client)

        await waitForEntitlementStreamReady(client: client)

        let monthlyEntitlement: Set<String> = [SubscriptionManager.monthlyProductID]
        client.pushEntitlementUpdate(monthlyEntitlement)
        try await Task.sleep(for: .milliseconds(100))
        #expect(manager.purchasedProductIDs == monthlyEntitlement)

        manager.stopEntitlementListener()
        await Task.yield()

        let yearlyEntitlement: Set<String> = [SubscriptionManager.yearlyProductID]
        client.pushEntitlementUpdate(yearlyEntitlement)
        try await Task.sleep(for: .milliseconds(100))
        #expect(manager.purchasedProductIDs == monthlyEntitlement)

        client.finishEntitlementUpdates()
    }

    @Test("stopEntitlementListener is idempotent")
    func stopEntitlementListenerIsIdempotent() {
        let manager = makeManager()
        manager.stopEntitlementListener()
        manager.stopEntitlementListener()
        #expect(true)
    }
}
