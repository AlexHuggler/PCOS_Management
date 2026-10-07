import Foundation

// MARK: - Steps (A2–A7)

/// The six onboarding steps of the v1 journey. Progress persists as `journey_<rawValue>` under
/// `onboarding.currentPhaseRaw` so an interrupted flow resumes where it stopped.
enum CompanionOnboardingStage: Int, CaseIterable, Sendable {
    case welcome, stage, focus, checkIn, unlocks, health

    static let phasePrefix = "journey_"

    /// Figma step IDs, used as analytics `step_id` so dashboards line up with the blueprint.
    var stepID: String {
        switch self {
        case .welcome: "A2_welcome"
        case .stage: "A3_stage"
        case .focus: "A4_focus"
        case .checkIn: "A5_first_checkin"
        case .unlocks: "A6_reminder"
        case .health: "A7_health"
        }
    }

    var persistedPhase: String { "\(Self.phasePrefix)\(rawValue)" }

    var next: Self? { Self(rawValue: rawValue + 1) }
    var previous: Self? { Self(rawValue: rawValue - 1) }

    /// Steps after the welcome show a five-segment progress bar (A3–A7).
    var progressIndex: Int? { self == .welcome ? nil : rawValue }
    static let progressSegments = 5

    static func resume(defaults: UserDefaults = .standard, arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        var raw = defaults.string(forKey: "onboarding.currentPhaseRaw")
        if arguments.contains("UITestMode"), let index = arguments.firstIndex(of: "-onboarding.startPhase"), index + 1 < arguments.count {
            raw = arguments[index + 1]
        }
        guard let raw else { return .welcome }
        if raw.hasPrefix(phasePrefix), let number = Int(raw.dropFirst(phasePrefix.count)), let stage = Self(rawValue: number) {
            return stage
        }
        // The unshipped four-step companion flow (welcome, preferences, health, check-in).
        if raw.hasPrefix("companion_"), let number = Int(raw.dropFirst("companion_".count)) {
            switch number {
            case 0: return .welcome
            case 1: return .stage
            default: return .checkIn
            }
        }
        // The shipped 13-step flow.
        switch raw {
        case "theme", "name", "personalize", "quiz", "results", "how_app_helps": return .stage
        case "permissions", "health_context", "aha": return .health
        case "meal_scan_demo", "your_plan", "first_log", "guided_action", "social_proof", "all_set", "completion": return .checkIn
        default: return .welcome
        }
    }
}

// MARK: - A4 focus topics

/// "What would you like to understand?" chips. Stored separately from `SymptomFocusArea`, which
/// older insight hints and backups use; the overlapping topics are mirrored into it.
enum OnboardingFocusTopic: String, CaseIterable, Identifiable, Sendable {
    case irregularPeriods
    case moodEnergy
    case painCramps
    case skinHair
    case cravingsDigestion
    case sleep
    case bloodSugar

    var id: String { rawValue }

    static let defaultsKey = "onboarding.focusTopics.v1"

    var title: String {
        switch self {
        case .irregularPeriods: L10n.string("Irregular periods", defaultValue: "Irregular periods")
        case .moodEnergy: L10n.string("Mood & energy", defaultValue: "Mood & energy")
        case .painCramps: L10n.string("Pain & cramps", defaultValue: "Pain & cramps")
        case .skinHair: L10n.string("Skin & hair", defaultValue: "Skin & hair")
        case .cravingsDigestion: L10n.string("Cravings & digestion", defaultValue: "Cravings & digestion")
        case .sleep: L10n.string("Sleep", defaultValue: "Sleep")
        case .bloodSugar: L10n.string("Blood sugar", defaultValue: "Blood sugar")
        }
    }

    var symptomFocusArea: SymptomFocusArea? {
        switch self {
        case .moodEnergy: .moodEnergy
        case .painCramps: .painCramps
        case .skinHair: .skinHair
        case .cravingsDigestion: .digestionWeight
        case .irregularPeriods, .sleep, .bloodSugar: nil
        }
    }

