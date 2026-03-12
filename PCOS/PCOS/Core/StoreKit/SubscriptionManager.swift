import Foundation
import os

@Observable
@MainActor
final class SubscriptionManager: PremiumStatusProviding {
    static let shared = SubscriptionManager()

    // MARK: - Product Identifiers

    static let monthlyProductID = "com.cyclebalance.premium.monthly"
    static let yearlyProductID = "com.cyclebalance.premium.yearly"
    typealias BillingClientFactory = @MainActor (_ mode: BillingBackendMode, _ configuration: BillingConfiguration) -> any PremiumBillingClient

    // MARK: - Published State

    var products: [BillingProduct] = []
    var purchasedProductIDs: Set<String> = [] {
        didSet {
            guard oldValue != purchasedProductIDs else { return }
            NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: self)
        }
    }
    var isLoading = false
    var errorMessage: String?
    let billingMode: BillingBackendMode

    // MARK: - Computed Properties

    var isPremium: Bool { !purchasedProductIDs.isEmpty }
    var isLocalTestMode: Bool { billingMode == .localStoreKit }

    var monthlyProduct: BillingProduct? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var yearlyProduct: BillingProduct? {
        products.first { $0.id == Self.yearlyProductID }
    }

    // MARK: - Private

    private let billingClient: any PremiumBillingClient
    private var transactionListener: Task<Void, Never>?
    private var isClientConfigured = false

    // MARK: - Init / Deinit

    init(
        mode: BillingBackendMode = BillingBackendMode.resolved(),
        configuration: BillingConfiguration = BillingConfiguration.from(
            productIDs: [SubscriptionManager.monthlyProductID, SubscriptionManager.yearlyProductID]
        ),
        clientFactory: @escaping BillingClientFactory = SubscriptionManager.makeBillingClient
    ) {
        self.billingMode = mode
        self.billingClient = clientFactory(mode, configuration)

        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
        } catch {
            handleConfigurationFailure(error)
        }
    }

    @MainActor deinit {
        stopEntitlementListener()
    }

    // MARK: - Public API

    func load() async {
        await loadProducts()
    }

    /// Loads available subscription products from the App Store.
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            let loadedProducts = try await billingClient.loadProducts()
            products = loadedProducts
            Logger.storeKit.info("Loaded \(loadedProducts.count) subscription products using \(self.billingMode.rawValue, privacy: .public)")
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Unable to load subscriptions. Please try again."
            )
            Logger.storeKit.error("Failed to load products: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }

    /// Initiates a purchase for the given product.
    func purchase(_ product: BillingProduct) async throws {
        isLoading = true
        errorMessage = nil

        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            let result = try await billingClient.purchase(product)
            switch result {
            case .purchased(let productID):
                purchasedProductIDs.insert(productID)
                purchasedProductIDs = try await billingClient.currentEntitlements()
                Logger.storeKit.info("Purchase succeeded for \(product.id, privacy: .public)")
            case .userCancelled:
                Logger.storeKit.info("User cancelled purchase of \(product.id, privacy: .public)")
            case .pending:
                Logger.storeKit.info("Purchase pending for \(product.id, privacy: .public)")
            }
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Purchase failed. Please try again."
            )
            Logger.storeKit.error("Purchase error: \(error.localizedDescription, privacy: .public)")
            isLoading = false
            throw error
        }

        isLoading = false
    }

    func restore() async {
        await restorePurchases()
    }

    /// Restores previously purchased subscriptions.
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            purchasedProductIDs = try await billingClient.restorePurchases()
            Logger.storeKit.info("Purchases restored successfully")
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Could not restore purchases. Please try again."
            )
            Logger.storeKit.error("Restore failed: \(error.localizedDescription, privacy: .public)")
        }

        isLoading = false
    }

    /// Checks current entitlements to determine active subscriptions.
    func checkSubscriptionStatus() async {
        do {
            try ensureClientConfigured()
            startEntitlementListenerIfNeeded()
            purchasedProductIDs = try await billingClient.currentEntitlements()
            Logger.storeKit.info("Subscription status checked via \(self.billingMode.rawValue, privacy: .public)")
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Unable to refresh subscription status."
            )
            Logger.storeKit.error("Failed to check subscription status: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopEntitlementListener() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    // MARK: - Private Helpers

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
            }
        }
    }

    private func handleConfigurationFailure(_ error: Error) {
        let message = Self.userFacingMessage(
            for: error,
            fallback: "Subscription setup is incomplete."
        )
        errorMessage = message
        Logger.storeKit.error("Subscription manager configuration failed: \(error.localizedDescription, privacy: .public)")
    }

    private static func userFacingMessage(for error: Error, fallback: String) -> String {
        if let localizedError = error as? LocalizedError {
            if let description = localizedError.errorDescription, let suggestion = localizedError.recoverySuggestion {
                return "\(description) \(suggestion)"
            }

            if let description = localizedError.errorDescription {
                return description
            }
        }

        return fallback
    }

    private static func makeBillingClient(
        mode: BillingBackendMode,
        configuration: BillingConfiguration
    ) -> any PremiumBillingClient {
        switch mode {
        case .revenuecat:
            RevenueCatBillingClient(configuration: configuration)
        case .localStoreKit:
            StoreKitBillingClient(configuration: configuration)
        }
    }
}

extension Notification.Name {
    static let subscriptionStatusDidChange = Notification.Name("subscriptionStatusDidChange")
}
