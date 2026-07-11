import Foundation
import SwiftData

@Model
final class MealScanFoodItem {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<MealScanFoodItem>([\.mealId], [\.canonicalFoodId])
    #endif

    var id: UUID = UUID()
    var mealId: UUID = UUID()
    var displayName: String = ""
    var canonicalFoodId: String?
    var nutritionSource: NutritionDataSource = NutritionDataSource.appFixture
    var estimatedGrams: Double = 0
    var estimatedVolumeMl: Double?
    var servingDescription: String?
    var caloriesKcal: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var netCarbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    var confidenceScore: Double = 0
    var detectionSource: String?
    var portionEstimationMethod: PortionEstimationMethod = PortionEstimationMethod.mockFixture
    var wasUserEdited: Bool = false
    var warning: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        mealId: UUID,
        displayName: String,
        canonicalFoodId: String?,
        nutritionSource: NutritionDataSource,
        estimatedGrams: Double,
        estimatedVolumeMl: Double?,
        servingDescription: String?,
        nutrition: NutritionSnapshot,
        confidenceScore: Double,
        detectionSource: String?,
        portionEstimationMethod: PortionEstimationMethod,
        wasUserEdited: Bool,
        warning: String?,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealId = mealId
        self.displayName = displayName
        self.canonicalFoodId = canonicalFoodId
        self.nutritionSource = nutritionSource
        self.estimatedGrams = estimatedGrams
        self.estimatedVolumeMl = estimatedVolumeMl
        self.servingDescription = servingDescription
        self.caloriesKcal = nutrition.caloriesKcal
        self.proteinGrams = nutrition.proteinGrams
        self.carbsGrams = nutrition.carbsGrams
        self.netCarbsGrams = nutrition.netCarbsGrams
        self.fatGrams = nutrition.fatGrams
        self.fiberGrams = nutrition.fiberGrams
        self.sugarGrams = nutrition.sugarGrams
        self.sodiumMg = nutrition.sodiumMg
        self.saturatedFatGrams = nutrition.saturatedFatGrams
        self.confidenceScore = confidenceScore
        self.detectionSource = detectionSource
        self.portionEstimationMethod = portionEstimationMethod
        self.wasUserEdited = wasUserEdited
        self.warning = warning
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MealScanNutritionSummary {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<MealScanNutritionSummary>([\.mealId])
    #endif

    var id: UUID = UUID()
    var mealId: UUID = UUID()
    var caloriesKcal: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var netCarbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    var confidenceScore: Double = 0
    var estimatedGlycemicImpact: GlycemicImpactLevel = GlycemicImpactLevel.unknown
    var nutritionSourceSummary: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        mealId: UUID,
        nutrition: NutritionSnapshot,
        confidenceScore: Double,
        estimatedGlycemicImpact: GlycemicImpactLevel,
        nutritionSourceSummary: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealId = mealId
        self.caloriesKcal = nutrition.caloriesKcal
        self.proteinGrams = nutrition.proteinGrams
        self.carbsGrams = nutrition.carbsGrams
        self.netCarbsGrams = nutrition.netCarbsGrams
        self.fatGrams = nutrition.fatGrams
        self.fiberGrams = nutrition.fiberGrams
        self.sugarGrams = nutrition.sugarGrams
        self.sodiumMg = nutrition.sodiumMg
        self.saturatedFatGrams = nutrition.saturatedFatGrams
        self.confidenceScore = confidenceScore
        self.estimatedGlycemicImpact = estimatedGlycemicImpact
        self.nutritionSourceSummary = nutritionSourceSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MealScanMetadata {
    #if swift(>=6.0)
    @available(iOS 18, *)
    #Index<MealScanMetadata>([\.mealId])
    #endif

    var id: UUID = UUID()
    var mealId: UUID = UUID()
    var originalPredictionJSON: String = "{}"
    var finalUserConfirmedJSON: String = "{}"
    var modelVersion: String = ""
    var pipelineVersion: String = ""
    var userConfirmed: Bool = false
    var hasUserEdits: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        mealId: UUID,
        originalPredictionJSON: String,
        finalUserConfirmedJSON: String,
        modelVersion: String,
        pipelineVersion: String,
        userConfirmed: Bool,
        hasUserEdits: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealId = mealId
        self.originalPredictionJSON = originalPredictionJSON
        self.finalUserConfirmedJSON = finalUserConfirmedJSON
        self.modelVersion = modelVersion
        self.pipelineVersion = pipelineVersion
        self.userConfirmed = userConfirmed
        self.hasUserEdits = hasUserEdits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class MealScanResultCacheRecord {
    var id: UUID = UUID()
    var cacheKey: String = ""
    var modelID: String = ""
    var schemaVersion: String = ""
    var promptVersion: String = ""
    var responseJSON: String = "{}"
    var confidenceScore: Double = 0
    var sourceImageHash: String = ""
    var createdAt: Date = Date()
    var lastAccessedAt: Date = Date()
    var expiresAt: Date = Date()

    init(
        id: UUID = UUID(),
        cacheKey: String,
        modelID: String,
        schemaVersion: String,
        promptVersion: String,
        responseJSON: String,
        confidenceScore: Double,
        sourceImageHash: String,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date(),
        expiresAt: Date = Date()
    ) {
        self.id = id
        self.cacheKey = cacheKey
        self.modelID = modelID
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.responseJSON = responseJSON
        self.confidenceScore = confidenceScore
        self.sourceImageHash = sourceImageHash
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.expiresAt = expiresAt
    }
}

@Model
final class MealScanRepeatCacheRecord {
    var id: UUID = UUID()
    var sourceMealID: UUID = UUID()
    var sourceImageHash: String = ""
    var featurePrintArchive: Data?
    var visionRevision: Int = 0
    var snapshotJSON: String = "{}"
    var snapshotSchemaVersion: Int = RepeatMealDraftSnapshot.currentSchemaVersion
    var mealName: String = ""
    var mealType: MealType = MealType.snack
    var caloriesKcal: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var sourceMealLoggedAt: Date = Date()
    var createdAt: Date = Date()
    var lastUsedAt: Date = Date()
    var lastMatchedAt: Date?
    var reuseCount: Int = 0

    init(
        id: UUID = UUID(),
        sourceMealID: UUID,
        sourceImageHash: String,
        featurePrintArchive: Data?,
        visionRevision: Int,
        snapshotJSON: String,
        snapshotSchemaVersion: Int,
        mealName: String,
        mealType: MealType,
        caloriesKcal: Double,
        proteinGrams: Double,
        carbsGrams: Double,
        fatGrams: Double,
        sourceMealLoggedAt: Date,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        lastMatchedAt: Date? = nil,
        reuseCount: Int = 0
    ) {
        self.id = id
        self.sourceMealID = sourceMealID
        self.sourceImageHash = sourceImageHash
        self.featurePrintArchive = featurePrintArchive
        self.visionRevision = visionRevision
        self.snapshotJSON = snapshotJSON
        self.snapshotSchemaVersion = snapshotSchemaVersion
        self.mealName = mealName
        self.mealType = mealType
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.sourceMealLoggedAt = sourceMealLoggedAt
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.lastMatchedAt = lastMatchedAt
        self.reuseCount = reuseCount
    }
}
