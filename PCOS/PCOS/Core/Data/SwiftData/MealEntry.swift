import Foundation
import SwiftData

@Model
final class MealEntry {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<MealEntry>([\.timestamp])
    #endif

    var id: UUID = UUID()
    var timestamp: Date = Date()
    var mealType: MealType = MealType.breakfast
    var mealDescription: String = ""
    var glycemicImpact: GlycemicImpact = GlycemicImpact.medium
    @Attribute(.externalStorage) var photoData: Data?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var notes: String?
    var selectedTemplateID: String?
    var postMealSymptomSeverity: Int?
    var postMealSymptomNote: String?
    var postMealFeedbackTimestamp: Date?
    var nutritionImportID: UUID?
    var barcode: String?
    var sourceLabel: String?
    var calories: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var servingText: String?
    var mealSource: String?
    var photoLocalPath: String?
    var confidenceScore: Double?
    var userConfirmed: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        timestamp: Date,
        mealType: MealType,
        mealDescription: String,
        glycemicImpact: GlycemicImpact,
        photoData: Data? = nil,
        carbsGrams: Double? = nil,
        proteinGrams: Double? = nil,
        fatGrams: Double? = nil,
        notes: String? = nil,
        selectedTemplateID: String? = nil,
        postMealSymptomSeverity: Int? = nil,
        postMealSymptomNote: String? = nil,
        postMealFeedbackTimestamp: Date? = nil,
        nutritionImportID: UUID? = nil,
        barcode: String? = nil,
        sourceLabel: String? = nil,
        calories: Double? = nil,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        servingText: String? = nil,
        mealSource: String? = nil,
        photoLocalPath: String? = nil,
        confidenceScore: Double? = nil,
        userConfirmed: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mealType = mealType
        self.mealDescription = mealDescription
        self.glycemicImpact = glycemicImpact
        self.photoData = photoData
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.notes = notes
        self.selectedTemplateID = selectedTemplateID
        self.postMealSymptomSeverity = postMealSymptomSeverity
        self.postMealSymptomNote = postMealSymptomNote
        self.postMealFeedbackTimestamp = postMealFeedbackTimestamp
        self.nutritionImportID = nutritionImportID
        self.barcode = barcode
        self.sourceLabel = sourceLabel
        self.calories = calories
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.servingText = servingText
        self.mealSource = mealSource
        self.photoLocalPath = photoLocalPath
        self.confidenceScore = confidenceScore
        self.userConfirmed = userConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
