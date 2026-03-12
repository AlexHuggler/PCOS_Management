import Foundation
import Observation

@MainActor
protocol PremiumStatusProviding: AnyObject {
    var isPremium: Bool { get }
    func checkSubscriptionStatus() async
}

@MainActor
@Observable
final class PremiumStateBridge {
    private let statusProvider: any PremiumStatusProviding
    private var observerTask: Task<Void, Never>?

    init(statusProvider: any PremiumStatusProviding = SubscriptionManager.shared) {
        self.statusProvider = statusProvider
    }

    @MainActor deinit {
        stop()
    }

    func start(appState: AppState) {
        guard observerTask == nil else { return }

        observerTask = Task { [weak self] in
            await self?.sync(appState: appState)

            for await _ in NotificationCenter.default.notifications(named: .subscriptionStatusDidChange) {
                guard !Task.isCancelled else { return }
                await self?.sync(appState: appState)
            }
        }
    }

    func stop() {
        observerTask?.cancel()
        observerTask = nil
    }

    func sync(appState: AppState) async {
        await statusProvider.checkSubscriptionStatus()
        appState.isPremium = statusProvider.isPremium
    }
}
