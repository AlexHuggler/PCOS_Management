import Testing
import Foundation
@testable import PCOS

@Suite("RevenueCatBillingClient")
@MainActor
struct RevenueCatBillingClientTests {
    final class MockRevenueCatPurchasing: RevenueCatPurchasing {
        var isConfigured = false
        var configuredAPIKey: String?
        var products: [BillingProduct] = []
        var purchaseResult: BillingPurchaseResult = .userCancelled
        var entitlements: Set<String> = []
        var lastOfferingID: String?
        var lastEntitlementID: String?
        var lastFallbackProductIDs: [String] = []

        func configure(apiKey: String) {
            isConfigured = true
            configuredAPIKey = apiKey
        }

        func loadProducts(offeringID: String) async throws -> [BillingProduct] {
            lastOfferingID = offeringID
            return products
        }

        func purchase(productID: String) async throws -> BillingPurchaseResult {
            purchaseResult
        }

        func restorePurchases(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
            lastEntitlementID = entitlementID
            lastFallbackProductIDs = fallbackProductIDs
            return entitlements
        }

        func currentEntitlements(entitlementID: String, fallbackProductIDs: [String]) async throws -> Set<String> {
            lastEntitlementID = entitlementID
            lastFallbackProductIDs = fallbackProductIDs
            return entitlements
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
                revenueCatPublicSDKKey: nil,
                revenueCatEntitlementID: "premium",
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

    @Test("Loads products through configured offering")
    func loadsProductsForOffering() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.products = [
            BillingProduct(
                id: SubscriptionManager.monthlyProductID,
                displayName: "Monthly",
                displayPrice: "$9.99",
                price: 9.99,
                subscriptionPeriod: BillingPeriod(unit: .month, value: 1)
            ),
        ]

        let client = RevenueCatBillingClient(
            configuration: BillingConfiguration(
                revenueCatPublicSDKKey: "appl_test_key",
                revenueCatEntitlementID: "premium",
                revenueCatOfferingID: "default",
                productIDs: [SubscriptionManager.monthlyProductID]
            ),
            revenueCat: provider
        )

        let products = try await client.loadProducts()

        #expect(provider.isConfigured)
        #expect(provider.configuredAPIKey == "appl_test_key")
        #expect(provider.lastOfferingID == "default")
        #expect(products.count == 1)
        #expect(products.first?.id == SubscriptionManager.monthlyProductID)
    }

    @Test("Entitlement requests use configured entitlement and fallback products")
    func entitlementRequestsUseConfiguredValues() async throws {
        let provider = MockRevenueCatPurchasing()
        provider.entitlements = [SubscriptionManager.yearlyProductID]

        let fallbackProducts = [
            SubscriptionManager.monthlyProductID,
            SubscriptionManager.yearlyProductID,
        ]

        let client = RevenueCatBillingClient(
            configuration: BillingConfiguration(
                revenueCatPublicSDKKey: "appl_test_key",
                revenueCatEntitlementID: "premium",
                revenueCatOfferingID: "default",
                productIDs: fallbackProducts
            ),
            revenueCat: provider
        )

        let entitlementSet = try await client.currentEntitlements()

        #expect(provider.lastEntitlementID == "premium")
        #expect(provider.lastFallbackProductIDs == fallbackProducts)
        #expect(entitlementSet == [SubscriptionManager.yearlyProductID])
    }
}
