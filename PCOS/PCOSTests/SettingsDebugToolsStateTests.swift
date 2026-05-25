#if DEBUG
import Foundation
import Testing
@testable import PCOS

@Suite("Settings Debug Tools State", .serialized)
@MainActor
struct SettingsDebugToolsStateTests {
    final class MockPremiumProvider: PremiumQAStatusProviding {
        var isPremium: Bool
        var backendMode: BillingBackendMode
        var purchasedProductIDs: Set<String>
        var revenueCatAppUserID: String?
        var statusMessage: String?
        var checkCallCount = 0

        init(
            isPremium: Bool = false,
            backendMode: BillingBackendMode = .localStoreKit,
            purchasedProductIDs: Set<String> = [],
            revenueCatAppUserID: String? = nil,
            statusMessage: String? = nil
        ) {
            self.isPremium = isPremium
            self.backendMode = backendMode
            self.purchasedProductIDs = purchasedProductIDs
            self.revenueCatAppUserID = revenueCatAppUserID
            self.statusMessage = statusMessage
        }

        func checkSubscriptionStatus() async {
            checkCallCount += 1
        }
    }

    @Test("primePremiumStatus surfaces entitlement state")
    func primePremiumStatusSurfacesState() {
        let state = SettingsDebugToolsState()
        let appState = AppState()
        let diagnosticsService = AppleAdsAttributionService(
            defaults: UserDefaults(suiteName: "SettingsDebugToolsStateTests.prime.\(UUID().uuidString)")!,
            tokenProvider: MockTokenProvider(result: .success("token-123")),
            now: { Date(timeIntervalSince1970: 100) }
        )
        let provider = MockPremiumProvider(
            isPremium: true,
            purchasedProductIDs: [SubscriptionManager.monthlyProductID]
        )

        state.primePremiumStatus(
            statusProvider: provider,
            appState: appState,
            attributionService: diagnosticsService
        )

        #expect(
            state.entitlementStatus == String(
                localized: "Premium active",
                comment: "Debug premium status label."
            )
        )
        #expect(state.billingBackend == BillingBackendMode.localStoreKit.debugDisplayName)
        #expect(state.billingBackendWarning == nil)
        #expect(state.entitlementIDs == [SubscriptionManager.monthlyProductID])
        #expect(state.appleAdsDiagnostics.lastResult == nil)
        #expect(appState.isPremium)
    }

    @Test("refreshPremiumStatus checks provider and updates app state")
    func refreshPremiumStatusUpdatesState() async {
        let state = SettingsDebugToolsState()
        let appState = AppState()
        let diagnosticsSuiteName = "SettingsDebugToolsStateTests.refresh.\(UUID().uuidString)"
        let diagnosticsDefaults = UserDefaults(suiteName: diagnosticsSuiteName)!
        defer { diagnosticsDefaults.removePersistentDomain(forName: diagnosticsSuiteName) }
        let diagnosticsService = AppleAdsAttributionService(
            defaults: diagnosticsDefaults,
            tokenProvider: MockTokenProvider(result: .success("token-456")),
            now: { Date(timeIntervalSince1970: 200) }
        )
        let provider = MockPremiumProvider(isPremium: false)

        await state.refreshPremiumStatus(
            statusProvider: provider,
            appState: appState,
            attributionService: diagnosticsService
        )
        #expect(provider.checkCallCount == 1)
        #expect(
            state.entitlementStatus == String(
                localized: "Free tier",
                comment: "Debug premium status label."
            )
        )
        #expect(state.billingBackend == BillingBackendMode.localStoreKit.debugDisplayName)
        #expect(state.billingBackendWarning == nil)
        #expect(!appState.isPremium)

        provider.isPremium = true
        provider.backendMode = .revenueCat
        provider.purchasedProductIDs = [SubscriptionManager.yearlyProductID]
        provider.revenueCatAppUserID = "$RCAnonymousID:qa-user"
        provider.statusMessage = "entitlement mismatch"
        diagnosticsService.captureLatestTokenIfAvailable()
        await state.refreshPremiumStatus(
            statusProvider: provider,
            appState: appState,
            attributionService: diagnosticsService
        )

        #expect(provider.checkCallCount == 2)
        #expect(
            state.entitlementStatus == String(
                localized: "Premium active",
                comment: "Debug premium status label."
            )
        )
        #expect(state.billingBackend == BillingBackendMode.revenueCat.debugDisplayName)
        #expect(state.entitlementIDs == [SubscriptionManager.yearlyProductID])
        #expect(state.revenueCatAppUserID == "$RCAnonymousID:qa-user")
        #expect(state.billingBackendWarning?.contains("PCOS Local StoreKit") == true)
        #expect(state.billingBackendWarning?.contains("[Environment: Xcode]") == true)
        #expect(state.billingBackendWarning?.contains("PCOS.storekit") == true)
        #expect(state.statusMessage == "entitlement mismatch")
        #expect(state.appleAdsDiagnostics.lastResult == .success)
        #expect(appState.isPremium)
    }

    @Test("refreshAppleAdsDiagnostics updates the stored attribution snapshot")
    func refreshAppleAdsDiagnosticsUpdatesState() {
        let suiteName = "SettingsDebugToolsStateTests.appleAds.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = SettingsDebugToolsState()
        let diagnosticsService = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("token-789")),
            now: { Date(timeIntervalSince1970: 300) }
        )

        state.refreshAppleAdsDiagnostics(attributionService: diagnosticsService)

        #expect(state.appleAdsDiagnostics.lastResult == .success)
        #expect(state.appleAdsDiagnostics.tokenPreview == "token-789")
    }
}

private enum MockTokenError: Error {
    case unavailable
}

private final class MockTokenProvider: AppleAdsTokenProviding {
    var result: Result<String, Error>

    init(result: Result<String, Error>) {
        self.result = result
    }

    func attributionToken() throws -> String {
        try result.get()
    }
}
#endif
