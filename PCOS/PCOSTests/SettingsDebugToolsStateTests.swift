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
        let provider = MockPremiumProvider(
            isPremium: true,
            purchasedProductIDs: [SubscriptionManager.monthlyProductID]
        )

        state.primePremiumStatus(
            statusProvider: provider,
            appState: appState
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
        #expect(appState.isPremium)
    }

    @Test("refreshPremiumStatus checks provider and updates app state")
    func refreshPremiumStatusUpdatesState() async {
        let state = SettingsDebugToolsState()
        let appState = AppState()
        let provider = MockPremiumProvider(isPremium: false)

        await state.refreshPremiumStatus(
            statusProvider: provider,
            appState: appState
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
        await state.refreshPremiumStatus(
            statusProvider: provider,
            appState: appState
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
        #expect(appState.isPremium)
    }

}


#endif
