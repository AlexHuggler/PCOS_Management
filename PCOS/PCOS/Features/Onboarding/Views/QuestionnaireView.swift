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
            .simultaneousGesture(boundedQuestionnaireSwipeGesture)

            Spacer()

            // Continue + Skip
            VStack(spacing: AppTheme.spacing12) {
                Button {
                    advanceOrComplete()
                } label: {
                    Text(String(localized: "Continue", comment: "Primary questionnaire button label."))
                        .appFont(.headline)
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
                .accessibilityIdentifier("onboarding.questionnaire.continue")

                Button {
                    skipQuestionnaire()
                } label: {
                    Text(String(localized: "Skip", comment: "Secondary questionnaire button label."))
                }
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHint(
                        Text(
                            String(
                                localized: "Skip the questionnaire and continue setup",
                                comment: "Accessibility hint for the questionnaire skip button."
                            )
                        )
                    )
                    .accessibilityIdentifier("onboarding.questionnaire.skip")
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.bottom, AppTheme.spacing32)
        }
        .background(BotanicalScreenBackground(style: .dense))
        .sensoryFeedback(.selection, trigger: questionIndex)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding.questionnaire")
    }

    private var boundedQuestionnaireSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 42, coordinateSpace: .local)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard abs(horizontalDistance) > max(72, verticalDistance * 1.6) else {
                    return
                }

                if horizontalDistance < 0 {
                    guard canContinue else { return }
                    advanceOrComplete()
                } else {
                    retreatQuestion()
                }
            }
    }

    // MARK: - Questions

    private var goalQuestion: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing16) {
            VStack(alignment: .leading, spacing: AppTheme.spacing8) {
                Text(String(localized: "What brings you to CycleBalance?", comment: "Questionnaire heading asking for the user's primary goal."))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(String(localized: "This helps us focus on what matters most to you.", comment: "Questionnaire helper text under the primary goal heading."))
                    .appFont(.subheadline)
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
                Text(String(localized: "How long have you been managing PCOS?", comment: "Questionnaire heading asking about PCOS experience."))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(String(localized: "No wrong answers — this helps us set the right pace.", comment: "Questionnaire helper text under the PCOS experience heading."))
                    .appFont(.subheadline)
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
                Text(String(localized: "Which symptoms matter most to you?", comment: "Questionnaire heading asking about symptom priorities."))
                    .appHeadingFont(.title2, weight: .regular)
                    .foregroundStyle(AppTheme.primaryText)
                Text(String(localized: "We'll highlight these on your dashboard. You can always change this later.", comment: "Questionnaire helper text under the symptom focus heading."))
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppTheme.spacing24)

            if !selectedFocusAreas.isEmpty {
                Text(
                    String(
                        localized: "\(selectedFocusAreas.count) of \(Self.maxFocusSelections) selected",
                        comment: "Questionnaire progress text showing how many symptom focus areas are selected."
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

    private func retreatQuestion() {
        guard questionIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            questionIndex -= 1
        }
    }
}

#Preview {
    QuestionnaireView(
        profile: OnboardingProfile(),
        onContinue: {},
        onSkip: {}
    )
}
