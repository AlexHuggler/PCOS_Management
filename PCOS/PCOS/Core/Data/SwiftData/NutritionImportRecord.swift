import Foundation
import SwiftData

enum NutritionImportSourceKind: String, Codable, CaseIterable, Sendable {
    case healthKit = "health_kit"
    case barcodeOpenFoodFacts = "barcode_open_food_facts"
    case barcodeUSDA = "barcode_usda"
    case manualReview = "manual_review"
    case aiMealScan = "ai_meal_scan"

    var displayName: String {
        switch self {
        case .healthKit:
            "Apple Health"
        case .barcodeOpenFoodFacts:
            "Open Food Facts"
        case .barcodeUSDA:
            "USDA FoodData Central"
        case .manualReview:
            "Manual review"
        case .aiMealScan:
            "AI meal estimate"
        }
    }
}

enum NutritionImportReviewStatus: String, Codable, CaseIterable, Sendable {
    case needsReview = "needs_review"
    case reviewed
    case rejected
}

@Model
final class NutritionImportRecord {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<NutritionImportRecord>([\.startDate], [\.barcode])
    #endif

    var id: UUID = UUID()
    var sourceKind: NutritionImportSourceKind = NutritionImportSourceKind.manualReview
    var sourceName: String?
    var externalIdentifier: String?
    var startDate: Date = Date()
    var endDate: Date?
    var barcode: String?
    var productName: String?
    var brandName: String?
    var servingText: String?
    var calories: Double?
    var carbsGrams: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var fiberGrams: Double?
    var sugarGrams: Double?
    var waterOz: Double?
    var sodiumMg: Double?
    var saturatedFatGrams: Double?
    var cholesterolMg: Double?
    var potassiumMg: Double?
    var calciumMg: Double?
    var ironMg: Double?
    var confidence: Double = 0
    var completeness: Double = 0
    var importedAt: Date = Date()
    var reviewStatus: NutritionImportReviewStatus = NutritionImportReviewStatus.needsReview
    var userReviewed: Bool = false
    var notes: String?

    init(
        id: UUID = UUID(),
        sourceKind: NutritionImportSourceKind,
        sourceName: String? = nil,
        externalIdentifier: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        barcode: String? = nil,
        productName: String? = nil,
        brandName: String? = nil,
        servingText: String? = nil,
        calories: Double? = nil,
        carbsGrams: Double? = nil,
        proteinGrams: Double? = nil,
        fatGrams: Double? = nil,
        fiberGrams: Double? = nil,
        sugarGrams: Double? = nil,
        waterOz: Double? = nil,
        sodiumMg: Double? = nil,
        saturatedFatGrams: Double? = nil,
        cholesterolMg: Double? = nil,
        potassiumMg: Double? = nil,
        calciumMg: Double? = nil,
        ironMg: Double? = nil,
        confidence: Double = 0,
        completeness: Double = 0,
        importedAt: Date = Date(),
        reviewStatus: NutritionImportReviewStatus = .needsReview,
        userReviewed: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sourceName = sourceName
        self.externalIdentifier = externalIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.barcode = barcode
        self.productName = productName
        self.brandName = brandName
        self.servingText = servingText
        self.calories = calories
        self.carbsGrams = carbsGrams
        self.proteinGrams = proteinGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.waterOz = waterOz
        self.sodiumMg = sodiumMg
        self.saturatedFatGrams = saturatedFatGrams
        self.cholesterolMg = cholesterolMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
        self.confidence = confidence
        self.completeness = completeness
        self.importedAt = importedAt
        self.reviewStatus = reviewStatus
        self.userReviewed = userReviewed
        self.notes = notes
    }

    var sourceLabel: String {
        sourceName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? sourceName ?? sourceKind.displayName
            : sourceKind.displayName
    }

    var displayProductName: String {
        productName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? productName ?? sourceLabel
            : sourceLabel
    }
}
