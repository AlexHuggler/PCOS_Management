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

/// Hub view for the Track tab, providing access to all logging features
struct TrackingHubView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    CycleLogView()
                } label: {
                    Label("Log Period", systemImage: "drop.fill")
                }

                NavigationLink {
                    SymptomLogView()
                } label: {
                    Label("Log Symptoms", systemImage: "list.bullet.clipboard")
                }
            }
            .navigationTitle("Track")
        }
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
