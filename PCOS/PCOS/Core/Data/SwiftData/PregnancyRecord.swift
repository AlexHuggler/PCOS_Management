import Foundation
import SwiftData

@Model
final class PregnancyRecord {
    var id: UUID = UUID()
    var startDate: Date = Date()
    var estimatedDueDate: Date?
    var endDate: Date?
    var endReason: PregnancyEndReason?
    var isActive: Bool = true
    var notes: String?

    init(
        id: UUID = UUID(),
        startDate: Date,
        estimatedDueDate: Date? = nil,
        endDate: Date? = nil,
        endReason: PregnancyEndReason? = nil,
        isActive: Bool = true,
        notes: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.estimatedDueDate = estimatedDueDate
        self.endDate = endDate
        self.endReason = endReason
        self.isActive = isActive
        self.notes = notes
    }
}
