import SwiftUI

struct OnboardingMealScanDemoView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.spacing20) {
                    header
                    sampleEstimateCard
                    safetyCard
                }
                .padding(.horizontal, AppTheme.spacing24)
                .padding(.top, AppTheme.spacing24)
                .padding(.bottom, AppTheme.spacing16)
            }

            VStack(spacing: AppTheme.spacing12) {
                Button(action: onContinue) {
                    Text(L10n.string("Continue setup", defaultValue: "Continue setup"))
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                .fill(AppTheme.accentColor)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.meal_scan.continue")

                Button(action: onSkip) {
                    Text(L10n.string("Skip for now", defaultValue: "Skip for now"))
                }
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.meal_scan.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.meal_scan_demo")
    }

    private var header: some View {
        VStack(spacing: AppTheme.spacing12) {
            Image(systemName: "camera.viewfinder")
                .appFont(.largeTitle, weight: .semibold)
                .foregroundStyle(AppTheme.accentColor)
                .accessibilityHidden(true)

            Text(L10n.string("Photo estimates, with you in control", defaultValue: "Photo estimates, with you in control"))
                .appHeadingFont(.title2, weight: .regular)
                .foregroundStyle(AppTheme.primaryText)
                .multilineTextAlignment(.center)

            Text(L10n.string(
                "Take a meal photo to get an editable Google Gemini nutrition estimate after you consent. Fresh analyses use your rolling allowance; barcode scanning and manual meal logging remain available.",
                defaultValue: "Take a meal photo to get an editable Google Gemini nutrition estimate after you consent. Fresh analyses use your rolling allowance; barcode scanning and manual meal logging remain available."
            ))
            .appFont(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sampleEstimateCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            Label(
                L10n.string("Sample meal estimate", defaultValue: "Sample meal estimate"),
                systemImage: "sparkles"
            )
            .appFont(.caption, weight: .semibold)
            .foregroundStyle(AppTheme.coralAccent)

            VStack(alignment: .leading, spacing: AppTheme.spacing4) {
                Text(L10n.string("Chicken rice bowl", defaultValue: "Chicken rice bowl"))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)
                Text(L10n.string("Estimated from a sample preview. You review and edit before saving.", defaultValue: "Estimated from a sample preview. You review and edit before saving."))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.spacing8) {
                sampleMetric(title: L10n.string("Calories", defaultValue: "Calories"), value: "520")
                sampleMetric(title: L10n.string("Protein", defaultValue: "Protein"), value: "34g")
                sampleMetric(title: L10n.string("Carbs", defaultValue: "Carbs"), value: "58g")
                sampleMetric(title: L10n.string("Fats", defaultValue: "Fats"), value: "16g")
            }

            Label(
                L10n.string("Cycle note: pairing protein with carbs can support steadier energy during sensitive days.", defaultValue: "Cycle note: pairing protein with carbs can support steadier energy during sensitive days."),
                systemImage: "leaf.fill"
            )
            .appFont(.caption)
            .foregroundStyle(AppTheme.sage)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.spacing20)
        .background(cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.meal_scan.sample_estimate")
    }

    private func sampleMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(title)
                .appFont(.caption2, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.spacing12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium, style: .continuous)
                .fill(AppTheme.cardBackground.opacity(0.74))
        )
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: AppTheme.spacing12) {
            BotanicalIconBadge(systemImage: "checklist", color: AppTheme.sage, size: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(L10n.string("You choose before upload", defaultValue: "You choose before upload"))
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(AppTheme.primaryText)

                Text(L10n.string("Exact previous meals can be reused on this device. For a new photo estimate, CycleBalance asks before sending a compressed copy to Google Gemini. Barcode and manual entry stay available without a photo upload.", defaultValue: "Exact previous meals can be reused on this device. For a new photo estimate, CycleBalance asks before sending a compressed copy to Google Gemini. Barcode and manual entry stay available without a photo upload."))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.spacing16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
            .fill(AppTheme.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

#Preview {
    OnboardingMealScanDemoView(onContinue: {}, onSkip: {})
}
