import SwiftUI
import os

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var appLockManager = AppLockManager()
    @State private var premiumStateBridge = PremiumStateBridge()
    @State private var reportAccessPolicy = ReportAccessPolicy()
    @State private var appearancePreferences = AppearancePreferences.shared
    @State private var notificationManager = NotificationManager()

    private var premiumTabSelection: Binding<AppTab> {
        Binding(
            get: { appState.selectedTab },
            set: { requestedTab in
                appState.selectTab(requestedTab)
            }
        )
    }

    private var paywallPresentation: Binding<Bool> {
        Binding(
            get: { appState.showPremiumPaywall },
            set: { appState.showPremiumPaywall = $0 }
        )
    }

    var body: some View {
        ZStack {
            Group {
                if appState.hasCompletedOnboarding {
                    mainTabs
                } else {
                    OnboardingContainerView {
                        appState.hasCompletedOnboarding = true
                    }
                }
            }
            .environment(appState)
            .environment(appLockManager)
            .environment(reportAccessPolicy)
            .environment(appearancePreferences)
            .appFont(.subheadline)
            .disabled(appLockManager.shouldMaskContent(for: scenePhase))

            if appLockManager.shouldMaskContent(for: scenePhase) {
                AppLockShieldView()
                    .environment(appLockManager)
            }
        }
        .sheet(isPresented: paywallPresentation, onDismiss: appState.finishPremiumPaywall) {
            PaywallView()
                .environment(appState)
        }
        .task {
            premiumStateBridge.start(appState: appState)
            // Funnel events join to revenue on the anonymous RevenueCat app user ID (no health data).
            AppAnalytics.shared.distinctID = SubscriptionManager.shared.revenueCatAppUserID
            appState.restorePendingNotificationRoute()
            await refreshDailyReminders()
        }
        .task(id: appState.languageRenderKey) {
            do {
                _ = try InsightLocalizationRefreshService(modelContext: modelContext)
                    .refreshIfNeeded(appLanguage: appState.selectedAppLanguage)
            } catch {
                Logger.database.error(
                    "ContentView: Failed to refresh localized insights: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        .onDisappear {
            premiumStateBridge.stop()
        }
        .onAppear {
            AppChromeTypography.apply()
            appLockManager.handleScenePhaseChange(scenePhase)
        }
        .onChange(of: appearancePreferences.renderKey) { _, _ in
            AppChromeTypography.apply()
        }
        .onChange(of: scenePhase) { _, newPhase in
            appLockManager.handleScenePhaseChange(newPhase)
            if newPhase == .active {
                appState.restorePendingNotificationRoute()
                Task {
                    await refreshDailyReminders()
                    guard !CycleBalanceApp.isRunningTests else { return }
                    await HealthKitManager.shared.foregroundSync(modelContainer: modelContext.container)
                }
            }
        }
        .onChange(of: appState.hasCompletedOnboarding) { _, completed in
            if completed { appState.restorePendingNotificationRoute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkInReminderRefreshRequested)) { _ in
            Task { await refreshDailyReminders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: InsightRefreshCoordinator.notificationName)) { _ in
            Task { await refreshDailyReminders() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appNotificationRouteReceived)) { notification in
            guard let route = notification.object as? AppNotificationRoute else { return }
            appState.handleNotificationRoute(route)
        }
        .environment(\.locale, appState.renderLocale)
    }

    private func refreshDailyReminders() async {
        guard !CycleBalanceApp.isRunningTests else { return }
        await notificationManager.refreshDailyCheckInReminders(modelContext: modelContext)
    }

    private var mainTabs: some View { nativeTabContent }

    private var nativeTabContent: some View {
        TabView(selection: premiumTabSelection) {
            TodayView()
                .tabItem {
                    tabLabel(for: .today)
                }
                .tag(AppTab.today)

            CalendarMonthView()
                .tabItem {
                    tabLabel(for: .calendar)
                }
                .tag(AppTab.calendar)

            TrackingHubView()
                .tabItem {
                    tabLabel(for: .track)
                }
                .tag(AppTab.track)

            InsightsView()
                .tabItem {
                    tabLabel(for: .insights)
                }
                .tag(AppTab.insights)

            SettingsView()
                .tabItem {
                    tabLabel(for: .settings)
                }
                .tag(AppTab.settings)
        }
        .tint(AppTheme.accentColor)
    }

    private func tabLabel(for tab: AppTab) -> some View {
        let color = tab == appState.selectedTab
            ? AppTheme.accentColor
            : AppTheme.primaryText.opacity(AppTheme.isBotanicalJournal ? 0.58 : 0.7)

        return Label {
            Text(tab.title(for: appState.selectedAppLanguage))
        } icon: {
            Image(systemName: tab.systemImage)
                .symbolRenderingMode(.monochrome)
        }
        .foregroundStyle(color)
    }
}

private struct AppLockShieldView: View {
    @Environment(AppLockManager.self) private var appLockManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Rectangle()
                .fill(AppTheme.warmNeutral.opacity(0.98))
                .ignoresSafeArea()

            VStack(spacing: AppTheme.spacing16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(AppTheme.coralAccent)

                Text(
                    L10n.string("CycleBalance is locked", defaultValue: "CycleBalance is locked")
                )
                .appFont(.title3, weight: .semibold)

                Text(
                    L10n.string(
                        "Use Face ID, Touch ID, or your device passcode to continue.",
                        defaultValue: "Use Face ID, Touch ID, or your device passcode to continue."
                    )
                )
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if let errorMessage = appLockManager.lastAuthErrorMessage, scenePhase == .active {
                    Text(errorMessage)
                        .appFont(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

                if scenePhase == .active {
                    Button {
                        appLockManager.requestUnlock()
                    } label: {
                        if appLockManager.isAuthenticating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.string("Unlock App", defaultValue: "Unlock App"))
                                .appFont(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, AppTheme.spacing24)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(Capsule().fill(AppTheme.coralAccent))
                    .buttonStyle(.plain)
                    .disabled(appLockManager.isAuthenticating)
                }
            }
            .padding(AppTheme.spacing24)
        }
    }
}

/// The native tab remains mounted while one destination sheet owns each logger's draft.
struct TrackingHubView: View {
    @Environment(AppState.self) private var appState
    @State private var preferences = TrackingPreferences.shared
    @State private var activeLogger: LoggerShortcut?
    @State private var recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut

    private var available: [LoggerShortcut] {
        LoggerShortcut.allCases.filter { shortcut in
            if appState.lifecycleMode == .pregnant && [.period, .ovulation].contains(shortcut) { return false }
            if shortcut == .ovulation && !preferences.showFertility { return false }
            return true
        }
    }

    private var favorites: [LoggerShortcut] {
        preferences.favoriteActions.filter { available.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                        Text(L10n.string("What would you like to record?", defaultValue: "What would you like to record?"))
                            .font(.title2.weight(.semibold))
                        Text(L10n.string("Start with what matters to you today.", defaultValue: "Start with what matters to you today."))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, AppTheme.spacing8)
                }
                if !favorites.isEmpty {
                    Section(L10n.string("Your favorites", defaultValue: "Your favorites")) {
                        ForEach(favorites) { shortcut in loggerRow(shortcut, favorite: true) }
                    }
                }
                if let recentShortcut, available.contains(recentShortcut) {
                    Section(L10n.string("Log again", defaultValue: "Log again")) {
                        loggerRow(recentShortcut)
                    }
                }
                Section(L10n.string("All tracking", defaultValue: "All tracking")) {
                    ForEach(available) { shortcut in loggerRow(shortcut) }
                }
                Section {
                    Text(L10n.string("Change favorites and optional tracking in Settings → Personalization.", defaultValue: "Change favorites and optional tracking in Settings → Personalization."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(AppTheme.accentColor)
            .navigationTitle(L10n.string("Track", defaultValue: "Track"))
            .toolbarColorScheme(AppTheme.preferredColorScheme, for: .navigationBar)
            .accessibilityIdentifier("screen.tracking")
            .sheet(item: $activeLogger, onDismiss: consumePendingLogger) { shortcut in
                loggerDestination(shortcut)
            }
            .onAppear {
                recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut
                consumePendingLogger()
            }
            .onChange(of: appState.pendingLoggerShortcut) { _, _ in consumePendingLogger() }
            .onChange(of: appState.selectedTab) { _, _ in consumePendingLogger() }
            .onChange(of: appState.hasCompletedOnboarding) { _, _ in consumePendingLogger() }
        }
    }

    private func loggerRow(_ shortcut: LoggerShortcut, favorite: Bool = false) -> some View {
        Button { appState.requestLogger(shortcut) } label: {
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: shortcut.systemImage)
                    .foregroundStyle(AppTheme.accentColor)
                    .frame(width: 28)
                Text(shortcut == .symptoms ? L10n.string("Daily check-in", defaultValue: "Daily check-in") : shortcut.title)
                    .foregroundStyle(.primary)
                Spacer()
                if AppState.requiresPremium(shortcut) && !appState.allowsPremiumAccess {
                    Label(L10n.string("Premium", defaultValue: "Premium"), systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, AppTheme.spacing8)
        }
        .accessibilityIdentifier("tracking.\(favorite ? "favorite" : "card").\(shortcut == .bloodSugar ? "blood_sugar" : shortcut.rawValue)")
    }

    @ViewBuilder
    private func loggerDestination(_ shortcut: LoggerShortcut) -> some View {
        switch shortcut {
        case .period: CycleLogView()
        case .ovulation: OvulationLogView()
        case .symptoms: SymptomLogView()
        case .bloodSugar: BloodSugarLogView()
        case .supplements: SupplementLogView()
        case .meal: MealLogView(entryPoint: .trackingHub)
        case .photo: PhotoGalleryView()
        }
    }

    private func consumePendingLogger() {
        guard activeLogger == nil, let shortcut = appState.consumePendingLogger() else { return }
        UserEntryDefaultsStore.shared.lastLoggerShortcut = shortcut
        recentShortcut = shortcut
        activeLogger = shortcut
    }
}
