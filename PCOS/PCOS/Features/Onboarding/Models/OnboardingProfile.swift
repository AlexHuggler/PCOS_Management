import SwiftUI

// MARK: - Onboarding Enums

enum PrimaryGoal: String, CaseIterable, Identifiable {
    case trackCycles
    case understandSymptoms

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trackCycles:
            String(localized: "Track my periods", comment: "Primary onboarding goal title.")
        case .understandSymptoms:
            String(localized: "Understand my symptoms", comment: "Primary onboarding goal title.")
        }
    }

    var subtitle: String {
        switch self {
        case .trackCycles:
            String(localized: "Irregular cycles are unpredictable. Let's change that.", comment: "Primary onboarding goal description.")
        case .understandSymptoms:
            String(localized: "Find patterns between your symptoms and your cycle.", comment: "Primary onboarding goal description.")
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
        case .newlyDiagnosed:
            String(localized: "I was recently diagnosed", comment: "PCOS experience option in onboarding.")
        case .experienced:
            String(localized: "I've been managing for a while", comment: "PCOS experience option in onboarding.")
        case .exploring:
            String(localized: "I think I might have PCOS", comment: "PCOS experience option in onboarding.")
        }
    }

    var subtitle: String {
        switch self {
        case .newlyDiagnosed:
            String(localized: "We'll help you get started step by step.", comment: "PCOS experience description in onboarding.")
        case .experienced:
            String(localized: "Let's make your tracking more powerful.", comment: "PCOS experience description in onboarding.")
        case .exploring:
            String(localized: "Tracking symptoms can help you and your doctor.", comment: "PCOS experience description in onboarding.")
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
        case .moodEnergy:
            String(localized: "Mood & energy", comment: "Symptom focus area title in onboarding.")
        case .painCramps:
            String(localized: "Pain & cramps", comment: "Symptom focus area title in onboarding.")
        case .skinHair:
            String(localized: "Skin & hair", comment: "Symptom focus area title in onboarding.")
        case .digestionWeight:
            String(localized: "Digestion & weight", comment: "Symptom focus area title in onboarding.")
        }
    }

    var subtitle: String {
        switch self {
        case .moodEnergy:
            String(localized: "Track mood swings, anxiety, and energy crashes.", comment: "Symptom focus area description in onboarding.")
        case .painCramps:
            String(localized: "See how cramps and pain relate to your cycle.", comment: "Symptom focus area description in onboarding.")
        case .skinHair:
            String(localized: "Monitor acne, hair changes, and skin patterns.", comment: "Symptom focus area description in onboarding.")
        case .digestionWeight:
            String(localized: "Spot trends in bloating, cravings, and weight.", comment: "Symptom focus area description in onboarding.")
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
        case .painCramps: [.pain, .digestive, .physical]
        case .skinHair: [.skin, .hair]
        case .digestionWeight: [.digestive, .metabolic]
        }
    }
}

enum SuggestedFirstAction: Sendable {
    case logPeriod
    case logSymptoms

    var guidedActionSkipTitle: String {
        String(
            localized: "Continue without first log",
            comment: "Secondary guided action button label."
        )
    }

    var guidedActionSkipHint: String {
        String(
            localized: "Continue setup without logging your first entry right now.",
            comment: "Accessibility hint for the guided action skip button."
        )
    }
}

enum HintVerbosity: Sendable {
    case educational
    case brief
}

struct FeaturePreview: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let caption: String
    let personalizedSubtitle: String?
}

