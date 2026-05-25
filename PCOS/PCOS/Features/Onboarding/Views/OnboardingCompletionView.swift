import SwiftUI

/// Celebratory screen shown after completing onboarding.
/// Displays a personalized goal message based on the user's questionnaire answers.
struct OnboardingCompletionView: View {
    let profile: OnboardingProfile
    let onFinish: () -> Void

    @State private var appeared = false

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 72

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.accentColor)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            Text(String(localized: "You're all set!", comment: "Onboarding completion headline."))
                .appHeadingFont(.title, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)

            Text(personalizedMessage)
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            Text(String(localized: "We're a small team building this for you — find \"Share Feedback\" in Settings anytime.", comment: "Feedback invitation on the completion screen."))
                .appFont(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            Button {
                onFinish()
            } label: {
                Text(String(localized: "Start Exploring", comment: "Primary onboarding completion button label."))
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
            .accessibilityIdentifier("onboarding.completion.finish")
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.completion")
        .onAppear {
            appeared = true
        }
    }

    private var personalizedMessage: String {
        switch profile.primaryGoal {
        case .trackCycles:
            String(localized: "Everything's set. Log when you're ready — CycleBalance adapts to your rhythm, not the other way around.", comment: "Onboarding completion message for users focused on cycle tracking.")
        case .understandSymptoms:
            String(localized: "Your tracking journey starts now. You're part of a growing community of women making sense of their symptoms.", comment: "Onboarding completion message for users focused on symptoms.")
        case nil:
            String(localized: "You're part of a growing community of women taking control of their PCOS. We're glad you're here.", comment: "Generic onboarding completion message.")
        }
    }
}

#Preview {
    OnboardingCompletionView(profile: OnboardingProfile(), onFinish: {})
}
