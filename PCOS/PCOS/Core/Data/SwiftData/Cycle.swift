import Foundation
import SwiftData

@Model
final class Cycle {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var endDate: Date?
    var lengthDays: Int?
    var isPredicted: Bool = false

    @Relationship(deleteRule: .cascade)
    var entries: [CycleEntry]?

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
