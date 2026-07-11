import Foundation
import CoreGraphics
import UIKit

enum NutritionDataSource: String, Codable, CaseIterable, Sendable {
    case usda
    case openFoodFacts
    case nutritionLabelOCR
    case userManual
    case appFixture
}

enum NutritionConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case unknown

    var score: Double {
        switch self {
        case .high: 0.9
        case .medium: 0.65
        case .low: 0.35
        case .unknown: 0.2
        }
    }

    var displayName: String {
        switch self {
        case .high: "Good estimate"
        case .medium: "Review suggested"
        case .low: "Needs confirmation"
        case .unknown: "Manual estimate"
        }
    }

    var rank: Int {
        switch self {
        case .unknown: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    func lowered(by steps: Int = 1) -> NutritionConfidence {
        let nextRank = max(0, rank - steps)
        return Self.allCases.first { $0.rank == nextRank } ?? .unknown
    }
}

enum HiddenIngredientEstimate: String, Codable, CaseIterable, Identifiable, Sendable {
    case no
    case aLittle
    case moderate
    case aLot
    case notSure

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .no: "No"
        case .aLittle: "A little"
        case .moderate: "Moderate"
        case .aLot: "A lot"
        case .notSure: "Not sure"
        }
    }

    var addedOilGrams: Double {
        switch self {
        case .no: 0
        case .aLittle: 5
        case .moderate: 14
        case .aLot: 28
        case .notSure: 7
        }
    }
}

enum GlycemicImpactLevel: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case moderateHigh
    case high
    case unknown

    var displayName: String {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .moderateHigh: "Moderate-high"
        case .high: "High"
        case .unknown: "Unknown"
        }
    }

    var mealEntryImpact: GlycemicImpact {
        switch self {
        case .low: .low
        case .moderate, .unknown: .medium
        case .moderateHigh, .high: .high
        }
    }
}

enum MealScanCarbLoadCategory: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high
    case veryHigh
}

enum MealScanAdequacy: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case strong
}

enum MealScanFatLevel: String, Codable, CaseIterable, Sendable {
    case low
    case moderate
    case high
}

enum PortionEstimationMethod: String, Codable, CaseIterable, Sendable {
    case lidarDepth
    case monocularDepth
    case plateReference
    case servingSizeHeuristic
    case manualUserInput
    case mockFixture
}

enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case cookedRice
    case pasta
    case chicken
    case beef
    case fish
    case eggs
    case yogurt
    case oatmeal
    case bread
    case fruit
    case vegetables
    case salad
    case beans
    case soup
    case sauce
    case oilDressing
    case mixedDish
}

struct NutritionSnapshot: Codable, Equatable, Sendable {
    var caloriesKcal: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var netCarbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    var cholesterolMg: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0

    init(
        caloriesKcal: Double = 0,
        proteinGrams: Double = 0,
        carbsGrams: Double = 0,
        netCarbsGrams: Double? = nil,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        sugarGrams: Double = 0,
        sodiumMg: Double = 0,
        saturatedFatGrams: Double = 0,
        cholesterolMg: Double = 0,
        potassiumMg: Double = 0,
        calciumMg: Double = 0,
        ironMg: Double = 0
    ) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.netCarbsGrams = netCarbsGrams ?? max(carbsGrams - fiberGrams, 0)
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.sugarGrams = sugarGrams
        self.sodiumMg = sodiumMg
        self.saturatedFatGrams = saturatedFatGrams
        self.cholesterolMg = cholesterolMg
        self.potassiumMg = potassiumMg
        self.calciumMg = calciumMg
        self.ironMg = ironMg
    }

    func adding(_ other: NutritionSnapshot) -> NutritionSnapshot {
        NutritionSnapshot(
            caloriesKcal: caloriesKcal + other.caloriesKcal,
            proteinGrams: proteinGrams + other.proteinGrams,
            carbsGrams: carbsGrams + other.carbsGrams,
            fatGrams: fatGrams + other.fatGrams,
            fiberGrams: fiberGrams + other.fiberGrams,
            sugarGrams: sugarGrams + other.sugarGrams,
            sodiumMg: sodiumMg + other.sodiumMg,
            saturatedFatGrams: saturatedFatGrams + other.saturatedFatGrams,
            cholesterolMg: cholesterolMg + other.cholesterolMg,
            potassiumMg: potassiumMg + other.potassiumMg,
            calciumMg: calciumMg + other.calciumMg,
            ironMg: ironMg + other.ironMg
        )
    }
}

struct FoodNutritionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var source: NutritionDataSource
    var displayName: String
    var canonicalName: String
    var brandName: String? = nil
    var servingDescription: String? = nil
    var servingGrams: Double? = nil
    var caloriesPer100g: Double? = nil
    var proteinPer100g: Double? = nil
    var carbsPer100g: Double? = nil
    var fatPer100g: Double? = nil
    var fiberPer100g: Double? = nil
    var sugarPer100g: Double? = nil
    var addedSugarPer100g: Double? = nil
    var sodiumMgPer100g: Double? = nil
    var saturatedFatPer100g: Double? = nil
    var cholesterolMgPer100g: Double? = nil
    var potassiumMgPer100g: Double? = nil
    var calciumMgPer100g: Double? = nil
    var ironMgPer100g: Double? = nil
    var category: FoodCategory? = nil
    var aliases: [String] = []
}

