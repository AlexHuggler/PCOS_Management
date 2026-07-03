import Foundation
import SwiftData

@Model
final class DailyLog {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<DailyLog>([\.date])
    #endif

    var id: UUID = UUID()
    var date: Date = Date()
    var weight: Double?
    var sleepHours: Double?
    var activeMinutes: Int?
    var restingHeartRateBPM: Double?
    var stressLevel: Int?
    var energyLevel: Int?
    var waterOz: Int?
    var painLevel0To10: Int?
    var privateNote: String?
    var positiveActionRawValues: String = ""

    init(
        id: UUID = UUID(),
        date: Date,
        weight: Double? = nil,
        sleepHours: Double? = nil,
        activeMinutes: Int? = nil,
        restingHeartRateBPM: Double? = nil,
        stressLevel: Int? = nil,
        energyLevel: Int? = nil,
        waterOz: Int? = nil,
        painLevel0To10: Int? = nil,
        privateNote: String? = nil,
        positiveActionRawValues: String = ""
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.sleepHours = sleepHours
        self.activeMinutes = activeMinutes
        self.restingHeartRateBPM = restingHeartRateBPM
        self.stressLevel = stressLevel
        self.energyLevel = energyLevel
        self.waterOz = waterOz
        self.painLevel0To10 = painLevel0To10
        self.privateNote = privateNote
        self.positiveActionRawValues = positiveActionRawValues
    }
}

extension DailyLog {
    var positiveActions: Set<PositiveActionType> {
        get {
            Set(
                positiveActionRawValues
                    .split(separator: "|")
                    .compactMap { PositiveActionType(rawValue: String($0)) }
            )
        }
        set {
            let orderedRawValues = PositiveActionType.allCases
                .filter { newValue.contains($0) }
                .map(\.rawValue)
            positiveActionRawValues = orderedRawValues.joined(separator: "|")
        }
    }

    var sortedPositiveActions: [PositiveActionType] {
        PositiveActionType.allCases.filter { positiveActions.contains($0) }
    }

    var hasHealthContext: Bool {
        weight != nil
            || sleepHours != nil
            || activeMinutes != nil
            || restingHeartRateBPM != nil
    }

    func hasPositiveAction(_ action: PositiveActionType) -> Bool {
        positiveActions.contains(action)
    }

    func setPositiveAction(_ action: PositiveActionType, isCompleted: Bool) {
        var actions = positiveActions
        if isCompleted {
            actions.insert(action)
        } else {
            actions.remove(action)
        }
        positiveActions = actions
    }
}

@MainActor
struct DailyLogService {
    enum ValidationError: Error, Equatable {
        case invalidPainLevel
        case invalidStressLevel
        case invalidWaterOz
    }

    private let modelContext: ModelContext
    private let calendar = Calendar.current

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchLog(on date: Date = Date()) throws -> DailyLog? {
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { log in
                log.date >= startOfDay && log.date < endOfDay
            }
        )
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func upsertLog(on date: Date = Date()) throws -> DailyLog {
        if let existing = try fetchLog(on: date) {
            return existing
        }

        let log = DailyLog(date: calendar.startOfDay(for: date))
        modelContext.insert(log)
        try modelContext.save()
        return log
    }

    @discardableResult
    func setPositiveAction(
        _ action: PositiveActionType,
        isCompleted: Bool,
        date: Date = Date()
    ) throws -> DailyLog {
        let log = try upsertLog(on: date)
        log.setPositiveAction(action, isCompleted: isCompleted)
        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
        return log
    }

    @discardableResult
    func togglePositiveAction(_ action: PositiveActionType, date: Date = Date()) throws -> DailyLog {
        let log = try upsertLog(on: date)
        log.setPositiveAction(action, isCompleted: !log.hasPositiveAction(action))
        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
        return log
    }

    @discardableResult
    func saveDailyCheckIn(
        date: Date = Date(),
        painLevel0To10: Int?,
        privateNote: String?,
        stressLevel: Int? = nil,
        waterOz: Int? = nil
    ) throws -> DailyLog {
        if let painLevel0To10, !(0...10).contains(painLevel0To10) {
            throw ValidationError.invalidPainLevel
        }
        if let stressLevel, !(1...5).contains(stressLevel) {
            throw ValidationError.invalidStressLevel
        }
        if let waterOz, waterOz < 0 {
            throw ValidationError.invalidWaterOz
        }

        let log = try upsertLog(on: date)
        log.painLevel0To10 = painLevel0To10
        if let stressLevel {
            log.stressLevel = stressLevel
        }
        if let waterOz {
            log.waterOz = waterOz
        }

        let trimmedNote = privateNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        log.privateNote = trimmedNote?.isEmpty == true ? nil : trimmedNote

        try modelContext.save()
        InsightRefreshCoordinator.invalidate()
        return log
    }
}

