import SwiftUI

// MARK: - Onboarding Enums

enum PrimaryGoal: String, CaseIterable, Identifiable {
    case trackCycles
    case understandSymptoms

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trackCycles: "Track my periods"
        case .understandSymptoms: "Understand my symptoms"
        }
    }

    var subtitle: String {
        switch self {
        case .trackCycles: "Irregular cycles are unpredictable. Let's change that."
        case .understandSymptoms: "Find patterns between your symptoms and your cycle."
        }
    }

    var systemImage: String {
        switch self {
        case .trackCycles: "calendar.badge.clock"
        case .understandSymptoms: "chart.xyaxis.line"
        }
    }
}

enum PCOSExperience: String, CaseIterable, Identifiable {
    case newlyDiagnosed
    case experienced
    case exploring

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newlyDiagnosed: "I was recently diagnosed"
        case .experienced: "I've been managing for a while"
        case .exploring: "I think I might have PCOS"
        }
    }

    var subtitle: String {
        switch self {
        case .newlyDiagnosed: "We'll help you get started step by step."
        case .experienced: "Let's make your tracking more powerful."
        case .exploring: "Tracking symptoms can help you and your doctor."
        }
    }

    var systemImage: String {
        switch self {
        case .newlyDiagnosed: "sparkles"
        case .experienced: "chart.line.uptrend.xyaxis"
        case .exploring: "magnifyingglass"
        }
    }
}

enum SymptomFocusArea: String, CaseIterable, Identifiable {
    case moodEnergy
    case painCramps
    case skinHair
    case digestionWeight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moodEnergy: "Mood & energy"
        case .painCramps: "Pain & cramps"
        case .skinHair: "Skin & hair"
        case .digestionWeight: "Digestion & weight"
        }
    }

    var subtitle: String {
        switch self {
        case .moodEnergy: "Track mood swings, anxiety, and energy crashes."
        case .painCramps: "See how cramps and pain relate to your cycle."
        case .skinHair: "Monitor acne, hair changes, and skin patterns."
        case .digestionWeight: "Spot trends in bloating, cravings, and weight."
        }
    }

    var systemImage: String {
        switch self {
        case .moodEnergy: "brain.head.profile"
        case .painCramps: "bolt.heart"
        case .skinHair: "comb.fill"
        case .digestionWeight: "fork.knife"
        }
    }

    var relatedCategories: [SymptomCategory] {
        switch self {
        case .moodEnergy: [.mood, .metabolic]
        case .painCramps: [.pain, .physical]
        case .skinHair: [.skin, .hair]
        case .digestionWeight: [.digestive, .metabolic]
        }
    }
}

enum SuggestedFirstAction: Sendable {
    case logPeriod
    case logSymptoms
}

enum HintVerbosity: Sendable {
    case educational
    case brief
}

// MARK: - Onboarding Profile

@Observable
@MainActor
final class OnboardingProfile {

    // MARK: - Hint IDs

    static let hintQuickLogIntro = "hint.quick_log_intro"
    static let hintCalendarTab = "hint.calendar_tab"
    static let hintLogSymptoms = "hint.log_symptoms"
    static let hintFirstPrediction = "hint.first_prediction"

    // MARK: - Keys

    private enum Keys {
        static let hasCompletedWelcome = "onboarding.hasCompletedWelcome"
        static let hasCompletedQuestionnaire = "onboarding.hasCompletedQuestionnaire"
        static let hasCompletedGuidedAction = "onboarding.hasCompletedGuidedAction"
        static let hasCompletedOnboarding = "onboarding.hasCompletedOnboarding"
        static let primaryGoal = "onboarding.primaryGoal"
        static let pcosExperience = "onboarding.pcosExperience"
        static let symptomFocusAreas = "onboarding.symptomFocusAreas"
        static let dismissedHints = "onboarding.dismissedHints"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Completion Flags

    var hasCompletedWelcome: Bool {
        get {
            access(keyPath: \.hasCompletedWelcome)
            return defaults.bool(forKey: Keys.hasCompletedWelcome)
        }
        set {
            withMutation(keyPath: \.hasCompletedWelcome) {
                defaults.set(newValue, forKey: Keys.hasCompletedWelcome)
            }
        }
    }

    var hasCompletedQuestionnaire: Bool {
        get {
            access(keyPath: \.hasCompletedQuestionnaire)
            return defaults.bool(forKey: Keys.hasCompletedQuestionnaire)
        }
        set {
            withMutation(keyPath: \.hasCompletedQuestionnaire) {
                defaults.set(newValue, forKey: Keys.hasCompletedQuestionnaire)
            }
        }
    }

