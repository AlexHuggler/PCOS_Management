import Foundation
import os

@Observable
@MainActor
final class SubscriptionManager: PremiumStatusProviding {
    static let shared = SubscriptionManager()

    static let monthlyProductID = "cyclebalance.premium.monthly"
    static let yearlyProductID = "cyclebalance.premium.annual"
    /// One-time "exit offer": a yearly plan at a lower price, in the same subscription group,
    /// shown once after a paywall is closed without buying. Must be created in App Store Connect,
    /// attached to the Premium entitlement in RevenueCat and added to the `exit_offer` offering.
    static let exitOfferProductID = "cyclebalance.premium.annual.offer"
    static let exitOfferOfferingID = "exit_offer"
    typealias BillingClientFactory = @MainActor (_ configuration: BillingConfiguration) -> any PremiumBillingClient

    var purchasedProductIDs: Set<String> = [] {
        didSet {
            guard oldValue != purchasedProductIDs else { return }
            NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: self)
        }
    }

    var isPremium: Bool { !purchasedProductIDs.isEmpty }
    var backendMode: BillingBackendMode { billingClient.backendMode }
    var revenueCatAppUserID: String? { billingClient.revenueCatAppUserID }
    var statusMessage: String?

    private let billingClient: any PremiumBillingClient
    private var transactionListener: Task<Void, Never>?
    private var isClientConfigured = false

    init(
        configuration: BillingConfiguration = BillingConfiguration.from(
            productIDs: [SubscriptionManager.monthlyProductID, SubscriptionManager.yearlyProductID],
            additionalEntitlementProductIDs: [SubscriptionManager.exitOfferProductID]
        ),
        clientFactory: @escaping BillingClientFactory = SubscriptionManager.makeBillingClient
    ) {
        self.billingClient = clientFactory(configuration)

        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
        } catch {
            Logger.storeKit.error("Subscription manager configuration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor deinit {
        stopEntitlementListener()
    }

    func checkSubscriptionStatus() async {
        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            purchasedProductIDs = try await billingClient.currentEntitlements()
            statusMessage = billingClient.lastStatusMessage
            Logger.storeKit.info("Subscription status checked via \(self.backendMode.rawValue, privacy: .public)")
        } catch {
            statusMessage = error.localizedDescription
            Logger.storeKit.error("Failed to check subscription status: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadProducts() async throws -> [BillingProduct] {
        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            let products = try await billingClient.loadProducts()
            statusMessage = billingClient.lastStatusMessage
            return products
        } catch {
            statusMessage = error.localizedDescription
            throw error
        }
    }

    func purchase(productID: String) async throws -> BillingPurchaseOutcome {
        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            let outcome = try await billingClient.purchase(productID: productID)
            statusMessage = billingClient.lastStatusMessage
            return outcome
        } catch {
            statusMessage = error.localizedDescription
            throw error
        }
    }

    func restorePurchases() async throws {
        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            try await billingClient.restorePurchases()
            statusMessage = billingClient.lastStatusMessage
        } catch {
            statusMessage = error.localizedDescription
            throw error
        }
    }

    /// Loads the exit-offer product if it is configured; nil otherwise (never throws).
    func loadExitOfferProduct() async -> BillingProduct? {
        do {
            try ensureClientConfigured()
        } catch {
            return nil
        }
        return await billingClient.loadOptionalProduct(
            productID: Self.exitOfferProductID,
            offeringID: Self.exitOfferOfferingID
        )
    }

    func stopEntitlementListener() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    private func ensureClientConfigured() throws {
        guard !isClientConfigured else { return }
        try billingClient.configureIfNeeded()
        isClientConfigured = true
    }

    private func startEntitlementListenerIfNeeded() {
        guard transactionListener == nil else { return }
        let billingClient = self.billingClient
        transactionListener = Task { [weak self] in
            for await entitlements in billingClient.makeEntitlementUpdatesStream() {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.purchasedProductIDs = entitlements
                self.statusMessage = billingClient.lastStatusMessage
            }
        }
    }

    private static func makeBillingClient(
        configuration: BillingConfiguration
    ) -> any PremiumBillingClient {
        switch configuration.backendMode {
        case .revenueCat:
            RevenueCatBillingClient(configuration: configuration)
        case .localStoreKit:
            StoreKitBillingClient(configuration: configuration)
        }
    }
}

extension Notification.Name {
    static let subscriptionStatusDidChange = Notification.Name("subscriptionStatusDidChange")
}