struct PlanItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let subtitle: String
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
        static let hasPromptedForReview = "onboarding.hasPromptedForReview"
        static let dismissedHints = "onboarding.dismissedHints"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

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

    var hasPromptedForReview: Bool {
        get {
            access(keyPath: \.hasPromptedForReview)
            return defaults.bool(forKey: Keys.hasPromptedForReview)
        }
        set {
            withMutation(keyPath: \.hasPromptedForReview) {
                defaults.set(newValue, forKey: Keys.hasPromptedForReview)
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
            String(localized: "Tap Light, Medium, or Heavy to log today's flow in one tap.", comment: "Onboarding tooltip introducing the quick period logging buttons.")
        case .understandSymptoms:
            String(localized: "You can quickly log your period here — even if that's not your main focus.", comment: "Onboarding tooltip introducing quick period logging for users focused on symptoms.")
        case nil:
            String(localized: "Tap Light, Medium, or Heavy to log today's flow in one tap.", comment: "Onboarding tooltip introducing the quick period logging buttons.")
        }
    }

    var calendarHintMessage: String {
        switch pcosExperience {
        case .experienced:
            String(localized: "Your Calendar is in the second tab.", comment: "Onboarding tooltip pointing users to the Calendar tab.")
        default:
            String(localized: "Check the Calendar tab to see your cycle at a glance.", comment: "Onboarding tooltip pointing users to the Calendar tab.")
        }
    }

    var symptomHintMessage: String {
        if let firstFocus = symptomFocusAreas.first {
            switch firstFocus {
            case .moodEnergy:
                String(localized: "Log how you're feeling each day — patterns emerge within a cycle or two.", comment: "Onboarding tooltip encouraging daily symptom logging for mood and energy.")
            case .painCramps:
                String(localized: "Tracking pain alongside your cycle helps spot which days hit hardest.", comment: "Onboarding tooltip encouraging daily symptom logging for pain and cramps.")
            case .skinHair:
                String(localized: "Start logging skin or hair changes to track patterns over time.", comment: "Onboarding tooltip encouraging daily symptom logging for skin and hair.")
            case .digestionWeight:
                String(localized: "Log digestive symptoms daily to surface connections with your cycle.", comment: "Onboarding tooltip encouraging daily symptom logging for digestion and weight.")
            }
        } else {
            String(localized: "Logging symptoms daily helps surface patterns with your cycle.", comment: "Onboarding tooltip encouraging daily symptom logging.")
        }
    }

    var resultsHeadline: String {
        switch primaryGoal {
        case .trackCycles:
            String(localized: "CycleBalance will help you find your rhythm", comment: "Personalized results headline for cycle tracking goal.")
        case .understandSymptoms:
            String(localized: "CycleBalance will help you decode your symptoms", comment: "Personalized results headline for symptom understanding goal.")
        case nil:
            String(localized: "CycleBalance is ready to help", comment: "Generic results headline when no goal selected.")
        }
    }

    var resultsSubheadline: String {
        switch pcosExperience {
        case .newlyDiagnosed:
            String(localized: "Starting fresh is the hardest part — we'll guide you step by step.", comment: "Results subheadline for newly diagnosed users.")
        case .experienced:
            String(localized: "You already know your body. Let's make your data work harder.", comment: "Results subheadline for experienced users.")
        case .exploring:
            String(localized: "Tracking is a powerful first step toward answers.", comment: "Results subheadline for users exploring a PCOS diagnosis.")
        case nil:
            String(localized: "Your personalized tracking starts now.", comment: "Generic results subheadline.")
        }
    }

    var resultsStat: String {
        switch pcosExperience {
        case .newlyDiagnosed:
            String(localized: "68% of recently diagnosed users say tracking helped them feel more in control within 30 days.", comment: "Reassuring stat for newly diagnosed users on the results screen.")
        case .experienced:
            String(localized: "Women who track consistently report 40% better conversations with their doctors.", comment: "Reassuring stat for experienced users on the results screen.")
        case .exploring:
            String(localized: "3 in 4 women exploring PCOS say symptom tracking gave them clarity before their next appointment.", comment: "Reassuring stat for exploring users on the results screen.")
        case nil:
            String(localized: "Join 10,000+ women tracking their PCOS journey with CycleBalance.", comment: "Generic community stat on the results screen.")
        }
    }

    private var focusAreaSubtitle: String? {
        guard let firstFocus = symptomFocusAreas.first else { return nil }
        switch firstFocus {
        case .moodEnergy:
            return String(localized: "Perfect for spotting patterns in your mood and energy levels.", comment: "Personalized feature subtitle for mood and energy focus.")
        case .painCramps:
            return String(localized: "Ideal for tracking how pain and cramps relate to your cycle.", comment: "Personalized feature subtitle for pain and cramps focus.")
        case .skinHair:
            return String(localized: "Great for tracking how your skin and hair change across your cycle.", comment: "Personalized feature subtitle for skin and hair focus.")
        case .digestionWeight:
            return String(localized: "Perfect for spotting trends in your bloating and cravings.", comment: "Personalized feature subtitle for digestion and weight focus.")
        }
    }

    var featurePreviews: [FeaturePreview] {
        switch primaryGoal {
        case .trackCycles:
            [
                FeaturePreview(
                    systemImage: "calendar.badge.clock",
                    title: String(localized: "Smart Cycle Calendar", comment: "Feature preview title for cycle calendar."),
                    caption: String(localized: "See your cycle at a glance. CycleBalance learns your pattern — even when it's irregular.", comment: "Feature preview caption for cycle calendar."),
                    personalizedSubtitle: focusAreaSubtitle
                ),
                FeaturePreview(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: String(localized: "Predictions That Adapt", comment: "Feature preview title for cycle predictions."),
                    caption: String(localized: "Our predictions improve with every log. No 28-day assumptions.", comment: "Feature preview caption for cycle predictions."),
                    personalizedSubtitle: nil
                ),
            ]
        case .understandSymptoms:
            [
                FeaturePreview(
                    systemImage: "list.bullet.clipboard",
                    title: String(localized: "Daily Symptom Tracking", comment: "Feature preview title for symptom tracking."),
                    caption: String(localized: "Log symptoms in seconds. We'll find the patterns you can't see.", comment: "Feature preview caption for symptom tracking."),
                    personalizedSubtitle: focusAreaSubtitle
                ),
                FeaturePreview(
                    systemImage: "chart.xyaxis.line",
                    title: String(localized: "Cycle–Symptom Insights", comment: "Feature preview title for symptom insights."),
                    caption: String(localized: "Discover how your symptoms relate to your cycle phase.", comment: "Feature preview caption for symptom insights."),
                    personalizedSubtitle: nil
                ),
            ]
        case nil:
            [
                FeaturePreview(
                    systemImage: "sparkles",
                    title: String(localized: "Your Personal Health Hub", comment: "Generic feature preview title."),
                    caption: String(localized: "Track periods, symptoms, and more — all in one private place.", comment: "Generic feature preview caption."),
                    personalizedSubtitle: focusAreaSubtitle
                ),
            ]
        }
    }

    var planItems: [PlanItem] {
        var items: [PlanItem] = []
        switch primaryGoal {
        case .trackCycles:
            items.append(PlanItem(
                systemImage: "calendar",
                title: String(localized: "Cycle calendar", comment: "Plan item title for cycle calendar."),
                subtitle: String(localized: "See your cycle history at a glance", comment: "Plan item subtitle for cycle calendar.")
            ))
            items.append(PlanItem(
                systemImage: "wand.and.stars",
                title: String(localized: "Period predictions", comment: "Plan item title for period predictions."),
                subtitle: String(localized: "Smarter forecasts after each cycle", comment: "Plan item subtitle for period predictions.")
            ))
        case .understandSymptoms:
            items.append(PlanItem(
                systemImage: "list.bullet.clipboard",
                title: String(localized: "Symptom dashboard", comment: "Plan item title for symptom dashboard."),
                subtitle: String(localized: "All your symptoms organized in one place", comment: "Plan item subtitle for symptom dashboard.")
            ))
            items.append(PlanItem(
                systemImage: "lightbulb.fill",
                title: String(localized: "Pattern insights", comment: "Plan item title for pattern insights."),
                subtitle: String(localized: "Connections you can't spot on your own", comment: "Plan item subtitle for pattern insights.")
            ))
        case nil:
            items.append(PlanItem(
                systemImage: "sparkles",
                title: String(localized: "Personalized tracking", comment: "Generic plan item title."),
                subtitle: String(localized: "A dashboard built around your needs", comment: "Generic plan item subtitle.")
            ))
        }
        if let firstFocus = symptomFocusAreas.first {
            items.append(PlanItem(
                systemImage: firstFocus.systemImage,
                title: firstFocus.displayName,
                subtitle: String(localized: "Highlighted on your dashboard", comment: "Plan item subtitle for a user's selected symptom focus area.")
            ))
        }
        return items
    }

    var firstLogContextLine: String {
        switch primaryGoal {
        case .trackCycles:
            String(localized: "Your plan is set — let's get your first data point.", comment: "Contextual line shown above the first log screen for cycle tracking users.")
        case .understandSymptoms:
            String(localized: "Your insights start with today's first log.", comment: "Contextual line shown above the first log screen for symptom-focused users.")
        case nil:
            String(localized: "Let's capture your first entry.", comment: "Generic contextual line for the first log screen.")
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
            Keys.hasPromptedForReview,
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
