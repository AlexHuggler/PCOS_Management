import Foundation
import SwiftData
import UIKit
import os

protocol MealPhotoStoring {
    func saveMealPhoto(_ data: Data, mealID: UUID) throws -> String
}

struct LocalMealPhotoStore: MealPhotoStoring {
    var fileManager: FileManager = .default

    func saveMealPhoto(_ data: Data, mealID: UUID) throws -> String {
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("MealScanPhotos", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let url = directory.appendingPathComponent("\(mealID.uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }
}

@MainActor
struct SwiftDataMealLogRepository: MealLogRepository {
    let modelContext: ModelContext
    var photoStore: MealPhotoStoring = LocalMealPhotoStore()
    var featureFlags: MealScanFeatureFlags = .current

    func saveMealScan(_ confirmedMeal: ConfirmedMealScan) async throws {
        let result = confirmedMeal.scanResult
        let now = Date()
        let mealID = confirmedMeal.id
        let isRepeated = confirmedMeal.repeatSourceRecordID != nil
        let sourceName = isRepeated ? "Repeated reviewed meal" : "AI meal estimate"
        let mealSource = isRepeated ? "reusedMeal" : NutritionImportSourceKind.aiMealScan.rawValue
        let photoPath: String?
        if featureFlags.enableMealPhotoRetention, let photoData = confirmedMeal.photoData {
            photoPath = try photoStore.saveMealPhoto(photoData, mealID: mealID)
        } else {
            photoPath = confirmedMeal.photoLocalPath
        }

        let nutritionImport = NutritionImportRecord(
            id: UUID(),
            sourceKind: .aiMealScan,
            sourceName: sourceName,
            externalIdentifier: result.id.uuidString,
            startDate: confirmedMeal.loggedAt,
            productName: result.mealName,
            servingText: "\(result.detectedItems.count) estimated foods",
            calories: result.nutrition.caloriesKcal,
            carbsGrams: result.nutrition.carbsGrams,
            proteinGrams: result.nutrition.proteinGrams,
            fatGrams: result.nutrition.fatGrams,
            fiberGrams: result.nutrition.fiberGrams,
            sugarGrams: result.nutrition.sugarGrams,
            confidence: result.confidence.score,
            completeness: result.detectedItems.isEmpty ? 0 : 0.86,
            importedAt: now,
            reviewStatus: .reviewed,
            userReviewed: confirmedMeal.userConfirmed,
            notes: result.metabolicProfile.caution
        )
        modelContext.insert(nutritionImport)

        let meal = MealEntry(
            id: mealID,
            timestamp: confirmedMeal.loggedAt,
            mealType: confirmedMeal.mealType,
            mealDescription: result.mealName,
            glycemicImpact: result.metabolicProfile.estimatedGlycemicImpact.mealEntryImpact,
            photoData: nil,
            carbsGrams: result.nutrition.carbsGrams,
            proteinGrams: result.nutrition.proteinGrams,
            fatGrams: result.nutrition.fatGrams,
            notes: confirmedMeal.notes ?? result.metabolicProfile.explanation,
            selectedTemplateID: nil,
            nutritionImportID: nutritionImport.id,
            sourceLabel: sourceName,
            calories: result.nutrition.caloriesKcal,
            fiberGrams: result.nutrition.fiberGrams,
            sugarGrams: result.nutrition.sugarGrams,
            servingText: "\(result.detectedItems.count) estimated foods",
            mealSource: mealSource,
            photoLocalPath: photoPath,
            confidenceScore: result.confidence.score,
            userConfirmed: confirmedMeal.userConfirmed,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(meal)

        for item in result.detectedItems {
            modelContext.insert(
                MealScanFoodItem(
                    id: item.id,
                    mealId: mealID,
                    displayName: item.displayName,
                    canonicalFoodId: item.canonicalFoodId,
                    nutritionSource: item.nutritionSource,
                    estimatedGrams: item.estimatedGrams,
                    estimatedVolumeMl: item.estimatedVolumeMl,
                    servingDescription: item.servingDescription,
                    nutrition: item.nutrition,
                    confidenceScore: item.confidence.score,
                    detectionSource: item.detectionSource,
                    portionEstimationMethod: item.portionEstimationMethod,
                    wasUserEdited: item.wasUserEdited,
                    warning: item.warning,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        modelContext.insert(
            MealScanNutritionSummary(
                mealId: mealID,
                nutrition: result.nutrition,
                confidenceScore: result.confidence.score,
                estimatedGlycemicImpact: result.metabolicProfile.estimatedGlycemicImpact,
                nutritionSourceSummary: "Local fixture nutrition database",
                createdAt: now,
                updatedAt: now
            )
        )

        modelContext.insert(
            MealScanMetadata(
                mealId: mealID,
                originalPredictionJSON: result.originalPredictionJSON,
                finalUserConfirmedJSON: confirmedMeal.finalUserConfirmedJSON,
                modelVersion: result.modelVersion,
                pipelineVersion: result.pipelineVersion,
                userConfirmed: confirmedMeal.userConfirmed,
                hasUserEdits: confirmedMeal.hasUserEdits,
                createdAt: now,
                updatedAt: now
            )
        )

            try modelContext.save()
            InsightRefreshCoordinator.invalidate()
            Logger.meals.info("Saved reviewed AI meal estimate.")
        }
    }
