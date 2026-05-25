import Foundation
import Observation

#if DEBUG
@MainActor
protocol PremiumQAStatusProviding: AnyObject {
    var isPremium: Bool { get }
    var backendMode: BillingBackendMode { get }
    var purchasedProductIDs: Set<String> { get }
    var revenueCatAppUserID: String? { get }
    var statusMessage: String? { get }
    func checkSubscriptionStatus() async
}

extension SubscriptionManager: PremiumQAStatusProviding {}

@MainActor
@Observable
final class SettingsDebugToolsState {
    private static let revenueCatSchemeWarning = String(
        localized: "Shared PCOS scheme is RevenueCat-only. If a purchase prompt shows '[Environment: Xcode]', you're likely using the 'PCOS Local StoreKit' scheme or another local scheme with PCOS.storekit attached, and the purchase will not unlock RevenueCat premium features.",
        comment: "Debug warning shown when the app is running in RevenueCat mode and a tester might still be using an Xcode StoreKit configuration."
    )

    var jsonBackupURL: URL?
    var lastImportSummary: SettingsDataImportService.ImportSummary?
    var showImportPicker = false
    var showDebugPaywallSheet = false
    var entitlementStatus = String(localized: "Unknown", comment: "Fallback debug label when the premium entitlement status is unavailable.")
    var entitlementIDs: [String] = []
    var billingBackend = String(localized: "Unknown", comment: "Fallback debug label when the billing backend is unavailable.")
    var billingBackendWarning: String?
    var revenueCatAppUserID: String?
    var statusMessage: String?
    var appleAdsDiagnostics = AppleAdsAttributionDiagnostics.empty
    var isRefreshingPremiumStatus = false
    var isRefreshingAppleAdsDiagnostics = false

    func primePremiumStatus(
        statusProvider: any PremiumQAStatusProviding = SubscriptionManager.shared,
        appState: AppState,
        attributionService: AppleAdsAttributionService = .shared
    ) {
        entitlementStatus = statusProvider.isPremium
            ? String(localized: "Premium active", comment: "Debug premium status label.")
            : String(localized: "Free tier", comment: "Debug premium status label.")
        entitlementIDs = statusProvider.purchasedProductIDs.sorted()
        billingBackend = statusProvider.backendMode.debugDisplayName
        billingBackendWarning = Self.warningMessage(for: statusProvider.backendMode)
        revenueCatAppUserID = statusProvider.revenueCatAppUserID
        statusMessage = statusProvider.statusMessage
        appleAdsDiagnostics = attributionService.diagnostics()
        appState.isPremium = statusProvider.isPremium
    }

    func refreshPremiumStatus(
        statusProvider: any PremiumQAStatusProviding = SubscriptionManager.shared,
        appState: AppState,
        attributionService: AppleAdsAttributionService = .shared
    ) async {
        isRefreshingPremiumStatus = true
        defer { isRefreshingPremiumStatus = false }

        await statusProvider.checkSubscriptionStatus()
        entitlementStatus = statusProvider.isPremium
            ? String(localized: "Premium active", comment: "Debug premium status label.")
            : String(localized: "Free tier", comment: "Debug premium status label.")
        entitlementIDs = statusProvider.purchasedProductIDs.sorted()
        billingBackend = statusProvider.backendMode.debugDisplayName
        billingBackendWarning = Self.warningMessage(for: statusProvider.backendMode)
        revenueCatAppUserID = statusProvider.revenueCatAppUserID
        statusMessage = statusProvider.statusMessage
        appleAdsDiagnostics = attributionService.diagnostics()
        appState.isPremium = statusProvider.isPremium
    }

    func refreshAppleAdsDiagnostics(
        attributionService: AppleAdsAttributionService = .shared
    ) {
        isRefreshingAppleAdsDiagnostics = true
        defer { isRefreshingAppleAdsDiagnostics = false }

        appleAdsDiagnostics = attributionService.captureLatestTokenIfAvailable()
    }

    private static func warningMessage(for backendMode: BillingBackendMode) -> String? {
        switch backendMode {
        case .revenueCat:
            revenueCatSchemeWarning
        case .localStoreKit:
            nil
        }
    }
}
#endif
