import SwiftUI

/// Three-question profiling flow that determines the user's primary goal,
/// PCOS experience level, and symptom focus areas.
struct QuestionnaireView: View {
    let profile: OnboardingProfile
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var questionIndex = 0
    @State private var selectedGoal: PrimaryGoal?
    @State private var selectedExperience: PCOSExperience?
    @State private var selectedFocusAreas: Set<SymptomFocusArea> = []

    private static let totalQuestions = 3
    private static let maxFocusSelections = 3

    private var canContinue: Bool {
        switch questionIndex {
        case 0: selectedGoal != nil
        case 1: selectedExperience != nil
        case 2: !selectedFocusAreas.isEmpty
        default: false
        }
    }

    var body: some View {
        VStack(spacing: AppTheme.spacing24) {
            // Progress dots
            HStack(spacing: AppTheme.spacing8) {
                ForEach(0..<Self.totalQuestions, id: \.self) { index in
                    Circle()
                        .fill(index <= questionIndex ? AppTheme.accentColor : Color(.tertiarySystemFill))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: questionIndex)
                }
            }
            .padding(.top, AppTheme.spacing24)

            Group {
                switch questionIndex {
                case 0:
                    goalQuestion
                case 1:
                    experienceQuestion
                default:
                    focusQuestion
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

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
                Text("This helps us focus on what matters most to you.")
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
                Text("No wrong answers \u{2014} this helps us set the right pace.")
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

    private var focusQuestion: some View {
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

            if !selectedFocusAreas.isEmpty {
                Text("\(selectedFocusAreas.count) of \(Self.maxFocusSelections) selected")
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
                        selection: $selectedFocusAreas,
                        maxSelection: Self.maxFocusSelections
                    )
                }
            }
            .padding(.horizontal, AppTheme.spacing24)
        }
    }

    // MARK: - Actions

    private func advanceOrComplete() {
        switch questionIndex {
        case 0:
            profile.primaryGoal = selectedGoal
            withAnimation(.easeInOut(duration: 0.3)) {
                questionIndex = 1
            }
        case 1:
            profile.pcosExperience = selectedExperience
            withAnimation(.easeInOut(duration: 0.3)) {
                questionIndex = 2
            }
        default:
            profile.symptomFocusAreas = Array(selectedFocusAreas)
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
