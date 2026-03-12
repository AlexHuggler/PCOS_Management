import Foundation
import SwiftData

@Model
final class SymptomEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var category: SymptomCategory = SymptomCategory.physical
    var symptomType: SymptomType = SymptomType.fatigue
    var severity: Int = 1
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
