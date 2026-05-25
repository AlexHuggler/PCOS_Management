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
}
