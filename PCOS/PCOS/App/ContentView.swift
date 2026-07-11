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
        .sheet(isPresented: paywallPresentation) {
            PaywallView()
                .environment(appState)
        }
        .id(contentRenderIdentity)
        .task {
            premiumStateBridge.start(appState: appState)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .appNotificationRouteReceived)) { notification in
            guard let route = notification.object as? AppNotificationRoute else { return }
            appState.handleNotificationRoute(route)
        }
        .environment(\.locale, appState.renderLocale)
    }

    private var contentRenderIdentity: String {
        guard appState.hasCompletedOnboarding else {
            return "onboarding-active"
        }

        return "\(appState.languageRenderKey)-\(appearancePreferences.renderKey.uuidString)"
    }

    @ViewBuilder
    private var mainTabs: some View {
        if AppTheme.usesCustomTabBar {
            botanicalTabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BotanicalTabBar(
                        selection: premiumTabSelection,
                        language: appState.selectedAppLanguage
                    )
                    .padding(.horizontal, AppTheme.spacing16)
                    .padding(.top, AppTheme.spacing8)
                    .padding(.bottom, AppTheme.spacing8)
                    .background(
                        LinearGradient(
                            colors: bottomBarBackdropColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .ignoresSafeArea(edges: .bottom)
                    )
                }
        } else {
            nativeTabContent
        }
    }

    private var bottomBarBackdropColors: [Color] {
        if AppTheme.isBotanicalJournal {
            [
                AppTheme.botanicalCreamRGB.color.opacity(0.86),
                AppTheme.botanicalCreamRGB.color.opacity(0.99),
                AppTheme.botanicalCreamRGB.color,
            ]
        } else if AppTheme.usesImmersiveHomeShell {
            [
                AppTheme.premiumEditorBackground.opacity(0),
                AppTheme.premiumEditorBackground.opacity(0.84),
                AppTheme.premiumEditorBackground,
            ]
        } else {
            [
                AppTheme.warmNeutral.opacity(0),
                AppTheme.warmNeutral.opacity(0.92),
                AppTheme.warmNeutral,
            ]
        }
    }

    @ViewBuilder
    private var botanicalTabContent: some View {
        switch appState.selectedTab {
        case .today:
            TodayView()
        case .calendar:
            CalendarMonthView()
        case .track:
            TrackingHubView()
        case .insights:
            InsightsView()
        case .settings:
            SettingsView()
        }
    }

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

private struct BotanicalTabBar: View {
    @Binding var selection: AppTab
    let language: AppLanguage

