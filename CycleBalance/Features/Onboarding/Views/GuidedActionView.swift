import SwiftUI

/// Transitional screen that presents the user's recommended first action.
/// Opens the existing CycleLogView or SymptomLogView as a sheet.
struct GuidedActionView: View {
    let profile: OnboardingProfile
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var showingSheet = false

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private var isLogPeriod: Bool {
        profile.suggestedFirstAction == .logPeriod
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: isLogPeriod ? "drop.fill" : "list.bullet.clipboard")
                .font(.system(size: iconSize))
                .foregroundStyle(isLogPeriod ? AppTheme.coralAccent : AppTheme.accentColor)
                .symbolEffect(.bounce, value: showingSheet)
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.spacing12) {
                Text(isLogPeriod
                     ? "Let's log your first period day"
                     : "How are you feeling today?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(isLogPeriod
                     ? "Even if your period isn't today, you can log your most recent one. This starts your cycle tracking."
                     : "Tap any symptoms you're experiencing. Even logging once helps start building your pattern.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    showingSheet = true
                } label: {
                    Label(
                        isLogPeriod ? "Log Period Day" : "Log Symptoms",
                        systemImage: isLogPeriod ? "drop.fill" : "list.bullet.clipboard"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isLogPeriod ? AppTheme.coralAccent : AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip this step and go to the dashboard")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.warmNeutral.ignoresSafeArea())
        .sheet(isPresented: $showingSheet, onDismiss: {
            profile.hasCompletedGuidedAction = true
            onComplete()
        }) {
            if isLogPeriod {
                CycleLogView()
            } else {
                SymptomLogView()
            }
        }
    }
}

#Preview {
    GuidedActionView(
        profile: OnboardingProfile(),
        onComplete: {},
        onSkip: {}
    )
}
