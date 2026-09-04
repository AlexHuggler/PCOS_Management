import Foundation
import SwiftData

@Model
final class SupplementLog {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<SupplementLog>([\.timeTaken])
    #endif

    var id: UUID = UUID()
    var date: Date = Date()
    var supplementName: String = ""
    var dosageMg: Double?
    /// Raw `DosageUnit` value; defaults to milligrams for rows written before units existed.
    var dosageUnitRawValue: String = DosageUnit.milligram.rawValue
    var timeTaken: Date = Date()
    var taken: Bool = true
    var brand: String?

    init(
        id: UUID = UUID(),
        date: Date,
        supplementName: String,
        dosageMg: Double? = nil,
        dosageUnit: DosageUnit = .milligram,
        timeTaken: Date,
        taken: Bool = true,
        brand: String? = nil
    ) {
        self.id = id
        self.date = date
        self.supplementName = supplementName
        self.dosageMg = dosageMg
        self.dosageUnitRawValue = dosageUnit.rawValue
        self.timeTaken = timeTaken
        self.taken = taken
        self.brand = brand
    }

    var dosageUnit: DosageUnit {
        get { DosageUnit(rawValue: dosageUnitRawValue) ?? .milligram }
        set { dosageUnitRawValue = newValue.rawValue }
    }
}
