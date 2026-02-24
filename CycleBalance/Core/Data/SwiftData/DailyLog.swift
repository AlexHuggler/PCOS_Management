import Foundation
import SwiftData

@Model
final class DailyLog {
    var id: UUID
    var date: Date
    var weight: Double?
    var sleepHours: Double?
    var activeMinutes: Int?
    var stressLevel: Int?
    var energyLevel: Int?
    var waterOz: Int?

    init(
        id: UUID = UUID(),
        date: Date,
        weight: Double? = nil,
        sleepHours: Double? = nil,
        activeMinutes: Int? = nil,
        stressLevel: Int? = nil,
        energyLevel: Int? = nil,
        waterOz: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.weight = weight
        self.sleepHours = sleepHours
        self.activeMinutes = activeMinutes
        self.stressLevel = stressLevel
        self.energyLevel = energyLevel
        self.waterOz = waterOz
    }
}
