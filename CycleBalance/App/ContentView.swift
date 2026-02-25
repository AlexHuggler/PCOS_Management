import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        if appState.hasCompletedOnboarding {
            TabView(selection: $appState.selectedTab) {
                Tab("Today", systemImage: AppTab.today.systemImage, value: .today) {
                    TodayView()
                }

                Tab("Calendar", systemImage: AppTab.calendar.systemImage, value: .calendar) {
                    CalendarMonthView()
                }

                Tab("Track", systemImage: AppTab.track.systemImage, value: .track) {
                    TrackingHubView()
                }

                Tab("Insights", systemImage: AppTab.insights.systemImage, value: .insights) {
                    InsightsView()
                }

                Tab("Settings", systemImage: AppTab.settings.systemImage, value: .settings) {
                    SettingsView()
                }
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
}

/// Hub view for the Track tab — direct sheet presentation for quick logging
struct TrackingHubView: View {
    @State private var showingLogPeriod = false
    @State private var showingLogSymptoms = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.spacing16) {
                    TrackingCard(
                        title: "Log Period",
                        subtitle: "Record flow intensity and notes",
                        systemImage: "drop.fill",
                        color: AppTheme.coralAccent
                    ) {
                        showingLogPeriod = true
                    }

                    TrackingCard(
                        title: "Log Symptoms",
                        subtitle: "Track how you're feeling today",
                        systemImage: "list.bullet.clipboard",
                        color: AppTheme.accentColor
                    ) {
                        showingLogSymptoms = true
                    }
                }
                .padding()
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("Track")
            .sheet(isPresented: $showingLogPeriod) {
                CycleLogView()
            }
            .sheet(isPresented: $showingLogSymptoms) {
                SymptomLogView()
            }
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

                VStack(alignment: .leading, spacing: 4) {
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
        ], inMemory: true)
}
