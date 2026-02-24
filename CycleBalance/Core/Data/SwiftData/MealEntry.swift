import Foundation
import SwiftData

@Model
final class MealEntry {
    var id: UUID
    var timestamp: Date
    var mealType: MealType
    var mealDescription: String
    var glycemicImpact: GlycemicImpact
    @Attribute(.externalStorage) var photoData: Data?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        mealType: MealType,
        mealDescription: String,
        glycemicImpact: GlycemicImpact,
        photoData: Data? = nil,
        carbsGrams: Double? = nil,
        proteinGrams: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mealType = mealType
        self.mealDescription = mealDescription
        self.glycemicImpact = glycemicImpact
        self.photoData = photoData
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.notes = notes
    }
}
