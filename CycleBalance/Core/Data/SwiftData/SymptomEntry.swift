import Foundation
import SwiftData

@Model
final class SymptomEntry {
    var id: UUID
    var date: Date
    var category: SymptomCategory
    var symptomType: String
    var severity: Int
    var notes: String?

    var cycleEntry: CycleEntry?

    init(
        id: UUID = UUID(),
        date: Date,
        category: SymptomCategory,
        symptomType: String,
        severity: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.category = category
        self.symptomType = symptomType
        self.severity = severity
        self.notes = notes
    }

    /// Convenience initializer using SymptomType enum
    convenience init(
        id: UUID = UUID(),
        date: Date,
        type: SymptomType,
        severity: Int,
        notes: String? = nil
    ) {
        self.init(
            id: id,
            date: date,
            category: type.category,
            symptomType: type.rawValue,
            severity: min(max(severity, 1), 5),
            notes: notes
        )
    }
}
