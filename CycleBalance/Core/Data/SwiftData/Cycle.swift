import Foundation
import SwiftData

@Model
final class Cycle {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var lengthDays: Int?
    var isPredicted: Bool

    @Relationship(deleteRule: .nullify)
    var entries: [CycleEntry] = []

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        lengthDays: Int? = nil,
        isPredicted: Bool = false
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.lengthDays = lengthDays
        self.isPredicted = isPredicted
    }
}
