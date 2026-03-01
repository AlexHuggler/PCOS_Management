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
                    Text("Which symptoms matter most to you?")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("We'll highlight these on your dashboard. You can always change this later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppTheme.spacing24)

                if !selectedAreas.isEmpty {
                    Text("\(selectedAreas.count) of \(Self.maxSelections) selected")
                        .font(.caption)
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
                    Text("Continue")
                        .font(.headline)
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

                Button("Skip", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip symptom focus selection and continue setup")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
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
