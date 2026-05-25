import Testing
import Foundation
import SwiftUI
@testable import PCOS

@Suite("App Lock Manager", .serialized)
@MainActor
struct AppLockManagerTests {
    private final class AuthCallCounter: @unchecked Sendable {
        var count = 0
    }

    private enum MockAuthError: LocalizedError {
        case denied

        var errorDescription: String? {
            "Authentication denied"
        }
    }

    @Test("Successful authentication unlocks the app")
    func successfulAuthenticationUnlocksApp() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in }
        )
        manager.setEnabled(true)
        manager.isLocked = true

        await manager.authenticateIfNeeded()

        #expect(!manager.isLocked)
        #expect(manager.lastAuthErrorMessage == nil)
    }

    @Test("Failed authentication keeps the app locked and surfaces an error")
    func failedAuthenticationKeepsAppLocked() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in throw MockAuthError.denied }
        )
        manager.setEnabled(true)
        manager.isLocked = true

        await manager.authenticateIfNeeded()

        #expect(manager.isLocked)
        #expect(manager.lastAuthErrorMessage == "Authentication denied")
    }

    @Test("Relock delay waits until its threshold before requesting authentication")
    func relockDelayWaitsUntilThreshold() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = AuthCallCounter()
        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            }
        )
        manager.setEnabled(true)
        manager.setRelockDelay(.oneMinute)

        let origin = Date(timeIntervalSince1970: 1_715_000_000)
        manager.handleScenePhaseChange(.inactive, now: origin)
        manager.handleScenePhaseChange(.active, now: origin.addingTimeInterval(120))
        await drainQueuedTasks()
        #expect(counter.count == 0)
        #expect(!manager.isLocked)

        let backgroundDate = origin.addingTimeInterval(300)
        manager.handleScenePhaseChange(.background, now: backgroundDate)
        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(30))
        await drainQueuedTasks()
        #expect(counter.count == 0)
        #expect(!manager.isLocked)

        let secondBackgroundDate = origin.addingTimeInterval(600)
        manager.handleScenePhaseChange(.background, now: secondBackgroundDate)
        manager.handleScenePhaseChange(.active, now: secondBackgroundDate.addingTimeInterval(61))
        await drainQueuedTasks()
        #expect(counter.count == 1)
        #expect(!manager.isLocked)
    }

    @Test("Inactive scene transitions do not schedule authentication")
    func inactiveSceneTransitionsDoNotScheduleAuthentication() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = AuthCallCounter()
        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            }
        )
        manager.setEnabled(true)
        manager.setRelockDelay(.immediately)

        let now = Date(timeIntervalSince1970: 1_715_100_000)
        manager.handleScenePhaseChange(.inactive, now: now)
        await drainQueuedTasks()
        #expect(counter.count == 0)
        #expect(!manager.isLocked)

        manager.handleScenePhaseChange(.active, now: now.addingTimeInterval(1))
        await drainQueuedTasks()
        #expect(counter.count == 0)
        #expect(!manager.isLocked)
    }

    @Test("Background to active with immediate relock authenticates exactly once")
    func backgroundToActiveAuthenticatesExactlyOnce() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = AuthCallCounter()
        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            }
        )
        manager.setEnabled(true)
        manager.setRelockDelay(.immediately)

        let backgroundDate = Date(timeIntervalSince1970: 1_715_200_000)
        manager.handleScenePhaseChange(.background, now: backgroundDate)
        #expect(manager.isLocked)

        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(1))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(!manager.isLocked)
    }

    @Test("Cold relaunch with immediate relock restores lock and authenticates once")
    func coldRelaunchImmediateRelockAuthenticatesOnce() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backgroundDate = Date(timeIntervalSince1970: 1_715_250_000)
        let originalManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in },
            nowProvider: { backgroundDate }
        )
        originalManager.setEnabled(true)
        originalManager.setRelockDelay(.immediately)
        originalManager.handleScenePhaseChange(.background, now: backgroundDate)

        let counter = AuthCallCounter()
        let relaunchedManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            },
            nowProvider: { backgroundDate.addingTimeInterval(1) }
        )

        #expect(relaunchedManager.isLocked)

        relaunchedManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(1))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(!relaunchedManager.isLocked)
    }

    @Test("Cold relaunch within one-minute delay stays unlocked")
    func coldRelaunchWithinOneMinuteDelayStaysUnlocked() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backgroundDate = Date(timeIntervalSince1970: 1_715_260_000)
        let originalManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in },
            nowProvider: { backgroundDate }
        )
        originalManager.setEnabled(true)
        originalManager.setRelockDelay(.oneMinute)
        originalManager.handleScenePhaseChange(.background, now: backgroundDate)

        let counter = AuthCallCounter()
        let relaunchedManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            },
            nowProvider: { backgroundDate.addingTimeInterval(30) }
        )

        #expect(!relaunchedManager.isLocked)

        relaunchedManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(30))
        await drainQueuedTasks()

        #expect(counter.count == 0)
        #expect(!relaunchedManager.isLocked)
    }

    @Test("Cold relaunch after one-minute delay authenticates once")
    func coldRelaunchAfterOneMinuteDelayAuthenticatesOnce() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backgroundDate = Date(timeIntervalSince1970: 1_715_270_000)
        let originalManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in },
            nowProvider: { backgroundDate }
        )
        originalManager.setEnabled(true)
        originalManager.setRelockDelay(.oneMinute)
        originalManager.handleScenePhaseChange(.background, now: backgroundDate)

        let counter = AuthCallCounter()
        let relaunchedManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            },
            nowProvider: { backgroundDate.addingTimeInterval(61) }
        )

        #expect(relaunchedManager.isLocked)

        relaunchedManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(61))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(!relaunchedManager.isLocked)
    }

    @Test("Cold relaunch after five-minute delay authenticates once")
    func coldRelaunchAfterFiveMinuteDelayAuthenticatesOnce() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backgroundDate = Date(timeIntervalSince1970: 1_715_280_000)
        let originalManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in },
            nowProvider: { backgroundDate }
        )
        originalManager.setEnabled(true)
        originalManager.setRelockDelay(.fiveMinutes)
        originalManager.handleScenePhaseChange(.background, now: backgroundDate)

        let counter = AuthCallCounter()
        let relaunchedManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            },
            nowProvider: { backgroundDate.addingTimeInterval(301) }
        )

        #expect(relaunchedManager.isLocked)

        relaunchedManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(301))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(!relaunchedManager.isLocked)
    }

    @Test("Auth sheet inactive-active bounce does not re-trigger authentication")
    func authSheetInactiveActiveBounceDoesNotRetriggerAuthentication() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = AuthCallCounter()
        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
                try? await Task.sleep(for: .milliseconds(150))
            }
        )
        manager.setEnabled(true)
        manager.setRelockDelay(.immediately)

        let backgroundDate = Date(timeIntervalSince1970: 1_715_300_000)
        manager.handleScenePhaseChange(.background, now: backgroundDate)
        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(1))
        await waitForAuthCalls(counter, expectedCount: 1)

        manager.handleScenePhaseChange(.inactive, now: backgroundDate.addingTimeInterval(2))
        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(3))
        await drainQueuedTasks()
        #expect(counter.count == 1)

        try? await Task.sleep(for: .milliseconds(200))
        await drainQueuedTasks()
        #expect(counter.count == 1)
        #expect(!manager.isLocked)
    }

    @Test("Failed automatic authentication only retries on manual unlock")
    func failedAutomaticAuthenticationOnlyRetriesOnManualUnlock() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let counter = AuthCallCounter()
        let manager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
                throw MockAuthError.denied
            }
        )
        manager.setEnabled(true)
        manager.setRelockDelay(.immediately)

        let backgroundDate = Date(timeIntervalSince1970: 1_715_400_000)
        manager.handleScenePhaseChange(.background, now: backgroundDate)
        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(1))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(manager.isLocked)
        #expect(manager.lastAuthErrorMessage == "Authentication denied")

        manager.handleScenePhaseChange(.inactive, now: backgroundDate.addingTimeInterval(2))
        manager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(3))
        await drainQueuedTasks()
        #expect(counter.count == 1)

        manager.requestUnlock()
        await drainQueuedTasks()
        #expect(counter.count == 2)
        #expect(manager.isLocked)
    }

    @Test("Failed relaunch authentication restores locked shield without auto retry")
    func failedRelaunchAuthenticationRestoresLockedShieldWithoutAutoRetry() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backgroundDate = Date(timeIntervalSince1970: 1_715_410_000)
        let originalManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in },
            nowProvider: { backgroundDate }
        )
        originalManager.setEnabled(true)
        originalManager.setRelockDelay(.immediately)
        originalManager.handleScenePhaseChange(.background, now: backgroundDate)

        let counter = AuthCallCounter()
        let failingManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
                throw MockAuthError.denied
            },
            nowProvider: { backgroundDate.addingTimeInterval(1) }
        )
        failingManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(1))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(failingManager.isLocked)

        let restoredManager = AppLockManager(
            defaults: defaults,
            authenticate: { _ in
                counter.count += 1
            },
            nowProvider: { backgroundDate.addingTimeInterval(2) }
        )
        #expect(restoredManager.isLocked)

        restoredManager.handleScenePhaseChange(.active, now: backgroundDate.addingTimeInterval(2))
        await drainQueuedTasks()

        #expect(counter.count == 1)
        #expect(restoredManager.isLocked)
    }
}

private extension AppLockManagerTests {
    private func drainQueuedTasks(iterations: Int = 4) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }

    private func waitForAuthCalls(
        _ counter: AuthCallCounter,
        expectedCount: Int,
        timeout: Duration = .seconds(1)
    ) async {
        let deadline = ContinuousClock().now + timeout
        while counter.count < expectedCount && ContinuousClock().now < deadline {
            await drainQueuedTasks()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "AppLockManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
