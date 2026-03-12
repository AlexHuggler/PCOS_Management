import Foundation
import SwiftData

@Model
final class CycleEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var flowIntensity: FlowIntensity?
    var isPeriodDay: Bool = false
    var cyclePhase: CyclePhase?
    var notes: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SymptomEntry.cycleEntry)
    var symptoms: [SymptomEntry]?

    @Relationship(inverse: \Cycle.entries)
    var cycle: Cycle?

    init(
        id: UUID = UUID(),
        date: Date,
        flowIntensity: FlowIntensity? = nil,
        isPeriodDay: Bool = false,
        cyclePhase: CyclePhase? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.flowIntensity = flowIntensity
        self.isPeriodDay = isPeriodDay
        self.cyclePhase = cyclePhase
        self.notes = notes
        self.createdAt = createdAt
    }
}
