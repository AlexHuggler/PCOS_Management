import Testing
import Foundation
@testable import PCOS

@Suite("PremiumStateBridge", .serialized)
@MainActor
struct PremiumStateBridgeTests {
    final class MockPremiumStatusProvider: PremiumStatusProviding {
        var isPremium = false
        var checkCallCount = 0

        func checkSubscriptionStatus() async {
            checkCallCount += 1
        }
    }

    @Test("sync updates app state with provider entitlement")
    func syncUpdatesAppState() async {
        let appState = AppState()
        appState.isPremium = false

        let provider = MockPremiumStatusProvider()
        provider.isPremium = true

        let bridge = PremiumStateBridge(statusProvider: provider)
        await bridge.sync(appState: appState)

        #expect(provider.checkCallCount == 1)
        #expect(appState.isPremium)
    }

    @Test("notification-driven updates refresh app state")
    func notificationRefreshesAppState() async throws {
        let appState = AppState()
        appState.isPremium = false

        let provider = MockPremiumStatusProvider()
        provider.isPremium = false

        let bridge = PremiumStateBridge(statusProvider: provider)
        bridge.start(appState: appState)
        defer { bridge.stop() }
        await Task.yield()

        provider.isPremium = true
        NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.isPremium)
    }

    @Test("stop cancels notification observation and prevents further refresh")
    func stopPreventsFurtherNotificationRefresh() async throws {
        let appState = AppState()
        appState.isPremium = false

        let provider = MockPremiumStatusProvider()
        provider.isPremium = false

        let bridge = PremiumStateBridge(statusProvider: provider)
        bridge.start(appState: appState)
        await Task.yield()

        provider.isPremium = true
        NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(appState.isPremium)
        let callCountBeforeStop = provider.checkCallCount

        bridge.stop()
        await Task.yield()

        provider.isPremium = false
        NotificationCenter.default.post(name: .subscriptionStatusDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(provider.checkCallCount == callCountBeforeStop)
        #expect(appState.isPremium)
    }
}
