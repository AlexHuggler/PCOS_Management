import Foundation

struct RepeatMealSourceMetadata: Codable, Equatable, Sendable {
    var modelVersion: String
    var pipelineVersion: String
}

struct RepeatMealDraftSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = Self.currentSchemaVersion
    var mealName: String
    var mealType: MealType
    var items: [MealFoodItemDraft]
    var nutrition: NutritionSnapshot
    var confidence: NutritionConfidence
    var warnings: [String]
    var hiddenIngredientEstimate: HiddenIngredientEstimate
    var source: RepeatMealSourceMetadata

    func makeDraftItemsForReuse() -> [MealFoodItemDraft] {
        items.map { item in
            var reusedItem = item
            reusedItem.id = UUID()
            return reusedItem
        }
    }
}

struct MealImageFingerprint: Equatable, Sendable {
    var sourceImageHash: String
    var featurePrintArchive: Data?
    var visionRevision: Int
}

struct RepeatMealSuggestion: Identifiable, Equatable, Sendable {
    enum MatchKind: String, Sendable {
        case exactImage
        case similarImage
    }

    var id: UUID { recordID }
    var recordID: UUID
    var sourceMealID: UUID
    var snapshot: RepeatMealDraftSnapshot
    var sourceMealLoggedAt: Date
    var matchKind: MatchKind
}

struct MealRepeatSimilarityPolicy: Codable, Equatable, Sendable {
    var version: Int
    var enabled: Bool
    var maximumDistance: Float
    var minimumNeighborMargin: Float
    var evaluatedImageCount: Int
    var precision: Double
    var highRiskFalseMatches: Int

    static let disabled = Self(
        version: 1,
        enabled: false,
        maximumDistance: 0,
        minimumNeighborMargin: 0,
        evaluatedImageCount: 0,
        precision: 0,
        highRiskFalseMatches: 0
    )
}
