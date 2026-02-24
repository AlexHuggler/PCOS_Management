import Foundation
import SwiftData

@Model
final class SupplementLog {
    var id: UUID
    var date: Date
    var supplementName: String
    var dosageMg: Double?
    var timeTaken: Date
    var taken: Bool
    var brand: String?

    init(
        id: UUID = UUID(),
        date: Date,
        supplementName: String,
        dosageMg: Double? = nil,
        timeTaken: Date,
        taken: Bool = true,
        brand: String? = nil
    ) {
        self.id = id
        self.date = date
        self.supplementName = supplementName
        self.dosageMg = dosageMg
        self.timeTaken = timeTaken
        self.taken = taken
        self.brand = brand
    }
}
