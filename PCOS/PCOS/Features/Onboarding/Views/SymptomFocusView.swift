import SwiftUI

/// Multi-select symptom focus question for onboarding (Question 3).
/// Users can select up to 3 symptom focus areas to personalize their experience.
struct SymptomFocusView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var selectedAreas: Set<SymptomFocusArea> = []

    private static let maxSelections = 3

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            VStack(alignment: .leading, spacing: AppTheme.spacing16) {
                VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                    Text(L10n.string("Which symptoms matter most to you?", defaultValue: "Which symptoms matter most to you?"))
                        .appHeadingFont(.title2, weight: .regular)
                        .foregroundStyle(AppTheme.primaryText)
                    Text(L10n.string("We'll highlight these on your dashboard. You can always change this later.", defaultValue: "We'll highlight these on your dashboard. You can always change this later."))
                        .appFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.spacing24)

                if !selectedAreas.isEmpty {
                    Text(
                        String(
                            localized: "\(selectedAreas.count) of \(Self.maxSelections) selected",
                            comment: "Text showing how many symptom focus areas are selected during onboarding."
                        )
                    )
                        .appFont(.caption)
                        .foregroundStyle(AppTheme.accentColor)
                        .padding(.horizontal, AppTheme.spacing24)
                }

                VStack(spacing: AppTheme.spacing12) {
                    ForEach(SymptomFocusArea.allCases) { area in
                        MultiSelectableCard(
                            systemImage: area.systemImage,
                            title: area.displayName,
                            subtitle: area.subtitle,
                            value: area,
                            selection: $selectedAreas,
                            maxSelection: Self.maxSelections
                        )
                    }
                }
                .padding(.horizontal, AppTheme.spacing24)
            }

            Spacer()

            VStack(spacing: AppTheme.spacing12) {
                Button {
                    saveAndContinue()
                } label: {
                    Text(L10n.string("Continue", defaultValue: "Continue"))
                        .appFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(!selectedAreas.isEmpty ? AppTheme.accentColor : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(selectedAreas.isEmpty)

                Button(L10n.string("Skip", defaultValue: "Skip"), action: onSkip)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip symptom focus selection and continue setup")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .sensoryFeedback(.selection, trigger: selectedAreas.count)
    }

    private func saveAndContinue() {
        profile.symptomFocusAreas = Array(selectedAreas)
        onContinue()
    }
}

#Preview {
    SymptomFocusView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
