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

@Suite("Apple Ads Attribution Service", .serialized)
@MainActor
struct AppleAdsAttributionServiceTests {
    private enum MockTokenError: Error {
        case unavailable
        case unsupported
    }

    final class MockTokenProvider: AppleAdsTokenProviding {
        var result: Result<String, Error>

        init(result: Result<String, Error>) {
            self.result = result
        }

        func attributionToken() throws -> String {
            try result.get()
        }
    }

    @Test("Successful capture persists diagnostics and the latest successful token")
    func successfulCapturePersistsLatestToken() throws {
        let suiteName = "AppleAdsAttributionServiceTests.success.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedDate = Date(timeIntervalSince1970: 1_717_171_717)
        let service = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("token-123")),
            now: { expectedDate }
        )

        let diagnostics = service.captureLatestTokenIfAvailable()

        #expect(diagnostics.lastResult == .success)
        #expect(diagnostics.lastAttemptedAt == expectedDate)
        let record = try #require(service.latestRecord())
        #expect(record.token == "token-123")
        #expect(record.fetchedAt == expectedDate)
        #expect(service.diagnostics().tokenPreview == "token-123")
    }

    @Test("Empty token records a no-token diagnostic result")
    func emptyTokenRecordsNoTokenResult() {
        let suiteName = "AppleAdsAttributionServiceTests.noToken.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("   ")),
            now: { Date(timeIntervalSince1970: 222) }
        )

        let diagnostics = service.captureLatestTokenIfAvailable()

        #expect(diagnostics.lastResult == .noToken)
        #expect(diagnostics.latestSuccessfulToken == nil)
        #expect(service.latestRecord() == nil)
    }

    @Test("Failed capture preserves the last successful token and records a failed result")
    func failedCaptureLeavesExistingTokenUntouched() throws {
        let suiteName = "AppleAdsAttributionServiceTests.failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialDate = Date(timeIntervalSince1970: 123)
        let updatingService = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("initial-token")),
            now: { initialDate }
        )
        updatingService.captureLatestTokenIfAvailable()

        let failingService = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .failure(MockTokenError.unavailable)),
            now: { Date(timeIntervalSince1970: 456) }
        )
        let diagnostics = failingService.captureLatestTokenIfAvailable()

        let record = try #require(failingService.latestRecord())
        #expect(record.token == "initial-token")
        #expect(record.fetchedAt == initialDate)
        #expect(diagnostics.lastResult == .failed)
        #expect(diagnostics.lastAttemptedAt == Date(timeIntervalSince1970: 456))
        #expect(diagnostics.latestSuccessfulFetchedAt == initialDate)
    }

    @Test("Subsequent captures replace the previously stored token")
    func laterCaptureReplacesStoredToken() throws {
        let suiteName = "AppleAdsAttributionServiceTests.replace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstService = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("old-token")),
            now: { Date(timeIntervalSince1970: 100) }
        )
        firstService.captureLatestTokenIfAvailable()

        let secondDate = Date(timeIntervalSince1970: 200)
        let secondService = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .success("new-token")),
            now: { secondDate }
        )
        secondService.captureLatestTokenIfAvailable()

        let record = try #require(secondService.latestRecord())
        #expect(record.token == "new-token")
        #expect(record.fetchedAt == secondDate)
        #expect(secondService.diagnostics().tokenPreview == "new-token")
    }

    @Test("Unsupported platforms record an unsupported diagnostic result")
    func unsupportedCaptureRecordsUnsupportedResult() {
        let suiteName = "AppleAdsAttributionServiceTests.unsupported.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = AppleAdsAttributionService(
            defaults: defaults,
            tokenProvider: MockTokenProvider(result: .failure(AppleAdsAttributionServiceError.unsupportedPlatform)),
            now: { Date(timeIntervalSince1970: 600) }
        )

        let diagnostics = service.captureLatestTokenIfAvailable()

        #expect(diagnostics.lastResult == .unsupported)
        #expect(diagnostics.lastAttemptedAt == Date(timeIntervalSince1970: 600))
        #expect(service.latestRecord() == nil)
    }
}
