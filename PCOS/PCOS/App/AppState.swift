import SwiftUI

enum PremiumPaywallReason: String {
    case general
    case mealScan
}

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case calendar
    case track
    case insights
    case settings

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .today:
            L10n.string("Today", defaultValue: "Today", language: language)
        case .calendar:
            L10n.string("Calendar", defaultValue: "Calendar", language: language)
        case .track:
            L10n.string("Track", defaultValue: "Track", language: language)
        case .insights:
            L10n.string("Insights", defaultValue: "Insights", language: language)
        case .settings:
            L10n.string("Settings", defaultValue: "Settings", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .calendar: "calendar"
        case .track: "plus.circle.fill"
        case .insights: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape"
        }
    }
}

@Observable
@MainActor
final class AppState {
    private static var compiledInDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private let defaults: UserDefaults
    private let uiTestDemoScenarioActive: Bool
    private let testFlightOverrideActive: Bool

    var selectedTab: AppTab = .today
    var isPremium: Bool = false
    var showPremiumPaywall = false
    var premiumPaywallReason: PremiumPaywallReason = .general
    var pendingNotificationRoute: AppNotificationRoute?
    private(set) var pendingLoggerShortcut: LoggerShortcut?
    private var deferredLoggerShortcut: LoggerShortcut?
    let launchAppLanguage: AppLanguage
    var selectedAppLanguage: AppLanguage {
        didSet {
            selectedAppLanguage.persist(defaults: defaults)
            selectedAppLanguage.applyLaunchOverride(defaults: defaults)
        }
    }

    var showScientificDetail: Bool {
        didSet { defaults.set(showScientificDetail, forKey: "display.showScientificDetail") }
    }

    var lifecycleMode: LifecycleMode {
        didSet { defaults.set(lifecycleMode.rawValue, forKey: "lifecycle.mode") }
    }

    let onboardingProfile = OnboardingProfile()

    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: "onboarding.hasCompletedOnboarding")
        }
    }

    init(
        defaults: UserDefaults = .standard,
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        appStoreReceiptURL: URL? = Bundle.main.appStoreReceiptURL,
        isDebugBuild: Bool = AppState.compiledInDebugBuild
    ) {
        self.defaults = defaults
        uiTestDemoScenarioActive = launchArguments.contains("-uiTest.demoScenario")
        testFlightOverrideActive = Self.isTestFlightOverrideActive(
            appStoreReceiptURL: appStoreReceiptURL,
            isDebugBuild: isDebugBuild
        )
        let storedAppLanguage = AppLanguage.stored(defaults: defaults)
        launchAppLanguage = AppLanguage.launchSnapshot(
            defaults: defaults,
            arguments: launchArguments
        )
        selectedAppLanguage = storedAppLanguage
        hasCompletedOnboarding = defaults.bool(forKey: "onboarding.hasCompletedOnboarding")
        showScientificDetail = defaults.bool(forKey: "display.showScientificDetail")
        lifecycleMode = LifecycleMode(rawValue: defaults.string(forKey: "lifecycle.mode") ?? "") ?? .cycling

        if !defaults.bool(forKey: "insights.narrativeUpgradeApplied") {
            defaults.set(true, forKey: "insights.narrativeUpgradeApplied")
            InsightRefreshCoordinator.invalidate(defaults: defaults)
        }
    }

    var renderLocale: Locale {
        L10n.locale(for: selectedAppLanguage)
    }

    var languageRenderKey: String {
        "\(selectedAppLanguage.rawValue)-\(L10n.resolvedLanguageIdentifier(for: selectedAppLanguage))"
    }

    var allowsPremiumAccess: Bool {
        isPremium || uiTestDemoScenarioActive || testFlightOverrideActive
    }

    var showsSubscriptionUI: Bool {
        !testFlightOverrideActive
    }

    func selectTab(_ requestedTab: AppTab) {
        selectedTab = requestedTab
    }

    func presentPremiumPaywall(reason: PremiumPaywallReason = .general) {
        guard showsSubscriptionUI, !allowsPremiumAccess else { return }
        premiumPaywallReason = reason
        showPremiumPaywall = true
    }

    /// The only entry point for presenting a logger from Today, Track, or notifications.
    func requestLogger(_ shortcut: LoggerShortcut) {
        selectedTab = .track
        pendingLoggerShortcut = shortcut
        guard hasCompletedOnboarding else { return }
        if Self.requiresPremium(shortcut), !allowsPremiumAccess {
            deferredLoggerShortcut = shortcut
            pendingLoggerShortcut = nil
            presentPremiumPaywall()
        }
    }

    static func requiresPremium(_ shortcut: LoggerShortcut) -> Bool {
        switch shortcut {
        case .period, .ovulation, .symptoms: false
        case .bloodSugar, .supplements, .meal, .photo: true
        }
    }

    func consumePendingLogger() -> LoggerShortcut? {
        guard hasCompletedOnboarding, selectedTab == .track, !showPremiumPaywall,
              let shortcut = pendingLoggerShortcut else { return nil }
        if Self.requiresPremium(shortcut), !allowsPremiumAccess {
            requestLogger(shortcut)
            return nil
        }
        pendingLoggerShortcut = nil
        if let route = pendingNotificationRoute { consumeNotificationRoute(route) }
        return shortcut
    }

    /// Called after the paywall sheet has actually dismissed, so presentations never overlap.
    func finishPremiumPaywall() {
        showPremiumPaywall = false
        guard let shortcut = deferredLoggerShortcut else { return }
        deferredLoggerShortcut = nil
        if allowsPremiumAccess {
            pendingLoggerShortcut = shortcut
            selectedTab = .track
        } else {
            pendingLoggerShortcut = nil
            if let route = pendingNotificationRoute { consumeNotificationRoute(route) }
        }
    }

    func handleNotificationRoute(_ route: AppNotificationRoute) {
        route.persistPending(defaults: defaults)
        pendingNotificationRoute = route
        requestLogger(route.loggerShortcut)
    }

    func restorePendingNotificationRoute() {
        guard let route = AppNotificationRoute.pending(defaults: defaults) else { return }
        handleNotificationRoute(route)
    }

    func consumeNotificationRoute(_ route: AppNotificationRoute) {
        guard pendingNotificationRoute == route else { return }
        pendingNotificationRoute = nil
        AppNotificationRoute.clearPending(defaults: defaults)
    }

    private static func isTestFlightOverrideActive(
        appStoreReceiptURL: URL?,
        isDebugBuild: Bool
    ) -> Bool {
        guard !isDebugBuild else { return false }
        return appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