    /// Symptoms pinned to the daily check-in for this topic.
    var pinnedSymptoms: [SymptomType] {
        switch self {
        case .irregularPeriods: []
        case .moodEnergy: [.fatigue, .moodSwings]
        case .painCramps: [.cramps, .pelvicPain]
        case .skinHair: [.acne, .shedding]
        case .cravingsDigestion: [.bloating, .cravings]
        case .sleep: []
        case .bloodSugar: [.energyCrash]
        }
    }

    static func stored(defaults: UserDefaults = .standard) -> [Self] {
        (defaults.stringArray(forKey: defaultsKey) ?? []).compactMap(Self.init(rawValue:))
    }

    static func store(_ topics: [Self], defaults: UserDefaults = .standard) {
        defaults.set(topics.map(\.rawValue), forKey: defaultsKey)
    }
}

// MARK: - Applying A3/A4 answers

/// Turns onboarding answers into the settings that shape Today and the check-in. Pure, so the
/// mapping is unit-tested; `apply` writes it to the shared preference stores.
struct OnboardingPersonalizationPlan: Equatable, Sendable {
    static let maxPinnedSymptoms = 4
    /// Shown when nothing was chosen (matches the Figma first check-in).
    static let defaultPinnedSymptoms: [SymptomType] = [.fatigue, .acne, .bloating]

    var pinnedSymptoms: [SymptomType]
    var favoriteActions: [LoggerShortcut]
    var visibleCards: [TodayCard]
    var healthCategories: [HealthKitDataTypeDescriptor.Category]
    var informationDetail: InformationDetail

    static func make(topics: [OnboardingFocusTopic], experience: PCOSExperience?) -> Self {
        var seen = Set<SymptomType>()
        var pinned = topics.flatMap(\.pinnedSymptoms).filter { seen.insert($0).inserted }
        if pinned.isEmpty { pinned = defaultPinnedSymptoms }
        pinned = Array(pinned.prefix(maxPinnedSymptoms))

        // Free actions only; Premium is offered later and in context, never as a day-1 shortcut.
        let favorites: [LoggerShortcut] = topics.contains(.irregularPeriods) || topics.isEmpty
            ? [.period, .symptoms]
            : [.symptoms, .period]

        var cards: [TodayCard] = [.cycle, .health, .observation, .symptoms]
        let wantsHealthContext = topics.contains(.sleep) || topics.contains(.bloodSugar)
        if !topics.isEmpty && !wantsHealthContext {
            cards.removeAll { $0 == .health }
            cards.append(.health)
        }
        if !topics.isEmpty && !topics.contains(.irregularPeriods) {
            cards.removeAll { $0 == .cycle }
            cards.append(.cycle)
        }

        var health: [HealthKitDataTypeDescriptor.Category] = [.sleep, .activity, .cycle, .symptoms]
        if topics.contains(.bloodSugar) { health.append(.glucose) }

        let detail: InformationDetail = experience == .experienced ? .detailed : .simple

        return Self(
            pinnedSymptoms: pinned,
            favoriteActions: favorites,
            visibleCards: cards,
            healthCategories: health,
            informationDetail: detail
        )
    }

    @MainActor
    func apply(to tracking: TrackingPreferences, profile: OnboardingProfile, topics: [OnboardingFocusTopic]) {
        tracking.pinnedSymptomRawValues = pinnedSymptoms.map(\.rawValue)
        tracking.favoriteActions = favoriteActions
        tracking.visibleCards = visibleCards
        tracking.informationDetail = informationDetail
        profile.symptomFocusAreas = topics.compactMap(\.symptomFocusArea)
    }
}

// MARK: - Analytics helpers

/// Onboarding timing for `onboarding_completed {duration_s}`.
enum OnboardingTiming {
    static let startedAtKey = "onboarding.startedAt"

    static func markStarted(now: Date = Date(), defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: startedAtKey) == nil else { return }
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: startedAtKey)
    }

    static func durationSeconds(now: Date = Date(), defaults: UserDefaults = .standard) -> Int {
        guard let started = defaults.object(forKey: startedAtKey) as? Double else { return 0 }
        return max(0, Int(now.timeIntervalSinceReferenceDate - started))
    }
}
