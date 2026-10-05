import Foundation
import SwiftData

@Model
final class HealthKitSyncCursor {
    var identifier: String = ""
    var anchor: Data?
    var windowStart: Date = Date()
    var committedAt: Date?
    init(identifier: String, windowStart: Date) {
        self.identifier = identifier
        self.windowStart = windowStart
    }
}

/// Separate ownership keeps old stores compatible. A populated field without ownership is manual.
@Model
final class HealthKitFieldOwnership {
    var recordID: UUID = UUID()
    var field: String = ""
    var lastAppliedValue: Double?
    var healthValue: Double?
    var isManual: Bool = false
    var lastAppliedFingerprint: String?
    init(recordID: UUID, field: String) { self.recordID = recordID; self.field = field }

    @MainActor
    static func markManual(log: DailyLog, fields: [String], context: ModelContext) throws {
        let owners = try context.fetch(FetchDescriptor<HealthKitFieldOwnership>())
        for field in fields {
            let owner = owners.first { $0.recordID == log.id && $0.field == field }
                ?? HealthKitFieldOwnership(recordID: log.id, field: field)
            if owner.modelContext == nil { context.insert(owner) }
            owner.isManual = true
        }
    }

    @MainActor
    static func useAppleHealth(log: DailyLog, field: String, context: ModelContext, save: (() throws -> Void)? = nil) throws {
        guard let owner = try context.fetch(FetchDescriptor<HealthKitFieldOwnership>()).first(where: {
            $0.recordID == log.id && $0.field == field
        }), let value = owner.healthValue else { return }
        let previousValue = Self.value(field: field, log: log)
        let previousAppliedValue = owner.lastAppliedValue
        let wasManual = owner.isManual
        do {
            set(value, field: field, log: log)
            owner.lastAppliedValue = value
            owner.isManual = false
            if let save { try save() } else { try context.save() }
        } catch {
            context.rollback()
            // SwiftData can retain a materialized object's assigned value after rollback.
            // Restore the visible values as well as the context's pending transaction.
            set(previousValue, field: field, log: log)
            owner.lastAppliedValue = previousAppliedValue
            owner.isManual = wasManual
            throw error
        }
        InsightRefreshCoordinator.invalidate()
        NotificationCenter.default.post(name: .healthKitDidCommit, object: nil)
    }

    static func value(field: String, log: DailyLog) -> Double? {
        switch field {
        case "weight": log.weight
        case "sleepHours": log.sleepHours
        case "activeMinutes": log.activeMinutes.map(Double.init)
        case "restingHeartRateBPM": log.restingHeartRateBPM
        default: nil
        }
    }

    static func set(_ value: Double?, field: String, log: DailyLog) {
        switch field {
        case "weight": log.weight = value
        case "sleepHours": log.sleepHours = value
        case "activeMinutes": log.activeMinutes = value.map { Int($0.rounded()) }
        case "restingHeartRateBPM": log.restingHeartRateBPM = value
        default: break
        }
    }
}

extension Notification.Name {
    static let healthKitDidCommit = Notification.Name("CycleBalance.healthKitDidCommit")
}

struct HealthKitSampleChange: Sendable {
    var uuid: String
    var identifier: String
    var start: Date
    var end: Date
    var value: Double?
    var categoryValue: Int?
    var source: String
    var sourceBundle: String?
}

struct HealthKitChangeBatch: Sendable {
    var identifier: String
    var samples: [HealthKitSampleChange]
    var deletedUUIDs: [String]
    var anchor: Data
}
