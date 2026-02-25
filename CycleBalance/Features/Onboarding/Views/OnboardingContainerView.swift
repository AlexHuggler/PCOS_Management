import SwiftUI

/// Root container that orchestrates the onboarding flow:
/// welcome pages -> questionnaire -> guided first action -> completion.
struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var phase: OnboardingPhase = .welcome

    private var stepNumber: Int {
        switch phase {
        case .welcome: 1
        case .questionnaire: 2
        case .guidedAction: 3
        case .completion: 4
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: AppTheme.spacing8) {
                ForEach(1...4, id: \.self) { step in
                    Capsule()
                        .fill(step <= stepNumber ? AppTheme.accentColor : Color(.tertiarySystemFill))
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.3), value: stepNumber)
                }
            }
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing8)

            Text("Step \(stepNumber) of 4")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, AppTheme.spacing4)
        }

        Group {
            switch phase {
            case .welcome:
                WelcomePagerView {
                    appState.onboardingProfile.hasCompletedWelcome = true
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .questionnaire
                    }
                } onSkip: {
                    completeOnboarding()
                }

            case .questionnaire:
                QuestionnaireView(profile: appState.onboardingProfile) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .guidedAction
                    }
                } onSkip: {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .guidedAction
                    }
                }

            case .guidedAction:
                GuidedActionView(profile: appState.onboardingProfile) {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        phase = .completion
                    }
                } onSkip: {
                    completeOnboarding()
                }

            case .completion:
                OnboardingCompletionView {
                    completeOnboarding()
                }
            }
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) {
            onComplete()
        }
    }
}

// MARK: - Onboarding Phase

private enum OnboardingPhase {
    case welcome
    case questionnaire
    case guidedAction
    case completion
}

#Preview {
    OnboardingContainerView(onComplete: {})
        .environment(AppState())
        .modelContainer(for: [CycleEntry.self, Cycle.self, SymptomEntry.self], inMemory: true)
}
