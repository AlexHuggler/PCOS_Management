import Testing
import Foundation
@testable import CycleBalance

@Suite("SubscriptionManager")
@MainActor
struct SubscriptionManagerTests {
    final class MockBillingClient: PremiumBillingClient {
        let mode: BillingBackendMode
        var productsToReturn: [BillingProduct] = []
        var entitlements: Set<String> = []
        var shouldThrowOnConfigure = false
        var entitlementContinuation: AsyncStream<Set<String>>.Continuation?

        init(mode: BillingBackendMode) {
            self.mode = mode
        }

        func configureIfNeeded() throws {
            if shouldThrowOnConfigure {
                throw BillingClientError.missingRevenueCatAPIKey
            }
        }

        func loadProducts() async throws -> [BillingProduct] {
            productsToReturn
        }

        func purchase(_ product: BillingProduct) async throws -> BillingPurchaseResult {
            entitlements.insert(product.id)
            return .purchased(productID: product.id)
        }

        func restorePurchases() async throws -> Set<String> {
            entitlements
        }

        func currentEntitlements() async throws -> Set<String> {
            entitlements
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

    private func makeManager(
        mode: BillingBackendMode = .localStoreKit,
        client: MockBillingClient? = nil
    ) -> SubscriptionManager {
        let mockClient = client ?? MockBillingClient(mode: mode)
        return SubscriptionManager(
            mode: mode,
            configuration: BillingConfiguration(
                revenueCatPublicSDKKey: nil,
                revenueCatEntitlementID: "premium",
                revenueCatOfferingID: "default",
                productIDs: [
                    SubscriptionManager.monthlyProductID,
                    SubscriptionManager.yearlyProductID,
                ]
            ),
            clientFactory: { _, _ in mockClient }
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

    @Test("Products array starts empty")
    func productsStartEmpty() {
        let manager = makeManager()
        #expect(manager.products.isEmpty)
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
        #expect(SubscriptionManager.monthlyProductID == "com.cyclebalance.premium.monthly")
    }

    @Test("Yearly product ID is correct")
    func yearlyProductID() {
        #expect(SubscriptionManager.yearlyProductID == "com.cyclebalance.premium.yearly")
    }

    @Test("monthlyProduct is nil when products are empty")
    func monthlyProductNilWhenEmpty() {
        let manager = makeManager()
        #expect(manager.monthlyProduct == nil)
    }

    @Test("yearlyProduct is nil when products are empty")
    func yearlyProductNilWhenEmpty() {
        let manager = makeManager()
        #expect(manager.yearlyProduct == nil)
    }

    @Test("isLoading starts as false")
    func isLoadingStartsFalse() {
        let manager = makeManager()
        #expect(!manager.isLoading)
    }

    @Test("errorMessage starts as nil")
    func errorMessageStartsNil() {
        let manager = makeManager()
        #expect(manager.errorMessage == nil)
    }

    @Test("Backend selection uses requested mode")
    func backendSelectionUsesRequestedMode() {
        var capturedMode: BillingBackendMode?
        let manager = SubscriptionManager(
            mode: .revenuecat,
            configuration: BillingConfiguration(
                revenueCatPublicSDKKey: "test_key",
                revenueCatEntitlementID: "premium",
                revenueCatOfferingID: "default",
                productIDs: [
                    SubscriptionManager.monthlyProductID,
                    SubscriptionManager.yearlyProductID,
                ]
            ),
            clientFactory: { mode, _ in
                capturedMode = mode
                return MockBillingClient(mode: mode)
            }
        )

        #expect(capturedMode == .revenuecat)
        #expect(manager.billingMode == .revenuecat)
        #expect(!manager.isLocalTestMode)
    }

    @Test("stopEntitlementListener stops entitlement updates after stop")
    func stopEntitlementListenerStopsUpdates() async throws {
        let client = MockBillingClient(mode: .localStoreKit)
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
