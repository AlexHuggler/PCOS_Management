import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var premiumStateBridge = PremiumStateBridge()

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                TabView(selection: $appState.selectedTab) {
                    TodayView()
                        .tabItem {
                            Label(AppTab.today.title, systemImage: AppTab.today.systemImage)
                        }
                        .tag(AppTab.today)

                    CalendarMonthView()
                        .tabItem {
                            Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage)
                        }
                        .tag(AppTab.calendar)

                    TrackingHubView()
                        .tabItem {
                            Label(AppTab.track.title, systemImage: AppTab.track.systemImage)
                        }
                        .tag(AppTab.track)

                    InsightsView()
                        .tabItem {
                            Label(AppTab.insights.title, systemImage: AppTab.insights.systemImage)
                        }
                        .tag(AppTab.insights)

                    SettingsView()
                        .tabItem {
                            Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                        }
                        .tag(AppTab.settings)
                }
                .tint(AppTheme.accentColor)
                .environment(appState)
            } else {
                OnboardingContainerView {
                    appState.hasCompletedOnboarding = true
                }
                .environment(appState)
            }
        }
        .task {
            premiumStateBridge.start(appState: appState)
        }
        .onDisappear {
            premiumStateBridge.stop()
        }
    }
}

/// Hub view for the Track tab — direct sheet presentation for quick logging
struct TrackingHubView: View {
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false
    @State private var showingLogBloodSugar = false
    @State private var showingLogSupplements = false
    @State private var showingLogMeal = false
    @State private var showingPhotoJournal = false
    @State private var recentShortcut = UserEntryDefaultsStore.shared.lastLoggerShortcut

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmNeutral.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.spacing16) {
                        if let recentShortcut {
                            Button {
                                open(shortcut: recentShortcut)
                            } label: {
                                HStack(spacing: AppTheme.spacing12) {
                                    Label("Recent", systemImage: "clock.arrow.circlepath")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Label(recentShortcut.title, systemImage: recentShortcut.systemImage)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundStyle(AppTheme.accentColor)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(AppTheme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        TrackingCard(
                            title: "Log Period",
                            subtitle: "Record flow intensity and notes",
                            systemImage: "drop.fill",
                            color: AppTheme.coralAccent
                        ) {
                            open(shortcut: .period)
                        }

                        TrackingCard(
                            title: "Log Symptoms",
                            subtitle: "Track how you're feeling today",
                            systemImage: "list.bullet.clipboard",
                            color: AppTheme.accentColor
                        ) {
                            open(shortcut: .symptoms)
                        }

                        TrackingCard(
                            title: "Log Blood Sugar",
                            subtitle: "Record glucose readings",
                            systemImage: "drop.triangle.fill",
                            color: .orange
                        ) {
                            open(shortcut: .bloodSugar)
                        }

                        TrackingCard(
                            title: "Log Supplements",
                            subtitle: "Track your daily supplements",
                            systemImage: "pills.fill",
                            color: AppTheme.accentColor
                        ) {
                            open(shortcut: .supplements)
                        }

                        TrackingCard(
                            title: "Log Meal",
                            subtitle: "Record meals and glycemic impact",
                            systemImage: "fork.knife",
                            color: AppTheme.sage
                        ) {
                            open(shortcut: .meal)
                        }

                        TrackingCard(
                            title: "Photo Journal",
                            subtitle: "Track hair and skin changes",
                            systemImage: "camera.fill",
                            color: AppTheme.sage
                        ) {
                            open(shortcut: .photo)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Track")
            .sheet(isPresented: $showingLogPeriod) {
                CycleLogView()
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
                MealLogView()
            }
            .sheet(isPresented: $showingPhotoJournal) {
                PhotoGalleryView()
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
        case .symptoms:
            showingLogSymptoms = true
        case .bloodSugar:
            showingLogBloodSugar = true
        case .supplements:
            showingLogSupplements = true
        case .meal:
            showingLogMeal = true
        case .photo:
            showingPhotoJournal = true
        }
    }
}

struct TrackingCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    @State private var tapped = false

    var body: some View {
        Button {
            tapped.toggle()
            action()
        } label: {
            HStack(spacing: AppTheme.spacing16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(color.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.cardBackground)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: tapped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            CycleEntry.self,
            Cycle.self,
            SymptomEntry.self,
            Insight.self,
            BloodSugarReading.self,
            SupplementLog.self,
            MealEntry.self,
            HairPhotoEntry.self,
            DailyLog.self,
        ], inMemory: true)
}
