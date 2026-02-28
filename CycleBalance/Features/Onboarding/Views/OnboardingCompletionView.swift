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

            Text("You're all set!")
                .font(.title)
                .fontWeight(.bold)

            Text(personalizedMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            Button {
                onFinish()
            } label: {
                Text("Start Exploring")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.spacing12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(AppTheme.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.warmNeutral.ignoresSafeArea())
        .onAppear {
            appeared = true
        }
    }

    private var personalizedMessage: String {
        switch profile.primaryGoal {
        case .trackCycles:
            "Log your period when it arrives and CycleBalance will start predicting your next one."
        case .understandSymptoms:
            "Log how you feel each day. After 2 cycles, you'll see your first insights."
        case nil:
            "Your CycleBalance journey starts now."
        }
    }
}

#Preview {
    OnboardingCompletionView(profile: OnboardingProfile(), onFinish: {})
}