struct PositiveActionRecommendation: Identifiable, Equatable {
    let action: PositiveActionType
    let reason: String
    let score: Int

    var id: String { action.rawValue }
}

enum PositiveActionRecommendationEngine {
    static func rankedRecommendations(
        cycleDay: Int?,
        symptoms: [SymptomEntry],
        completedActions: Set<PositiveActionType>
    ) -> [PositiveActionRecommendation] {
        let topSymptom = symptoms.reduce(nil as SymptomEntry?) { current, symptom in
            guard let current else { return symptom }
            return symptom.severity > current.severity ? symptom : current
        }
        let completed = completedActions
        let scores = scores(cycleDay: cycleDay, topSymptom: topSymptom)

        return PositiveActionType.allCases
            .filter { !completed.contains($0) }
            .map { action in
                PositiveActionRecommendation(
                    action: action,
                    reason: reason(for: action, cycleDay: cycleDay, topSymptom: topSymptom),
                    score: scores[action, default: 0]
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return actionOrder(lhs.action) < actionOrder(rhs.action)
                }
                return lhs.score > rhs.score
            }
    }

    private static func scores(
        cycleDay: Int?,
        topSymptom: SymptomEntry?
    ) -> [PositiveActionType: Int] {
        var scores = Dictionary(uniqueKeysWithValues: PositiveActionType.allCases.map { ($0, 1) })

        if let cycleDay {
            switch cycleDay {
            case ...7:
                scores[.stressReduction, default: 0] += 4
                scores[.goodSleep, default: 0] += 3
                scores[.pcosFriendlyMeal, default: 0] += 2
            case 8...15:
                scores[.walkMovement, default: 0] += 4
                scores[.highProteinMeal, default: 0] += 2
                scores[.cycleSupportiveSigns, default: 0] += 2
            default:
                scores[.highProteinMeal, default: 0] += 4
                scores[.pcosFriendlyMeal, default: 0] += 3
                scores[.lowerCarbMeal, default: 0] += 2
                scores[.goodSleep, default: 0] += 2
            }
        }

        guard let topSymptom else {
            return scores
        }

        switch topSymptom.symptomType.category {
        case .pain:
            scores[.stressReduction, default: 0] += 6
            scores[.goodSleep, default: 0] += 4
            scores[.walkMovement, default: 0] += 1
        case .mood:
            scores[.stressReduction, default: 0] += 6
            scores[.goodSleep, default: 0] += 2
        case .physical:
            scores[.goodSleep, default: 0] += 4
            scores[.stressReduction, default: 0] += 2
            scores[.pcosFriendlyMeal, default: 0] += 1
        case .digestive:
            scores[.pcosFriendlyMeal, default: 0] += 4
            scores[.stressReduction, default: 0] += 2
        case .metabolic:
            scores[.highProteinMeal, default: 0] += 5
            scores[.lowerCarbMeal, default: 0] += 5
            scores[.pcosFriendlyMeal, default: 0] += 3
            scores[.walkMovement, default: 0] += 2
        case .hair, .skin:
            scores[.goodSleep, default: 0] += 3
            scores[.supplementsTaken, default: 0] += 2
            scores[.stressReduction, default: 0] += 2
        }

        return scores
    }

    private static func reason(
        for action: PositiveActionType,
        cycleDay: Int?,
        topSymptom: SymptomEntry?
    ) -> String {
        if let topSymptom, topSymptom.severity >= 3 {
            return L10n.format(
                "Recommended because %@ is elevated today.",
                defaultValue: "Recommended because %@ is elevated today.",
                topSymptom.symptomType.displayName.lowercased()
            )
        }

        if let cycleDay {
            if cycleDay <= 7 {
                return L10n.string(
                    "A gentler support for early-cycle recovery.",
                    defaultValue: "A gentler support for early-cycle recovery."
                )
            } else if cycleDay <= 15 {
                return L10n.string(
                    "A light support for a steadier mid-cycle day.",
                    defaultValue: "A light support for a steadier mid-cycle day."
                )
            }

            return L10n.string(
                "A steadying support for the later part of your cycle.",
                defaultValue: "A steadying support for the later part of your cycle."
            )
        }

        return L10n.string(
            "A quick supportive action you can complete today.",
            defaultValue: "A quick supportive action you can complete today."
        )
    }

    private static func actionOrder(_ action: PositiveActionType) -> Int {
        PositiveActionType.allCases.firstIndex(of: action) ?? Int.max
    }
}
