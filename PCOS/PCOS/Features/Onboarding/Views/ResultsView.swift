import SwiftUI

/// Personalized results screen shown after the quiz.
/// Reflects the user's answers back to build an "this app gets me" moment.
struct ResultsView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            // Hero icon
            Image(systemName: profile.primaryGoal?.systemImage ?? "sparkles")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            // Headline
            Text(profile.resultsHeadline)
                .appHeadingFont(.title2, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            // Subheadline
            Text(profile.resultsSubheadline)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            // Reassuring stat card
            HStack(spacing: AppTheme.spacing12) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(AppTheme.accentColor)
                    .accessibilityHidden(true)

                Text(profile.resultsStat)
                    .appFont(.subheadline)
            }
            .cardStyle()
            .padding(.horizontal, AppTheme.spacing24)

            // Focus area chips
            if !profile.symptomFocusAreas.isEmpty {
                HStack(spacing: AppTheme.spacing8) {
                    ForEach(profile.symptomFocusAreas) { area in
                        HStack(spacing: AppTheme.spacing4) {
                            Image(systemName: area.systemImage)
                            Text(area.displayName)
                        }
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.accentColor)
                        .padding(.horizontal, AppTheme.spacing12)
                        .padding(.vertical, AppTheme.spacing8)
                        .background(
                            AppTheme.accentColor.opacity(AppTheme.opacitySubtle)
                        )
                        .clipShape(Capsule())
                    }
                }
            }

            // Privacy message
            HStack(spacing: AppTheme.spacing8) {
                Image(systemName: "lock.shield")
                    .accessibilityHidden(true)

                Text(
                    String(
                        localized: "Your health data stays on your device. No accounts, no servers, no exceptions.",
                        comment: "Privacy reassurance message shown on the results screen."
                    )
                )
            }
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            // Continue + Skip
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    onContinue()
                } label: {
                    Text(String(localized: "Continue", comment: "Primary button label on the results screen."))
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.results.continue")

                Button {
                    onSkip()
                } label: {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.results.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityIdentifier("screen.onboarding.results")
        .onAppear { appeared = true }
    }
}

#Preview {
    ResultsView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
