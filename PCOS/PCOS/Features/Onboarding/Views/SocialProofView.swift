import SwiftUI

// MARK: - Assurance Model

private struct OnboardingAssurance: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
}

private let onboardingAssurances: [OnboardingAssurance] = [
    OnboardingAssurance(
        icon: "lock.shield.fill",
        title: String(localized: "Local health records", comment: "Assurance card title on the onboarding screen."),
        message: String(localized: "Your cycle, symptom, meal, glucose, supplement, and photo logs are stored on your device by default.", comment: "Assurance card body on the onboarding screen.")
    ),
    OnboardingAssurance(
        icon: "checkmark.seal.fill",
        title: String(localized: "Review before saving", comment: "Assurance card title on the onboarding screen."),
        message: String(localized: "Meal and barcode results stay editable so nothing becomes a saved log until you choose it.", comment: "Assurance card body on the onboarding screen.")
    ),
    OnboardingAssurance(
        icon: "doc.text.fill",
        title: String(localized: "Care-team ready", comment: "Assurance card title on the onboarding screen."),
        message: String(localized: "Exportable reports help you bring organized context to appointments without replacing medical care.", comment: "Assurance card body on the onboarding screen.")
    ),
]

// MARK: - Social Proof View

/// Onboarding assurance screen that summarizes review-safe product principles.
struct SocialProofView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing24) {
                    // MARK: Section Header
                    Text(String(localized: "Built around your data, not hype", comment: "Assurance section header on the onboarding screen."))
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppTheme.spacing24)

                    // MARK: Assurance Cards
                    ForEach(onboardingAssurances) { assurance in
                        VStack(alignment: .leading, spacing: AppTheme.spacing12) {
                            Image(systemName: assurance.icon)
                                .appFont(.title3)
                                .foregroundStyle(AppTheme.accentColor.opacity(AppTheme.opacityStrong))
                                .accessibilityHidden(true)

                            Text(assurance.title)
                                .appFont(.headline, weight: .semibold)

                            Text(assurance.message)
                                .appFont(.body)
                                .foregroundStyle(.secondary)
                        }
                        .cardStyle()
                        .padding(.horizontal, AppTheme.spacing24)
                    }

                    // MARK: Product Principle
                    HStack(spacing: AppTheme.spacing12) {
                        Image(systemName: "sparkles")
                            .appFont(.title3)
                            .foregroundStyle(AppTheme.accentColor)
                            .accessibilityHidden(true)
                        Text(String(localized: "Designed for PCOS-aware tracking, irregular cycles, and reviewable health context.", comment: "Product principle on onboarding assurance screen."))
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

            // MARK: Bottom Button
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
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.social_proof")
    }

}

#Preview {
    SocialProofView(onContinue: {})
}