struct FoodClassificationCandidate: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var label: String
    var canonicalFoodId: String?
    var confidence: Double
}

struct MealScanRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct FoodSegmentationResult: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var label: String
    var boundingBox: MealScanRect?
    var confidence: Double
    var maskIdentifier: String?
}

struct MealDepthData: Equatable, Sendable {
    var sourceDescription: String
}

struct PortionEstimate: Identifiable, Equatable, Sendable {
    var id: UUID { foodItemId }
    var foodItemId: UUID
    var estimatedGrams: Double?
    var estimatedVolumeMl: Double?
    var servingDescription: String?
    var method: PortionEstimationMethod
    var confidence: NutritionConfidence
    var warning: String?
}

struct DetectedFoodItem: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var canonicalFoodId: String
    var estimatedGrams: Double
    var estimatedVolumeMl: Double? = nil
    var servingDescription: String?
    var nutrition: NutritionSnapshot
    var confidence: NutritionConfidence
    var warning: String?
    var detectionSource: String = "mock_fixture"
    var portionEstimationMethod: PortionEstimationMethod = .mockFixture
    var isMixedDish: Bool = false
}

struct MealFoodItemDraft: Identifiable, Equatable, Codable, Sendable {
    var id: UUID = UUID()
    var displayName: String
    var canonicalFoodId: String
    var nutritionSource: NutritionDataSource = .appFixture
    var estimatedGrams: Double
    var estimatedVolumeMl: Double? = nil
    var servingDescription: String? = nil
    var nutrition: NutritionSnapshot = NutritionSnapshot()
    var confidence: NutritionConfidence = .medium
    var warning: String? = nil
    var detectionSource: String = "mock_fixture"
    var portionEstimationMethod: PortionEstimationMethod = .mockFixture
    var wasUserEdited: Bool = false
    var isMixedDish: Bool = false
}

struct MealMetabolicProfile: Codable, Equatable, Sendable {
    var carbLoadCategory: MealScanCarbLoadCategory
    var proteinAdequacy: MealScanAdequacy
    var fiberAdequacy: MealScanAdequacy
    var fatLevel: MealScanFatLevel
    var estimatedGlycemicImpact: GlycemicImpactLevel
    var mealBalanceScore: Int
    var explanation: String
    var caution: String?
}

struct MealScanResult: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var mealName: String
    var mealType: MealType
    var detectedItems: [MealFoodItemDraft]
    var nutrition: NutritionSnapshot
    var metabolicProfile: MealMetabolicProfile
    var confidence: NutritionConfidence
    var warnings: [String]
    var originalPredictionJSON: String
    var modelVersion: String
    var pipelineVersion: String
}

struct ConfirmedMealScan: Equatable, Sendable {
    var id: UUID = UUID()
    var scanResult: MealScanResult
    var loggedAt: Date = Date()
    var mealType: MealType
    var userConfirmed: Bool
    var hasUserEdits: Bool
    var finalUserConfirmedJSON: String
    var photoData: Data?
    var photoLocalPath: String?
    var notes: String?
    var repeatSourceRecordID: UUID?

    init(
        id: UUID = UUID(),
        scanResult: MealScanResult,
        loggedAt: Date = Date(),
        mealType: MealType? = nil,
        userConfirmed: Bool,
        hasUserEdits: Bool = false,
        finalUserConfirmedJSON: String? = nil,
        photoData: Data? = nil,
        photoLocalPath: String? = nil,
        notes: String? = nil,
        repeatSourceRecordID: UUID? = nil
    ) {
        self.id = id
        self.scanResult = scanResult
        self.loggedAt = loggedAt
        self.mealType = mealType ?? scanResult.mealType
        self.userConfirmed = userConfirmed
        self.hasUserEdits = hasUserEdits
        self.finalUserConfirmedJSON = finalUserConfirmedJSON ?? scanResult.originalPredictionJSON
        self.photoData = photoData
        self.photoLocalPath = photoLocalPath
        self.notes = notes
        self.repeatSourceRecordID = repeatSourceRecordID
    }
}

struct FoodAlias: Codable, Equatable, Sendable {
    var inputName: String
    var canonicalFoodName: String
    var defaultFoodId: String?
    var category: FoodCategory
}

struct FoodDensityDefaults: Equatable, Sendable {
    var gramsPerMlByCategory: [FoodCategory: Double]

    static let fixture = FoodDensityDefaults(gramsPerMlByCategory: [
        .cookedRice: 0.85,
        .pasta: 0.65,
        .chicken: 0.95,
        .beef: 0.95,
        .fish: 0.9,
        .eggs: 1.03,
        .yogurt: 1.03,
        .oatmeal: 0.8,
        .bread: 0.27,
        .fruit: 0.65,
        .vegetables: 0.55,
        .salad: 0.25,
        .beans: 0.75,
        .soup: 1.0,
        .sauce: 1.05,
        .oilDressing: 0.9,
        .mixedDish: 0.8,
    ])

    func grams(forVolumeMl volumeMl: Double, category: FoodCategory) -> Double {
        let density = gramsPerMlByCategory[category] ?? 1
        return volumeMl * density
    }
}
