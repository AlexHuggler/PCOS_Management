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
        .id("\(appState.languageRenderKey)-\(appearancePreferences.renderKey.uuidString)")
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
        .environment(\.locale, appState.renderLocale)
    }

    @ViewBuilder
    private var mainTabs: some View {
        if AppTheme.isBotanicalJournal {
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
                            colors: [
                                AppTheme.botanicalCreamRGB.color.opacity(0),
                                AppTheme.botanicalCreamRGB.color.opacity(0.94),
                                AppTheme.botanicalCreamRGB.color
                            ],
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
        .padding(.vertical, AppTheme.spacing8)
        .background(
            Capsule()
                .fill(AppTheme.botanicalCreamAltRGB.color.opacity(0.98))
                .shadow(color: AppTheme.botanicalRoseRGB.color.opacity(0.18), radius: 18, y: 8)
        )
        .overlay(
            Capsule()
                .strokeBorder(AppTheme.botanicalRoseSoftRGB.color.opacity(0.38), lineWidth: 0.9)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("botanical.tab_bar")
    }
}

private struct BotanicalTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let language: AppLanguage
    let action: () -> Void

    private var foregroundColor: Color {
        isSelected ? AppTheme.primaryText : AppTheme.botanicalSageRGB.color.opacity(0.82)
    }

    private var fillColor: Color {
        isSelected ? AppTheme.botanicalCreamRGB.color.opacity(0.96) : .clear
    }

    private var borderColor: Color {
        isSelected ? AppTheme.botanicalRoseSoftRGB.color.opacity(0.45) : .clear
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .appFont(.subheadline, weight: isSelected ? .semibold : .regular)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 28, height: 22)

                Text(tab.title(for: language))
                    .appFont(.caption2, weight: isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.spacing8)
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
    @State private var showingPhotoJournal = false
    @State private var recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut

    var body: some View {
        NavigationStack {
            ZStack {
                BotanicalScreenBackground()

                ScrollView {
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
                            color: .orange
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
                    .padding()
                    .padding(.bottom, AppTheme.botanicalScrollableBottomPadding)
                }
            }
            .navigationTitle(L10n.string("Track", defaultValue: "Track"))
            .sheet(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogOvulation) {
                OvulationLogView()
            }
            .sheet(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
            .sheet(isPresented: $showingLogBloodSugar) {
                BloodSugarLogView()
            }
            .sheet(isPresented: $showingLogSupplements) {
                SupplementLogView()
            }
            .sheet(isPresented: $showingLogMeal) {
                MealLogView(entryPoint: .trackingHub)
            }
            .sheet(isPresented: $showingPhotoJournal) {
                PhotoGalleryView()
            }
            .onChange(of: showingLogMeal) { _, isPresented in
                Logger.meals.info("TrackingHubView meal log sheet state changed: \(isPresented, privacy: .public)")
            }
            .onAppear {
                recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut
            }
        }
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
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
        .environment(AppLockManager())
        .environment(ReportAccessPolicy())
        .environment(AppearancePreferences.shared)
}