    var body: some View {
        HStack(spacing: AppTheme.spacing4) {
            ForEach(AppTab.allCases) { tab in
                BotanicalTabButton(
                    tab: tab,
                    isSelected: selection == tab,
                    language: language
                ) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.spacing8)
        .padding(.vertical, AppTheme.botanicalTabItemVerticalPadding)
        .background(tabBarBackground)
        .overlay(tabBarBorder)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(tabBarAccessibilityIdentifier)
    }

    private var tabBarBackground: some View {
        Capsule()
            .fill(tabBarFill)
            .shadow(color: tabBarShadowColor, radius: AppTheme.usesImmersiveHomeShell ? 22 : 18, y: 8)
    }

    private var tabBarFill: some ShapeStyle {
        if AppTheme.isBotanicalJournal {
            LinearGradient(
                colors: [
                    AppTheme.botanicalCreamRGB.color,
                    AppTheme.botanicalCreamAltRGB.color.opacity(0.98),
                    AppTheme.botanicalCreamRGB.color,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if AppTheme.usesImmersiveHomeShell {
            LinearGradient(
                colors: [
                    AppTheme.premiumEditorRaisedSurface.opacity(0.98),
                    AppTheme.premiumEditorSurface.opacity(0.96),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    AppTheme.cardBackground.opacity(0.98),
                    AppTheme.sage.opacity(0.08),
                    AppTheme.cardBackground.opacity(0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var tabBarBorder: some View {
        Capsule()
            .strokeBorder(
                AppTheme.usesImmersiveHomeShell
                    ? AppTheme.premiumEditorBorderGradient
                    : AppTheme.themeBorderGradient,
                lineWidth: AppTheme.usesImmersiveHomeShell ? 1.1 : 0.9
            )
    }

    private var tabBarShadowColor: Color {
        if AppTheme.isBotanicalJournal {
            AppTheme.botanicalRoseRGB.color.opacity(0.18)
        } else if AppTheme.usesImmersiveHomeShell {
            AppTheme.premiumEditorAccentColor.opacity(0.12)
        } else {
            AppTheme.accentColor.opacity(AppTheme.isEditorialTheme ? 0.14 : 0.08)
        }
    }

    private var tabBarAccessibilityIdentifier: String {
        if AppTheme.isLunarCalm {
            "lunar.tab_bar"
        } else if AppTheme.isBotanicalJournal {
            "botanical.tab_bar"
        } else {
            "themed.tab_bar"
        }
    }
}

private struct BotanicalTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let language: AppLanguage
    let action: () -> Void

    private var foregroundColor: Color {
        if isSelected {
            AppTheme.usesImmersiveHomeShell ? AppTheme.premiumEditorAccentColor : AppTheme.primaryText
        } else if AppTheme.usesImmersiveHomeShell {
            AppTheme.secondaryText.opacity(0.72)
        } else if AppTheme.isBotanicalJournal {
            AppTheme.botanicalSageRGB.color.opacity(0.82)
        } else {
            AppTheme.secondaryText.opacity(0.86)
        }
    }

    private var fillColor: Color {
        if AppTheme.usesImmersiveHomeShell {
            isSelected ? AppTheme.premiumEditorRaisedSurface.opacity(0.96) : .clear
        } else if AppTheme.isBotanicalJournal {
            isSelected ? AppTheme.botanicalCreamRGB.color.opacity(0.96) : .clear
        } else {
            isSelected ? AppTheme.accentColor.opacity(0.11) : .clear
        }
    }

    private var borderColor: Color {
        if AppTheme.usesImmersiveHomeShell {
            isSelected ? AppTheme.premiumEditorAccentColor.opacity(0.62) : .clear
        } else if AppTheme.isBotanicalJournal {
            isSelected ? AppTheme.botanicalRoseSoftRGB.color.opacity(0.45) : .clear
        } else {
            isSelected ? AppTheme.accentColor.opacity(0.42) : .clear
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppTheme.botanicalTabLabelSpacing) {
                Image(systemName: tab.systemImage)
                    .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                    .symbolRenderingMode(.monochrome)
                    .frame(
                        width: AppTheme.botanicalTabIconFrame.width,
                        height: AppTheme.botanicalTabIconFrame.height
                    )

                Text(tab.title(for: language))
                    .appFont(.caption2, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .allowsTightening(true)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.botanicalTabMinHeight)
            .padding(.vertical, AppTheme.botanicalTabItemVerticalPadding)
            .background(Capsule().fill(fillColor))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title(for: language))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var accessibilityIdentifier: String {
        switch tab {
        case .today:
            "tab.today"
        case .calendar:
            "tab.calendar"
        case .track:
            "tab.track"
        case .insights:
            "tab.insights"
        case .settings:
            "tab.settings"
        }
    }
}

/// Hub view for the Track tab — direct sheet presentation for quick logging
struct TrackingHubView: View {
    @Environment(AppState.self) private var appState
    @State private var showingLogPeriod = false
    @State private var showingLogOvulation = false
    @State private var showingLogSymptoms = false
    @State private var showingLogBloodSugar = false
    @State private var showingLogSupplements = false
    @State private var showingLogMeal = false
    @State private var showingMealScan = false
    @State private var showingPhotoJournal = false
    @State private var recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut

    var body: some View {
        NavigationStack {
            ZStack {
                if AppTheme.usesImmersiveHomeShell {
                    AppTheme.premiumEditorBackground
                        .ignoresSafeArea()
                } else {
                    BotanicalScreenBackground()
                }

                ScrollView {
                    Group {
                        if AppTheme.usesImmersiveHomeShell {
                            lunarTrackingContent
                        } else {
                            standardTrackingContent
                        }
                    }
                    .padding()
                    .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("screen.tracking")
            }
            .navigationTitle(AppTheme.usesImmersiveHomeShell ? "" : L10n.string("Track", defaultValue: "Track"))
            .trackingHubPresentation(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .trackingHubPresentation(isPresented: $showingLogOvulation) {
                OvulationLogView()
            }
            .trackingHubPresentation(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
            .trackingHubPresentation(isPresented: $showingLogBloodSugar) {
                BloodSugarLogView()
            }
            .trackingHubPresentation(isPresented: $showingLogSupplements) {
                SupplementLogView()
            }
            .trackingHubPresentation(isPresented: $showingLogMeal) {
                MealLogView(entryPoint: .trackingHub)
            }
            .trackingHubPresentation(isPresented: $showingMealScan) {
                MealScanFlowView(mealType: .lunch)
            }
            .trackingHubPresentation(isPresented: $showingPhotoJournal) {
                PhotoGalleryView()
            }
            .onChange(of: showingLogMeal) { _, isPresented in
                Logger.meals.info("TrackingHubView meal log sheet state changed: \(isPresented, privacy: .public)")
            }
            .onAppear {
                recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut
                openPendingNotificationRouteIfNeeded()
            }
            .onChange(of: appState.pendingNotificationRoute) { _, _ in
                openPendingNotificationRouteIfNeeded()
            }
        }
    }

    private var standardTrackingContent: some View {
        VStack(spacing: AppTheme.spacing16) {
            BotanicalPosterHeader(
                title: L10n.string("Track your balance", defaultValue: "Track your balance"),
                subtitle: L10n.string("Log meals, symptoms, glucose, and cycle clues in one calm place.", defaultValue: "Log meals, symptoms, glucose, and cycle clues in one calm place."),
                dividerStyle: .ornamental
            )
            .padding(.top, AppTheme.spacing8)

            if let recentShortcut {
                Button {
                    open(shortcut: recentShortcut)
                } label: {
                    HStack(spacing: AppTheme.spacing12) {
                        BotanicalIllustrationBadge(
                            systemImage: "clock.arrow.circlepath",
                            color: AppTheme.lavenderAccent,
                            size: 42
                        )
                        Spacer()
                        Label(recentShortcut.title, systemImage: recentShortcut.systemImage)
                            .appFont(.subheadline, weight: .medium)
                            .foregroundStyle(AppTheme.accentColor)
                    }
                    .cardStyle()
                }
                .buttonStyle(.plain)
            }

            standardTrackingCards
        }
    }

    private var standardTrackingCards: some View {
        VStack(spacing: AppTheme.spacing16) {
            if appState.lifecycleMode != .pregnant {
                TrackingCard(
                    title: L10n.string("Log Period", defaultValue: "Log Period"),
                    subtitle: L10n.string("Record flow intensity and notes", defaultValue: "Record flow intensity and notes"),
                    systemImage: "drop.fill",
                    botanicalAssetName: "botanical-glucose-drop",
                    color: AppTheme.coralAccent,
                    accessibilityIdentifier: "tracking.card.period"
                ) {
                    open(shortcut: .period)
                }

                TrackingCard(
                    title: L10n.string("Log Ovulation Clues", defaultValue: "Log Ovulation Clues"),
                    subtitle: L10n.string("BBT, cervical mucus, and LH tests", defaultValue: "BBT, cervical mucus, and LH tests"),
                    systemImage: "scope",
                    botanicalAssetName: "botanical-sage-leaves",
                    color: AppTheme.sage,
                    accessibilityIdentifier: "tracking.card.ovulation"
                ) {
                    open(shortcut: .ovulation)
                }
            }

            TrackingCard(
                title: L10n.string("Log Symptoms", defaultValue: "Log Symptoms"),
                subtitle: L10n.string("Track how you're feeling today", defaultValue: "Track how you're feeling today"),
                systemImage: "list.bullet.clipboard",
                botanicalAssetName: "botanical-calendar-illustration",
                color: AppTheme.accentColor,
                accessibilityIdentifier: "tracking.card.symptoms"
            ) {
                open(shortcut: .symptoms)
            }

            TrackingCard(
                title: L10n.string("Log Blood Sugar", defaultValue: "Log Blood Sugar"),
                subtitle: L10n.string("Record glucose readings", defaultValue: "Record glucose readings"),
                systemImage: "drop.triangle.fill",
                botanicalAssetName: "botanical-glucose-drop",
                color: .orange,
                accessibilityIdentifier: "tracking.card.blood_sugar"
            ) {
                open(shortcut: .bloodSugar)
            }

            TrackingCard(
                title: L10n.string("Log Supplements", defaultValue: "Log Supplements"),
                subtitle: L10n.string("Track your daily supplements", defaultValue: "Track your daily supplements"),
                systemImage: "pills.fill",
                botanicalAssetName: "botanical-supplement-jar",
                color: AppTheme.accentColor,
                accessibilityIdentifier: "tracking.card.supplements"
            ) {
                open(shortcut: .supplements)
            }

            TrackingCard(
                title: L10n.string("Log Meal", defaultValue: "Log Meal"),
                subtitle: L10n.string("Record meals and glycemic impact", defaultValue: "Record meals and glycemic impact"),
                systemImage: "fork.knife",
                botanicalAssetName: "botanical-meal-bowl",
                color: AppTheme.sage,
                accessibilityIdentifier: "tracking.card.meal"
            ) {
                open(shortcut: .meal)
            }

            if MealScanFeatureFlags.current.enableMealScanV2 {
                TrackingCard(
                    title: L10n.string("AI Meal Scan", defaultValue: "AI Meal Scan"),
                    subtitle: L10n.string("Estimate foods, portions, and nutrients from a photo", defaultValue: "Estimate foods, portions, and nutrients from a photo"),
                    systemImage: "camera.viewfinder",
                    botanicalAssetName: "botanical-meal-bowl",
                    color: AppTheme.lavenderAccent,
                    accessibilityIdentifier: "tracking.card.meal_scan"
                ) {
                    openMealScan()
                }
            }

            TrackingCard(
                title: L10n.string("Photo Journal", defaultValue: "Photo Journal"),
                subtitle: L10n.string("Track hair and skin changes", defaultValue: "Track hair and skin changes"),
                systemImage: "camera.fill",
                botanicalAssetName: "botanical-rosebud-branch",
                color: AppTheme.sage,
                accessibilityIdentifier: "tracking.card.photo"
            ) {
                open(shortcut: .photo)
            }
        }
    }

    private var lunarTrackingContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing20) {
            lunarTrackingHero
            lunarShortcutRail

            if let recentShortcut {
                LunarTrackingCard(
                    title: L10n.string("Resume last log", defaultValue: "Resume last log"),
                    subtitle: recentShortcut.title,
                    systemImage: "clock.arrow.circlepath",
                    tint: AppTheme.lavenderAccent,
                    accessibilityIdentifier: "tracking.lunar.recent"
                ) {
                    open(shortcut: recentShortcut)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                Text(L10n.string("Choose your signal", defaultValue: "Choose your signal"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                    .accessibilityIdentifier("tracking.lunar.card_cluster")

                lunarTrackingCards
            }

            lunarTrackingSupportCard
        }
        .padding(.top, AppTheme.spacing8)
    }

    private var lunarTrackingHero: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            HStack(alignment: .top, spacing: AppTheme.spacing12) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Track gently today", defaultValue: "Track gently today"))
                        .appHeadingFont(.title, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(L10n.string("Small details can become useful patterns.", defaultValue: "Small details can become useful patterns."))
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                ZStack {
                    Circle()
                        .fill(AppTheme.premiumEditorAccentGradient)
                    Image(systemName: "moon.stars.fill")
                        .appFont(.title3, weight: .semibold)
                        .foregroundStyle(AppTheme.premiumEditorCTAForeground)
                }
                .frame(width: 50, height: 50)
                .shadow(color: AppTheme.premiumEditorAccentColor.opacity(0.22), radius: 16, y: 8)
                .accessibilityHidden(true)
            }

            HStack(spacing: AppTheme.spacing8) {
                LunarTrackingPill(title: L10n.string("Private", defaultValue: "Private"), systemImage: "lock.fill")
                LunarTrackingPill(title: L10n.string("Pattern-ready", defaultValue: "Pattern-ready"), systemImage: "sparkles")
                LunarTrackingPill(title: L10n.string("PCOS-aware", defaultValue: "PCOS-aware"), systemImage: "heart.text.square.fill")
            }
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.premiumEditorRaisedSurface.opacity(0.92),
                            AppTheme.premiumEditorSurface.opacity(0.84),
                            AppTheme.premiumEditorBackground.opacity(0.98),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorderGradient, lineWidth: 0.9)
                .opacity(0.78)
        )
        .accessibilityIdentifier("tracking.lunar.header")
    }

    private var lunarShortcutRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.spacing8) {
                ForEach(lunarShortcutOptions) { shortcut in
                    Button {
                        open(shortcut: shortcut)
                    } label: {
                        VStack(spacing: AppTheme.spacing8) {
                            ZStack {
                                Circle()
                                    .fill(lunarTint(for: shortcut).opacity(0.18))
                                Image(systemName: shortcut.systemImage)
                                    .appFont(.headline, weight: .semibold)
                                    .foregroundStyle(lunarTint(for: shortcut))
                            }
                            .frame(width: 44, height: 44)

                            Text(lunarShortTitle(for: shortcut))
                                .appFont(.caption, weight: .semibold)
                                .foregroundStyle(AppTheme.primaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }
                        .frame(width: 82, height: 82)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.66))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.premiumEditorBorder.opacity(0.58), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tracking.lunar.shortcut.\(shortcut.rawValue)")
                }
            }
            .padding(.vertical, AppTheme.spacing4)
        }
        .accessibilityIdentifier("tracking.lunar.quick_rail")
    }

    private var lunarTrackingCards: some View {
        VStack(spacing: AppTheme.spacing8) {
            if appState.lifecycleMode != .pregnant {
                LunarTrackingCard(
                    title: L10n.string("Log Period", defaultValue: "Log Period"),
                    subtitle: L10n.string("Flow, dates, and notes", defaultValue: "Flow, dates, and notes"),
                    systemImage: "drop.fill",
                    tint: AppTheme.premiumEditorWarningAccentColor,
                    accessibilityIdentifier: "tracking.card.period"
                ) {
                    open(shortcut: .period)
                }

                LunarTrackingCard(
                    title: L10n.string("Ovulation Clues", defaultValue: "Ovulation Clues"),
                    subtitle: L10n.string("BBT, cervical mucus, and LH tests", defaultValue: "BBT, cervical mucus, and LH tests"),
                    systemImage: "scope",
                    tint: AppTheme.premiumEditorAccentColor,
                    accessibilityIdentifier: "tracking.card.ovulation"
                ) {
                    open(shortcut: .ovulation)
                }
            }

            LunarTrackingCard(
                title: L10n.string("Log Symptoms", defaultValue: "Log Symptoms"),
                subtitle: L10n.string("Mood, pain, sleep, energy, and notes", defaultValue: "Mood, pain, sleep, energy, and notes"),
                systemImage: "cloud.moon.fill",
                tint: AppTheme.premiumEditorAccentColor,
                isProminent: true,
                accessibilityIdentifier: "tracking.card.symptoms"
            ) {
                open(shortcut: .symptoms)
            }

            LunarTrackingCard(
                title: L10n.string("Blood Sugar", defaultValue: "Blood Sugar"),
                subtitle: L10n.string("Readings around meals and symptoms", defaultValue: "Readings around meals and symptoms"),
                systemImage: "drop.triangle.fill",
                tint: AppTheme.accentColor,
                accessibilityIdentifier: "tracking.card.blood_sugar"
            ) {
                open(shortcut: .bloodSugar)
            }

            LunarTrackingCard(
                title: L10n.string("Supplements", defaultValue: "Supplements"),
                subtitle: L10n.string("Doses, timing, and consistency", defaultValue: "Doses, timing, and consistency"),
                systemImage: "pills.fill",
                tint: AppTheme.premiumEditorSecondaryAccentColor,
                accessibilityIdentifier: "tracking.card.supplements"
            ) {
                open(shortcut: .supplements)
            }

            LunarTrackingCard(
                title: L10n.string("Meal", defaultValue: "Meal"),
                subtitle: L10n.string("Food, cravings, and glycemic context", defaultValue: "Food, cravings, and glycemic context"),
                systemImage: "fork.knife",
                tint: AppTheme.lavenderAccent,
                accessibilityIdentifier: "tracking.card.meal"
            ) {
                open(shortcut: .meal)
            }

            if MealScanFeatureFlags.current.enableMealScanV2 {
                LunarTrackingCard(
                    title: L10n.string("AI Meal Scan", defaultValue: "AI Meal Scan"),
                    subtitle: L10n.string("Photo estimate for foods and portions", defaultValue: "Photo estimate for foods and portions"),
                    systemImage: "camera.viewfinder",
                    tint: AppTheme.softGoldAccent,
                    accessibilityIdentifier: "tracking.card.meal_scan"
                ) {
                    openMealScan()
                }
            }

            LunarTrackingCard(
                title: L10n.string("Photo Journal", defaultValue: "Photo Journal"),
                subtitle: L10n.string("Hair, skin, and visible changes", defaultValue: "Hair, skin, and visible changes"),
                systemImage: "camera.fill",
                tint: AppTheme.roseAccent,
                accessibilityIdentifier: "tracking.card.photo"
            ) {
                open(shortcut: .photo)
            }
        }
    }

    private var lunarTrackingSupportCard: some View {
        HStack(alignment: .center, spacing: AppTheme.spacing12) {
            Image(systemName: "moon.stars.fill")
                .appFont(.title3, weight: .semibold)
                .symbolRenderingMode(.palette)
                .foregroundStyle(AppTheme.premiumEditorAccentColor, AppTheme.softGoldAccent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppTheme.premiumEditorAccentColor.opacity(0.16)))

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Your pace counts.", defaultValue: "Your pace counts."))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("Even one log can make future insights calmer and clearer.", defaultValue: "Even one log can make future insights calmer and clearer."))
                    .appFont(.subheadline)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppTheme.spacing8)

            Image(systemName: "sparkles")
                .appFont(.caption, weight: .semibold)
                .foregroundStyle(AppTheme.softGoldAccent.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Circle().fill(AppTheme.premiumEditorSurface.opacity(0.72)))
                .accessibilityHidden(true)
        }
        .padding(AppTheme.spacing16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.premiumEditorRaisedSurface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.premiumEditorBorder.opacity(0.56), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tracking.lunar.support_card")
    }

    private var lunarShortcutOptions: [LoggerShortcut] {
        var shortcuts: [LoggerShortcut] = []
        if appState.lifecycleMode != .pregnant {
            shortcuts.append(.period)
        }
        shortcuts.append(contentsOf: [.symptoms, .meal, .bloodSugar, .supplements, .photo])
        return shortcuts
    }

    private func open(shortcut: LoggerShortcut) {
        UserEntryDefaultsStore.shared.lastLoggerShortcut = shortcut
        recentShortcut = shortcut
        switch shortcut {
        case .period:
            showingLogPeriod = true
        case .ovulation:
            showingLogOvulation = true
        case .symptoms:
            showingLogSymptoms = true
        case .bloodSugar:
            guard appState.allowsPremiumAccess else {
                appState.presentPremiumPaywall()
                return
            }
            showingLogBloodSugar = true
        case .supplements:
            guard appState.allowsPremiumAccess else {
                appState.presentPremiumPaywall()
                return
            }
            showingLogSupplements = true
        case .meal:
            Logger.meals.info("TrackingHubView requested meal log.")
            guard appState.allowsPremiumAccess else {
                Logger.meals.notice("TrackingHubView blocked meal log behind premium access.")
                appState.presentPremiumPaywall()
                return
            }
            showingLogMeal = true
            Logger.meals.info("TrackingHubView presenting meal log sheet.")
        case .photo:
            guard appState.allowsPremiumAccess else {
                appState.presentPremiumPaywall()
                return
            }
            showingPhotoJournal = true
        }
    }

    private func openMealScan() {
        guard MealScanFeatureFlags.current.enableMealScanV2 else {
            Logger.meals.info("TrackingHubView routed disabled AI meal scan request to meal log.")
            open(shortcut: .meal)
            return
        }

        Logger.meals.info("TrackingHubView requested AI meal scan.")
        showingMealScan = true
    }

    private func openPendingNotificationRouteIfNeeded() {
        guard appState.selectedTab == .track,
              appState.pendingNotificationRoute == .mealScan
        else {
            return
        }

        appState.consumeNotificationRoute(.mealScan)
        openMealScan()
    }

    private func lunarShortTitle(for shortcut: LoggerShortcut) -> String {
        switch shortcut {
        case .period:
            return L10n.string("Period", defaultValue: "Period")
        case .ovulation:
            return L10n.string("Ovulation", defaultValue: "Ovulation")
        case .symptoms:
            return L10n.string("Symptoms", defaultValue: "Symptoms")
        case .bloodSugar:
            return L10n.string("Glucose", defaultValue: "Glucose")
        case .supplements:
            return L10n.string("Supps", defaultValue: "Supps")
        case .meal:
            return L10n.string("Meal", defaultValue: "Meal")
        case .photo:
            return L10n.string("Photos", defaultValue: "Photos")
        }
    }

    private func lunarTint(for shortcut: LoggerShortcut) -> Color {
        switch shortcut {
        case .period:
            return AppTheme.premiumEditorWarningAccentColor
        case .ovulation:
            return AppTheme.premiumEditorAccentColor
        case .symptoms:
            return AppTheme.lavenderAccent
        case .bloodSugar:
            return AppTheme.accentColor
        case .supplements:
            return AppTheme.premiumEditorSecondaryAccentColor
        case .meal:
            return AppTheme.softGoldAccent
        case .photo:
            return AppTheme.roseAccent
        }
    }
}

private extension View {
    @ViewBuilder
    func trackingHubPresentation<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        if AppTheme.usesImmersivePresentation {
            fullScreenCover(isPresented: isPresented, content: destination)
        } else {
            sheet(isPresented: isPresented, content: destination)
        }
    }
}

struct TrackingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var botanicalAssetName: String? = nil
    let color: Color
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: AppTheme.spacing16) {
                BotanicalIllustrationBadge(
                    assetName: botanicalAssetName,
                    systemImage: systemImage,
                    color: color,
                    size: 56
                )

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .appHeadingFont(.headline, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(subtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .appFont(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .overlay(alignment: .bottom) {
                if AppTheme.isBotanicalJournal {
                    BotanicalOrnamentalDivider(width: 118)
                        .opacity(0.34)
                        .offset(y: AppTheme.spacing16)
                }
            }
            .cardStyle(cornerRadius: AppTheme.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: tapped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "\(title). \(subtitle)",
                comment: "Accessibility label for a tracking hub card, including title and subtitle."
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

private struct LunarTrackingPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .appFont(.caption, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, AppTheme.spacing8)
            .padding(.vertical, AppTheme.spacing4)
            .foregroundStyle(AppTheme.premiumEditorAccentColor)
            .background(Capsule().fill(AppTheme.premiumEditorAccentColor.opacity(0.12)))
            .overlay(Capsule().stroke(AppTheme.premiumEditorAccentColor.opacity(0.34), lineWidth: 0.7))
    }
}

private struct LunarTrackingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    var isProminent = false
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: AppTheme.spacing12) {
                ZStack {
                    Circle()
                        .fill(isProminent ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(tint.opacity(0.18)))
                    Image(systemName: systemImage)
                        .appFont(.title3, weight: .semibold)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isProminent ? AppTheme.premiumEditorCTAForeground : tint, AppTheme.premiumEditorSecondaryAccentColor)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .appFont(.headline, weight: .semibold)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(subtitle)
                        .appFont(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: AppTheme.spacing8)

                Image(systemName: "chevron.right")
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(isProminent ? AppTheme.premiumEditorAccentColor : AppTheme.secondaryText)
            }
            .padding(AppTheme.spacing12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.premiumEditorRaisedSurface.opacity(isProminent ? 0.96 : 0.82),
                                AppTheme.premiumEditorSurface.opacity(isProminent ? 0.9 : 0.76),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isProminent ? AppTheme.premiumEditorBorderGradient : LinearGradient(colors: [AppTheme.premiumEditorBorder.opacity(0.62)], startPoint: .leading, endPoint: .trailing), lineWidth: isProminent ? 1.1 : 0.8)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: tapped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "\(title). \(subtitle)",
                comment: "Accessibility label for a Lunar tracking hub card, including title and subtitle."
            )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}

private struct LunarWaveMark: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WaveBand(offsetY: 14, color: AppTheme.accentColor)
            WaveBand(offsetY: 3, color: AppTheme.premiumEditorAccentColor)
            WaveBand(offsetY: -8, color: AppTheme.premiumEditorSecondaryAccentColor)
        }
        .mask(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .padding(.leading, 16)
        )
    }

    private struct WaveBand: View {
        let offsetY: CGFloat
        let color: Color

        var body: some View {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 58))
                path.addCurve(
                    to: CGPoint(x: 134, y: 28 + offsetY),
                    control1: CGPoint(x: 34, y: 30 + offsetY),
                    control2: CGPoint(x: 80, y: 4 + offsetY)
                )
                path.addLine(to: CGPoint(x: 134, y: 58))
                path.closeSubpath()
            }
            .fill(color.opacity(0.68))
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            OvulationObservation.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            MealScanFoodItem.self,
            MealScanNutritionSummary.self,
            MealScanMetadata.self,
            MealScanResultCacheRecord.self,
            MealScanRepeatCacheRecord.self,
            NutritionImportRecord.self,
            HealthKitImportedSampleRecord.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
        .environment(AppLockManager())
        .environment(ReportAccessPolicy())
        .environment(AppearancePreferences.shared)
}
