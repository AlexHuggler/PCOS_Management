import Testing
import Foundation
@testable import PCOS

@Suite("App State Premium Routing", .serialized)
@MainActor
struct AppStatePremiumRoutingTests {
    @Test("Non-premium Insights selection changes tabs without presenting paywall")
    func nonPremiumInsightsSelectionPresentsPaywall() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = makeAppState(defaults: defaults)
        appState.selectedTab = .calendar
        appState.isPremium = false

        appState.selectTab(.insights)

        #expect(appState.selectedTab == .insights)
        #expect(!appState.showPremiumPaywall)
    }

    @Test("Premium Insights selection switches tabs without presenting paywall")
    func premiumInsightsSelectionChangesTab() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = makeAppState(defaults: defaults)
        appState.selectedTab = .today
        appState.isPremium = true

        appState.selectTab(.insights)

        #expect(appState.selectedTab == .insights)
        #expect(!appState.showPremiumPaywall)
    }

    @Test("UITest demo scenario allows Insights selection without premium entitlement")
    func uiTestDemoScenarioAllowsInsightsSelection() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            defaults: defaults,
            launchArguments: ["UITestMode", "-uiTest.demoScenario", DemoDataScenario.symptomManagement.rawValue],
            appStoreReceiptURL: makeReceiptURL(named: "receipt"),
            isDebugBuild: true
        )
        appState.selectedTab = .today
        appState.isPremium = false

        appState.selectTab(.insights)

        #expect(appState.selectedTab == .insights)
        #expect(!appState.showPremiumPaywall)
        #expect(appState.allowsPremiumAccess)
    }

    @Test("Non-premium standard tab selection still changes tabs")
    func nonPremiumStandardTabSelectionChangesTab() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = makeAppState(defaults: defaults)
        appState.selectedTab = .today
        appState.isPremium = false

        appState.selectTab(.settings)

        #expect(appState.selectedTab == .settings)
        #expect(!appState.showPremiumPaywall)
    }

    @Test("TestFlight builds unlock premium access without changing real entitlement state")
    func testFlightOverrideUnlocksPremiumAccess() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            defaults: defaults,
            launchArguments: [],
            appStoreReceiptURL: makeReceiptURL(named: "sandboxReceipt"),
            isDebugBuild: false
        )

        #expect(!appState.isPremium)
        #expect(appState.allowsPremiumAccess)
        #expect(!appState.showsSubscriptionUI)
    }

    @Test("TestFlight builds ignore paywall presentation requests")
    func testFlightOverrideSuppressesPaywallPresentation() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            defaults: defaults,
            launchArguments: [],
            appStoreReceiptURL: makeReceiptURL(named: "sandboxReceipt"),
            isDebugBuild: false
        )

        appState.presentPremiumPaywall()

        #expect(!appState.showPremiumPaywall)
    }

    @Test("Debug sandbox receipts do not trigger the TestFlight override")
    func debugSandboxReceiptDoesNotUnlockPremiumAccess() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            defaults: defaults,
            launchArguments: [],
            appStoreReceiptURL: makeReceiptURL(named: "sandboxReceipt"),
            isDebugBuild: true
        )

        #expect(!appState.allowsPremiumAccess)
        #expect(appState.showsSubscriptionUI)
    }

    @Test("Release receipts without sandbox do not trigger the TestFlight override")
    func releaseReceiptDoesNotUnlockPremiumAccess() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            defaults: defaults,
            launchArguments: [],
            appStoreReceiptURL: makeReceiptURL(named: "receipt"),
            isDebugBuild: false
        )

        #expect(!appState.allowsPremiumAccess)
        #expect(appState.showsSubscriptionUI)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppStatePremiumRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeAppState(
        defaults: UserDefaults,
        launchArguments: [String] = []
    ) -> AppState {
        AppState(
            defaults: defaults,
            launchArguments: launchArguments,
            appStoreReceiptURL: makeReceiptURL(named: "receipt"),
            isDebugBuild: true
        )
    }

    private func makeReceiptURL(named receiptName: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(receiptName)")
    }
}