    var hasCompletedGuidedAction: Bool {
        get {
            access(keyPath: \.hasCompletedGuidedAction)
            return defaults.bool(forKey: Keys.hasCompletedGuidedAction)
        }
        set {
            withMutation(keyPath: \.hasCompletedGuidedAction) {
                defaults.set(newValue, forKey: Keys.hasCompletedGuidedAction)
            }
        }
    }

    // MARK: - Questionnaire Answers

    var primaryGoal: PrimaryGoal? {
        get {
            access(keyPath: \.primaryGoal)
            return defaults.string(forKey: Keys.primaryGoal).flatMap(PrimaryGoal.init(rawValue:))
        }
        set {
            withMutation(keyPath: \.primaryGoal) {
                defaults.set(newValue?.rawValue, forKey: Keys.primaryGoal)
            }
        }
    }

    var pcosExperience: PCOSExperience? {
        get {
            access(keyPath: \.pcosExperience)
            return defaults.string(forKey: Keys.pcosExperience).flatMap(PCOSExperience.init(rawValue:))
        }
        set {
            withMutation(keyPath: \.pcosExperience) {
                defaults.set(newValue?.rawValue, forKey: Keys.pcosExperience)
            }
        }
    }

    var symptomFocusAreas: [SymptomFocusArea] {
        get {
            access(keyPath: \.symptomFocusAreas)
            guard let rawValues = defaults.stringArray(forKey: Keys.symptomFocusAreas) else {
                return []
            }
            return rawValues.compactMap(SymptomFocusArea.init(rawValue:))
        }
        set {
            withMutation(keyPath: \.symptomFocusAreas) {
                defaults.set(newValue.map(\.rawValue), forKey: Keys.symptomFocusAreas)
            }
        }
    }

    // MARK: - Derived State

    var preferredSymptomCategories: [SymptomCategory] {
        symptomFocusAreas.flatMap(\.relatedCategories)
    }

    var suggestedFirstAction: SuggestedFirstAction {
        switch primaryGoal {
        case .understandSymptoms: .logSymptoms
        default: .logPeriod
        }
    }

    var hintVerbosity: HintVerbosity {
        switch pcosExperience {
        case .experienced: .brief
        default: .educational
        }
    }

    var quickLogHintMessage: String {
        switch primaryGoal {
        case .trackCycles:
            "Tap Light, Medium, or Heavy to log today's flow in one tap."
        case .understandSymptoms:
            "You can quickly log your period here — even if that's not your main focus."
        case nil:
            "Tap Light, Medium, or Heavy to log today's flow in one tap."
        }
    }

    var calendarHintMessage: String {
        switch pcosExperience {
        case .experienced:
            "Your Calendar is in the second tab."
        default:
            "Check the Calendar tab to see your cycle at a glance."
        }
    }

    var symptomHintMessage: String {
        if let firstFocus = symptomFocusAreas.first {
            switch firstFocus {
            case .moodEnergy:
                "Log how you're feeling each day — patterns emerge within a cycle or two."
            case .painCramps:
                "Tracking pain alongside your cycle helps spot which days hit hardest."
            case .skinHair:
                "Start logging skin or hair changes to track patterns over time."
            case .digestionWeight:
                "Log digestive symptoms daily to surface connections with your cycle."
            }
        } else {
            "Logging symptoms daily helps surface patterns with your cycle."
        }
    }

    // MARK: - Hint Management

    func shouldShowHint(_ hintID: String) -> Bool {
        let dismissed = defaults.stringArray(forKey: Keys.dismissedHints) ?? []
        return !dismissed.contains(hintID)
    }

    func dismissHint(_ hintID: String) {
        var dismissed = defaults.stringArray(forKey: Keys.dismissedHints) ?? []
        guard !dismissed.contains(hintID) else { return }
        dismissed.append(hintID)
        defaults.set(dismissed, forKey: Keys.dismissedHints)
    }

    // MARK: - Reset

    func resetOnboarding() {
        let keysToRemove = [
            Keys.hasCompletedWelcome,
            Keys.hasCompletedQuestionnaire,
            Keys.hasCompletedGuidedAction,
            Keys.hasCompletedOnboarding,
            Keys.primaryGoal,
            Keys.pcosExperience,
            Keys.symptomFocusAreas,
            Keys.dismissedHints,
        ]
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
    }
}
