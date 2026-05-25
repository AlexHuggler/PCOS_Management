import SwiftUI

// MARK: - Testimonial Model

private struct Testimonial: Identifiable {
    let id = UUID()
    let quote: String
    let name: String
    let tag: String
}

private let testimonials: [Testimonial] = [
    Testimonial(
        quote: String(localized: "I finally understand why I feel different on certain days. This app connected the dots.", comment: "Testimonial quote from Sarah on the social proof screen."),
        name: "Sarah",
        tag: String(localized: "Recently Diagnosed", comment: "Testimonial author tag.")
    ),
    Testimonial(
        quote: String(localized: "After 3 months of logging, I brought my data to my doctor and we adjusted my treatment plan together.", comment: "Testimonial quote from Mia on the social proof screen."),
        name: "Mia",
        tag: String(localized: "Symptom Tracking", comment: "Testimonial author tag.")
    ),
    Testimonial(
        quote: String(localized: "I was skeptical, but seeing my symptom patterns mapped to my cycle was a game-changer.", comment: "Testimonial quote from Jade on the social proof screen."),
        name: "Jade",
        tag: String(localized: "Pattern Recognition", comment: "Testimonial author tag.")
    ),
]

// MARK: - Social Proof View

/// Social proof screen showing testimonials and community stats during onboarding.
struct SocialProofView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing24) {
                    // MARK: Section Header
                    Text(String(localized: "What women are saying", comment: "Social proof section header on the onboarding screen."))
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.spacing24)

                    // MARK: Testimonial Cards
                    ForEach(testimonials) { testimonial in
                        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                            Image(systemName: "quote.opening")
                                .appFont(.title3)
                                .foregroundStyle(AppTheme.accentColor.opacity(AppTheme.opacityStrong))
                                .accessibilityHidden(true)

                            Text(testimonial.quote)
                                .appFont(.body)
                                .italic()

                            HStack {
                                Text(testimonial.name)
                                    .appFont(.body, weight: .semibold)
                                Text(verbatim: "· ")
                                Text(testimonial.tag)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)

                            }
                        }
                        .cardStyle()
                        .padding(.horizontal, AppTheme.spacing24)
                    }

                    // MARK: Beta Community
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "person.2.fill")
                            .appFont(.title3)
                            .foregroundStyle(AppTheme.accentColor)
                            .accessibilityHidden(true)
                        Text(String(localized: "Built and tested with 200+ women in our beta community", comment: "Beta community stat on social proof screen."))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppTheme.spacing16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .fill(AppTheme.accentColor.opacity(AppTheme.opacitySubtle))
                    )
                    .padding(.horizontal, AppTheme.spacing24)

                    // MARK: Founder Note
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(AppTheme.coralAccent)
                            .accessibilityHidden(true)

                        Text(String(localized: "Built to give women with PCOS the insights they deserve.", comment: "Founder note on the social proof screen."))
                            .appFont(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(AppTheme.spacing16)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                            .fill(AppTheme.coralAccent.opacity(AppTheme.opacitySubtle))
                    )
                    .padding(.horizontal, AppTheme.spacing24)

                    Spacer(minLength: AppTheme.spacing24)
                }
            }

            // MARK: Bottom Buttons
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    onContinue()
                } label: {
                    Text(String(localized: "Continue", comment: "Social proof continue button label."))
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
                .accessibilityIdentifier("onboarding.social_proof.continue")

                Button {
                    onSkip()
                } label: {
                    Text(String(localized: "Skip", comment: "Social proof skip button label."))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.social_proof.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.social_proof")
    }

}

#Preview {
    SocialProofView(onContinue: {}, onSkip: {})
}
