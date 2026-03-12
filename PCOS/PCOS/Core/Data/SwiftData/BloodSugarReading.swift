import Foundation
import SwiftData

@Model
final class BloodSugarReading {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var glucoseValue: Double = 0
    var readingType: GlucoseReadingType = GlucoseReadingType.random
    var mealContext: String?
    var fromHealthKit: Bool = false
    var notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        glucoseValue: Double,
        readingType: GlucoseReadingType,
        mealContext: String? = nil,
        fromHealthKit: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.glucoseValue = glucoseValue
        self.readingType = readingType
        self.mealContext = mealContext
        self.fromHealthKit = fromHealthKit
        self.notes = notes
    }
}
