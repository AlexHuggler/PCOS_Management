import SwiftUI

/// Personalized plan / dashboard preview screen (R-17, R-18).
/// This is the "this was built for me" commitment moment that shows
/// the user what CycleBalance has set up based on their answers.
struct YourPlanView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing24) {

                    // MARK: - Header

                    VStack(spacing: AppTheme.spacing8) {
                        Text(String(
                            localized: "Your CycleBalance Plan",
                            comment: "Personalized plan screen headline."
                        ))
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .multilineTextAlignment(.center)

                        Text(String(
                            localized: "Based on your answers, here's what we've set up for you.",
                            comment: "Personalized plan screen subheadline."
                        ))
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppTheme.spacing24)
                    .padding(.top, AppTheme.spacing16)

                    // MARK: - Plan Item Cards

                    ForEach(Array(profile.planItems.enumerated()), id: \.element.id) { offset, item in
                        HStack(spacing: AppTheme.spacing16) {
                            BotanicalIconBadge(systemImage: item.systemImage, color: AppTheme.accentColor, size: 44)
                                .accessibilityHidden(true)

                            // Title and subtitle
                            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                                Text(item.title)
                                    .appHeadingFont(.headline, weight: .regular)
                                    .foregroundStyle(AppTheme.primaryText)

                                Text(item.subtitle)
                                    .appFont(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)

                            // Checkmark
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accentColor)
                        }
                        .cardStyle()
                        .opacity(appeared ? 1 : 0)
                        .animation(
                            .easeInOut(duration: 0.3).delay(Double(offset) * 0.12),
                            value: appeared
                        )
                        .padding(.horizontal, AppTheme.spacing24)
                    }

                    // MARK: - Timeline Note

                    Text(OnboardingThresholdCopy.timelineNote(for: profile.primaryGoal))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, AppTheme.spacing8)
                }
            }

            // MARK: - Buttons

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    onContinue()
                } label: {
                    Text(String(
                        localized: "Continue",
                        comment: "Primary button on the personalized plan screen."
                    ))
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
                .accessibilityIdentifier("onboarding.your_plan.continue")

                Button {
                    onSkip()
                } label: {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.your_plan.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.your_plan")
        .onAppear {
            appeared = true
        }
    }
}

#Preview {
    YourPlanView(profile: OnboardingProfile(), onContinue: {}, onSkip: {})
}
