import Foundation
import SwiftData

// MARK: - Tap-first check-in (A5, A8)

/// Three-step severity for the tap-first check-in, stored on the existing 1–5 scale.
enum QuickSeverity: Int, CaseIterable, Identifiable, Sendable {
    case mild = 1
    case moderate = 3
    case strong = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mild: L10n.string("Mild", defaultValue: "Mild")
        case .moderate: L10n.string("Moderate", defaultValue: "Moderate")
        case .strong: L10n.string("Strong", defaultValue: "Strong")
        }
    }

    /// The nearest step for a stored 1–5 value (2 reads as Mild, 4 as Strong).
    init?(storedSeverity: Int) {
        switch storedSeverity {
        case 1, 2: self = .mild
        case 3: self = .moderate
        case 4, 5: self = .strong
        default: return nil
        }
    }
}

extension DailyMood {
    /// Short, non-judgemental label for mood tiles. `.awful` keeps its stored raw value.
    var tileTitle: String {
        switch self {
        case .awful: L10n.string("Tough", defaultValue: "Tough")
        default: title
        }
    }
}

/// What the inline check-in collected. Every field is optional; "Nothing to report" counts.
struct QuickCheckInInput: Equatable, Sendable {
    var mood: DailyMood?
    var severities: [SymptomType: QuickSeverity] = [:]
    var nothingToReport = false

    var isEmpty: Bool { mood == nil && severities.isEmpty && !nothingToReport }

    /// Number of taps a user made, for the "under 6 taps" acceptance check.
    var tapCount: Int { (mood == nil ? 0 : 1) + severities.count + (nothingToReport ? 1 : 0) }

    mutating func toggle(_ severity: QuickSeverity, for symptom: SymptomType) {
        if severities[symptom] == severity {
            severities.removeValue(forKey: symptom)
        } else {
            severities[symptom] = severity
            nothingToReport = false
        }
    }

    mutating func toggleNothingToReport() {
        nothingToReport.toggle()
        if nothingToReport { severities = [:] }
    }

    /// Applies only what was tapped onto the day's loaded draft, so other fields are kept.
    func applying(to loaded: DailyCheckInDraft) -> DailyCheckInDraft {
        var draft = loaded
        if let mood { draft.mood = .set(mood) }
        if nothingToReport {
            draft.recordNoSymptoms()
        } else if !severities.isEmpty {
            var values = loaded.symptoms.value ?? [:]
            for (type, severity) in severities { values[type] = severity.rawValue }
            draft.symptoms = .set(values)
            draft.symptomsReviewed = true
        }
        return draft
    }
}

/// Saves the inline check-in through the same service as the full check-in sheet.
@MainActor
struct QuickCheckInService {
    let modelContext: ModelContext

    func load(on date: Date = Date()) throws -> QuickCheckInInput {
        let draft = try DailyCheckInService(modelContext: modelContext).load(on: date)
        var input = QuickCheckInInput()
        input.mood = draft.mood.value
        for (type, stored) in draft.symptoms.value ?? [:] {
            if let severity = QuickSeverity(storedSeverity: stored) { input.severities[type] = severity }
        }
        input.nothingToReport = draft.symptomsReviewed && (draft.symptoms.value ?? [:]).isEmpty
        return input
    }

    func save(_ input: QuickCheckInInput, on date: Date = Date()) throws {
        guard !input.isEmpty else { return }
        let service = DailyCheckInService(modelContext: modelContext)
        let original = try service.load(on: date)
        let edited = input.applying(to: original)
        try service.save(edited.changes(since: original))
    }
}

// MARK: - "3 of 7 toward your first pattern" (A6, A8)

enum CheckInProgress {
    static let firstPatternTarget = 7

    /// Distinct calendar days among the given dates.
    static func distinctDays(_ dates: [Date], calendar: Calendar = .current) -> Int {
        Set(dates.map { calendar.startOfDay(for: $0) }).count
    }

    /// Progress shown to the user, capped at the target.
    static func displayed(_ days: Int) -> Int { min(max(days, 0), firstPatternTarget) }

    static func fraction(_ days: Int) -> Double {
        Double(displayed(days)) / Double(firstPatternTarget)
    }

    /// Something the user recorded themselves (Apple Health imports such as water do not count).
    static func isManualCheckIn(_ log: DailyLog) -> Bool {
        log.symptomsReviewed || log.moodRawValue != nil || log.energyLevel != nil
            || log.painLevel0To10 != nil || log.stressLevel != nil
            || !(log.privateNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    @MainActor
    static func checkInDayCount(modelContext: ModelContext, calendar: Calendar = .current) -> Int {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let symptoms = (try? modelContext.fetch(FetchDescriptor<SymptomEntry>())) ?? []
        let dates = logs.filter(isManualCheckIn).map(\.date) + symptoms.map(\.date)
        return distinctDays(dates, calendar: calendar)
    }
}

// MARK: - Premium card on Today (A8, B1)

/// Premium is offered after value: from the third check-in day, never to subscribers,
/// and once dismissed it stays dismissed.
enum PremiumNudgePolicy {
    static let dismissedKey = "today.premiumCard.dismissed"
    static let minimumCheckInDays = 3

    static func shouldShow(
        checkInDays: Int,
        hasPremiumAccess: Bool,
        showsSubscriptionUI: Bool,
        dismissed: Bool
    ) -> Bool {
        checkInDays >= minimumCheckInDays && !hasPremiumAccess && showsSubscriptionUI && !dismissed
    }
}

// MARK: - Analytics (UI facts only)

@MainActor
enum CheckInAnalytics {
    /// `checkin_saved {source}` at most once a day, plus `first_checkin_saved` the first time.
    /// Only the UI location is sent — never what was recorded.
    static func recordSave(source: CheckInSource) {
        let analytics = AppAnalytics.shared
        analytics.trackOnce(.firstCheckinSaved(source: source), onceKey: "first_checkin_saved")
        analytics.trackOncePerDay(.checkinSaved(source: source), dailyKey: "checkin_saved")
    }
}
