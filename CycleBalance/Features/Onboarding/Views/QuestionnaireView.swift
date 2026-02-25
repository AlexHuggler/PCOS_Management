import SwiftUI

/// Two-question profiling flow that determines the user's primary goal and PCOS experience level.
struct QuestionnaireView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var questionIndex = 0
    @State private var selectedGoal: PrimaryGoal?
    @State private var selectedExperience: PCOSExperience?

    private var canContinue: Bool {
        questionIndex == 0 ? selectedGoal != nil : selectedExperience != nil
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            // Progress dots
            HStack(spacing: AppTheme.spacing8) {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .fill(index <= questionIndex ? AppTheme.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: questionIndex)
                }
            }
            .padding(.top, AppTheme.spacing24)

            if questionIndex == 0 {
                goalQuestion
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                experienceQuestion
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }

            Spacer()

            // Continue + Skip
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    advanceOrComplete()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.spacing12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(canContinue ? AppTheme.accentColor : Color.gray.opacity(0.3))
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)

                Button("Skip", action: skipQuestionnaire)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip the questionnaire and continue setup")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(AppTheme.warmNeutral.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: questionIndex)
    }

    // MARK: - Questions

    private var goalQuestion: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text("What brings you to CycleBalance?")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("This helps us personalize your experience.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.spacing24)

            VStack(spacing: AppTheme.spacing12) {
                ForEach(PrimaryGoal.allCases) { goal in
                    SelectableCard(
                        systemImage: goal.systemImage,
                        title: goal.displayName,
                        subtitle: goal.subtitle,
                        value: goal,
                        selection: $selectedGoal
                    )
                }
            }
            .padding(.horizontal, AppTheme.spacing24)
        }
    }

    private var experienceQuestion: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text("How long have you been managing PCOS?")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("No wrong answers here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.spacing24)

            VStack(spacing: AppTheme.spacing12) {
                ForEach(PCOSExperience.allCases) { experience in
                    SelectableCard(
                        systemImage: experience.systemImage,
                        title: experience.displayName,
                        subtitle: experience.subtitle,
                        value: experience,
                        selection: $selectedExperience
                    )
                }
            }
            .padding(.horizontal, AppTheme.spacing24)
        }
    }

    // MARK: - Actions

    private func advanceOrComplete() {
        if questionIndex == 0 {
            profile.primaryGoal = selectedGoal
            withAnimation(.easeInOut(duration: 0.3)) {
                questionIndex = 1
            }
        } else {
            profile.pcosExperience = selectedExperience
            profile.hasCompletedQuestionnaire = true
            onContinue()
        }
    }

    private func skipQuestionnaire() {
        profile.hasCompletedQuestionnaire = true
        onSkip()
    }
}

#Preview {
    QuestionnaireView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
