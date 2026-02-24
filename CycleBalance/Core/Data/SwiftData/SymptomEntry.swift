import Foundation
import SwiftData

@Model
final class SymptomEntry {
    var id: UUID
    var date: Date
    var category: SymptomCategory
    var symptomType: SymptomType
    var severity: Int
    var notes: String?

    var cycleEntry: CycleEntry?

    init(
        id: UUID = UUID(),
        date: Date,
        type: SymptomType,
        severity: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.category = type.category
        self.symptomType = type
        self.severity = min(max(severity, 1), 5)
        self.notes = notes
    }
}
