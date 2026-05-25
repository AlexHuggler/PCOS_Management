import StoreKit
import SwiftUI

/// App Store rating prompt screen shown after permissions during onboarding.
/// Uses mission-driven framing to encourage ratings.
struct RatingPromptView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @Environment(\.requestReview) private var requestReview
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 56

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            Spacer()

            Image(systemName: "heart.circle")
                .font(.system(size: iconSize))
                .foregroundStyle(AppTheme.coralAccent)
                .accessibilityHidden(true)

            Text(String(localized: "Support our mission", comment: "Rating prompt headline."))
                .appHeadingFont(.title2, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(String(localized: "We're a small team dedicated to giving women with PCOS actionable insights from their data, to manage and improve their lives. A rating on the App Store helps others find us.", comment: "Rating prompt body text."))
                .appFont(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.spacing24)

            Spacer()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    profile.hasPromptedForReview = true
                    requestReview()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        onContinue()
                    }
                } label: {
                    Text(String(localized: "Leave a Quick Review", comment: "Primary rating prompt button label."))
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(AppTheme.coralAccent)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.rating.rate")

                Button {
                    profile.hasPromptedForReview = true
                    onSkip()
                } label: {
                    Text(String(localized: "Maybe later", comment: "Rating prompt skip button label."))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.rating.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.rating")
        .onAppear {
            if profile.hasPromptedForReview {
                onContinue()
            }
        }
    }
}

#Preview {
    RatingPromptView(profile: OnboardingProfile(), onContinue: {}, onSkip: {})
}
