import SwiftUI

/// Personalized results screen shown after the quiz.
/// Reflects the user's answers back to build an "this app gets me" moment.
struct ResultsView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    private var privacySummary: String {
        if MealScanFeatureFlags.current.enableMealScanV2 {
            return L10n.string(
                "Your health logs stay on this device by default. Optional photo estimates are sent only after you confirm each upload.",
                defaultValue: "Your health logs stay on this device by default. Optional photo estimates are sent only after you confirm each upload."
            )
        }

        return L10n.string(
            "Your health logs stay on this device by default.",
            defaultValue: "Your health logs stay on this device by default."
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.spacing24) {
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
                    .fixedSize(horizontal: false, vertical: true)

                // Subheadline
                Text(profile.resultsSubheadline)
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // Reassuring stat card
                HStack(spacing: AppTheme.spacing12) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(AppTheme.accentColor)
                        .accessibilityHidden(true)

                    Text(profile.resultsStat)
                        .appFont(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .cardStyle()

                // Focus area chips
                if !profile.symptomFocusAreas.isEmpty {
                    FlowLayout(spacing: AppTheme.spacing8) {
                        ForEach(profile.symptomFocusAreas) { area in
                            HStack(spacing: AppTheme.spacing4) {
                                Image(systemName: area.systemImage)
                                    .accessibilityHidden(true)
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
                HStack(alignment: .top, spacing: AppTheme.spacing8) {
                    Image(systemName: "lock.shield")
                        .accessibilityHidden(true)

                    Text(privacySummary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appFont(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing32)
            .padding(.bottom, AppTheme.spacing24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("screen.onboarding.results")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            resultsActions
        }
        .background(BotanicalScreenBackground(style: .dense))
        .onAppear { appeared = true }
    }

    private var resultsActions: some View {
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
        .padding(.top, AppTheme.spacing12)
        .padding(.bottom, AppTheme.spacing24)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ResultsView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
