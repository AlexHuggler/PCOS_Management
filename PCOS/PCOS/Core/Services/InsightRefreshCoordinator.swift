import Foundation

enum InsightRefreshCoordinator {
    static let notificationName = Notification.Name("insights.refresh.invalidated")

    private static let needsRefreshKey = "insights.needsRefresh"

    static func invalidate(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        defaults.set(true, forKey: needsRefreshKey)
        notificationCenter.post(name: notificationName, object: nil)
    }

    static func needsRefresh(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: needsRefreshKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.set(false, forKey: needsRefreshKey)
    }
}
