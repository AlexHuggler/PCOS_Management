import Foundation
import SwiftData

@Model
final class OvulationObservation {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<OvulationObservation>([\.date])
    #endif

    var id: UUID = UUID()
    var date: Date = Date()
    var basalBodyTemperatureCelsius: Double?
    var cervicalMucus: CervicalMucusType?
    var lhTestResult: LHTestResult?
    var notes: String?
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        date: Date,
        basalBodyTemperatureCelsius: Double? = nil,
        cervicalMucus: CervicalMucusType? = nil,
        lhTestResult: LHTestResult? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.basalBodyTemperatureCelsius = basalBodyTemperatureCelsius
        self.cervicalMucus = cervicalMucus
        self.lhTestResult = lhTestResult
        self.notes = notes
        self.createdAt = createdAt
    }
}
