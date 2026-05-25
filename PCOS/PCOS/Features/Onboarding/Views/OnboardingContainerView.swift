import SwiftUI

/// Root container that orchestrates the 9-phase onboarding flow:
/// quiz -> results -> how app helps -> social proof -> rating ->
/// your plan -> first log -> permissions -> all set.
struct OnboardingContainerView: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @State private var phase: OnboardingPhase

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        _phase = State(initialValue: Self.initialPhase())
    }

    private var progress: CGFloat {
        let currentIndex = OnboardingPhase.allCases.firstIndex(of: phase) ?? 0
        let phaseCount = max(OnboardingPhase.allCases.count - 1, 1)
        let rawProgress = CGFloat(currentIndex) / CGFloat(phaseCount)
        return LayoutDimensionSanitizer.normalizedProgress(from: rawProgress)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Continuous progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.isBotanicalJournal ? AppTheme.lavenderAccent.opacity(0.18) : AppTheme.accentColor.opacity(AppTheme.opacityLight))
                    Capsule()
                        .fill(AppTheme.isBotanicalJournal ? AppTheme.roseAccent : AppTheme.accentColor)
                        .frame(
                            width: LayoutDimensionSanitizer.frameDimension(
                                from: geometry.size.width * progress
                            )
                        )
                }
            }
            .frame(height: 6)
            .padding(.horizontal, AppTheme.spacing24)
            .padding(.top, AppTheme.spacing8)
            .animation(.easeInOut(duration: 0.3), value: phase)
        }

        Group {
            switch phase {
            case .quiz:
                QuestionnaireView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .results:
                ResultsView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .howAppHelps:
                HowAppHelpsView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .socialProof:
                SocialProofView(onContinue: { advance() }, onSkip: { advance() })

            case .yourPlan:
                YourPlanView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .firstLog:
                GuidedActionView(profile: appState.onboardingProfile, onComplete: { advance() }, onSkip: { advance() })

            case .permissions:
                PermissionsStepView(onContinue: { advance() }, onSkip: { advance() })

            case .rating:
                RatingPromptView(profile: appState.onboardingProfile, onContinue: { advance() }, onSkip: { advance() })

            case .allSet:
                OnboardingCompletionView(profile: appState.onboardingProfile, onFinish: { completeOnboarding() })
            }
        }
    }

    private func advance() {
        guard
            let currentIndex = OnboardingPhase.allCases.firstIndex(of: phase),
            currentIndex + 1 < OnboardingPhase.allCases.count
        else {
            completeOnboarding()
            return
        }
        let next = OnboardingPhase.allCases[currentIndex + 1]
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = next
        }
    }

    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.35)) {
            onComplete()
        }
    }

    private static func initialPhase(arguments: [String] = ProcessInfo.processInfo.arguments) -> OnboardingPhase {
        guard arguments.contains("UITestMode") else {
            return .quiz
        }

        guard let phaseValue = launchArgumentValue(for: "onboarding.startPhase", in: arguments) else {
            return .quiz
        }

        return OnboardingPhase(launchArgumentValue: phaseValue) ?? .quiz
    }

    private static func launchArgumentValue(for key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "-\(key)") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

// MARK: - Onboarding Phase

private enum OnboardingPhase: CaseIterable {
    case quiz
    case results
    case howAppHelps
    case socialProof
    case yourPlan
    case firstLog
    case permissions
    case rating
    case allSet

    init?(launchArgumentValue: String) {
        switch launchArgumentValue {
        case "quiz":
            self = .quiz
        case "results":
            self = .results
        case "how_app_helps":
            self = .howAppHelps
        case "social_proof":
            self = .socialProof
        case "your_plan":
            self = .yourPlan
        case "guided_action":
            self = .firstLog
        case "permissions":
            self = .permissions
        case "rating":
            self = .rating
        case "completion":
            self = .allSet
        default:
            return nil
        }
    }
}

#Preview {
    OnboardingContainerView(onComplete: {})
        .environment(AppState())
        .modelContainer(for: [CycleEntry.self, Cycle.self, SymptomEntry.self], inMemory: true)
}
