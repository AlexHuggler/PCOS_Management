import SwiftUI

/// Why the paywall opened. Drives the contextual headline and the analytics `source`.
enum PremiumPaywallReason: String {
    case general
    case mealScan
    case meal
    case glucose
    case supplements
    case photo
    case insights
    case report
    case settings

    static func forLogger(_ shortcut: LoggerShortcut) -> PremiumPaywallReason {
        switch shortcut {
        case .meal: .meal
        case .bloodSugar: .glucose
        case .supplements: .supplements
        case .photo: .photo
        case .period, .ovulation, .symptoms: .general
        }
    }
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

    /// The sandbox Premium override is compiled in only for internal QA builds that set the
    /// `PREMIUM_QA_OVERRIDE` Swift compilation condition. App Store archives never include it,
    /// so App Review and TestFlight testers see the real paywall and sandbox purchases.
    static var compiledWithPremiumQAOverride: Bool {
#if PREMIUM_QA_OVERRIDE
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
    /// Analytics `source` for the current paywall (the real trigger, e.g. `today_premium_card`).
    private(set) var premiumPaywallSource = PremiumPaywallReason.general.rawValue
    var pendingNotificationRoute: AppNotificationRoute?
    private(set) var pendingLoggerShortcut: LoggerShortcut?
    /// The tab whose sheet should open `pendingLoggerShortcut` (Today opens loggers in place).
    private(set) var pendingLoggerHost: AppTab = .track
    private var deferredLoggerShortcut: LoggerShortcut?
    private var deferredLoggerHost: AppTab = .track

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
        isDebugBuild: Bool = AppState.compiledInDebugBuild,
        premiumQAOverrideEnabled: Bool = AppState.compiledWithPremiumQAOverride
    ) {
        self.defaults = defaults
        uiTestDemoScenarioActive = launchArguments.contains("-uiTest.demoScenario")
        testFlightOverrideActive = Self.isTestFlightOverrideActive(
            appStoreReceiptURL: appStoreReceiptURL,
            isDebugBuild: isDebugBuild,
            premiumQAOverrideEnabled: premiumQAOverrideEnabled
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

    func presentPremiumPaywall(reason: PremiumPaywallReason = .general, source: String? = nil) {
        guard showsSubscriptionUI, !allowsPremiumAccess else { return }
        premiumPaywallReason = reason
        premiumPaywallSource = source ?? reason.rawValue
        showPremiumPaywall = true
    }

    /// The only entry point for presenting a logger from Today, Track, or notifications.
    /// `host` is the tab that presents the logger: Today opens loggers in place (no tab jump);
    /// Track and notification routes use the Track tab.
    func requestLogger(_ shortcut: LoggerShortcut, host: AppTab = .track, source: String? = nil) {
        if host == .track { selectedTab = .track }
        pendingLoggerShortcut = shortcut
        pendingLoggerHost = host
        guard hasCompletedOnboarding else { return }
        if Self.requiresPremium(shortcut), !allowsPremiumAccess {
            deferredLoggerShortcut = shortcut
            deferredLoggerHost = host
            pendingLoggerShortcut = nil
            presentPremiumPaywall(
                reason: .forLogger(shortcut),
                source: source ?? "\(host.rawValue)_\(shortcut.rawValue)"
            )
        }
    }

    /// The logger the paywall will continue to after a purchase (for the success screen CTA).
    var deferredLogger: LoggerShortcut? { deferredLoggerShortcut }

    static func requiresPremium(_ shortcut: LoggerShortcut) -> Bool {
        switch shortcut {
        case .period, .ovulation, .symptoms: false
        case .bloodSugar, .supplements, .meal, .photo: true
        }
    }

    func consumePendingLogger() -> LoggerShortcut? {
        consumePendingLogger(host: .track)
    }

    func consumePendingLogger(host: AppTab) -> LoggerShortcut? {
        guard hasCompletedOnboarding, selectedTab == host, pendingLoggerHost == host,
              !showPremiumPaywall,
              let shortcut = pendingLoggerShortcut else { return nil }
        if Self.requiresPremium(shortcut), !allowsPremiumAccess {
            requestLogger(shortcut, host: host)
            return nil
        }
        pendingLoggerShortcut = nil
        if let route = pendingNotificationRoute { consumeNotificationRoute(route) }
        return shortcut
    }

    /// Called after the paywall sheet has actually dismissed, so presentations never overlap.
    /// After a purchase the started action continues on the tab it began on (A12); closing
    /// without a purchase leaves the user where they were and clears the action (B1).
    func finishPremiumPaywall() {
        showPremiumPaywall = false
        resumeOrClearDeferredLogger()
    }

    private func resumeOrClearDeferredLogger() {
        guard let shortcut = deferredLoggerShortcut else { return }
        let host = deferredLoggerHost
        deferredLoggerShortcut = nil
        if allowsPremiumAccess {
            pendingLoggerShortcut = shortcut
            pendingLoggerHost = host
            selectedTab = host
            AppAnalytics.shared.track(.purchaseResumedAction(action: shortcut.rawValue))
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
        isDebugBuild: Bool,
        premiumQAOverrideEnabled: Bool
    ) -> Bool {
        guard !isDebugBuild, premiumQAOverrideEnabled else { return false }
        return appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
