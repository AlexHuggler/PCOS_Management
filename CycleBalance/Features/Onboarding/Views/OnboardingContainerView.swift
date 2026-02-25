import SwiftUI

/// Root container that orchestrates the onboarding flow:
/// welcome pages -> questionnaire -> guided first action -> completion.
struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var phase: OnboardingPhase = .welcome

    var body: some View {
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
