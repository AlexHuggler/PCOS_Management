import Foundation
import SwiftData
import UIKit
import os

struct StoredMealPhoto: Equatable {
    let path: String
    let wasNewlyCreated: Bool
}

protocol MealPhotoStoring {
    func saveMealPhoto(_ data: Data, mealID: UUID) throws -> StoredMealPhoto
    func deleteMealPhoto(at path: String) throws
}

struct LocalMealPhotoStore: MealPhotoStoring {
    var fileManager: FileManager = .default

    func saveMealPhoto(_ data: Data, mealID: UUID) throws -> StoredMealPhoto {
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
        let wasNewlyCreated = !fileManager.fileExists(atPath: url.path)
        try data.write(to: url, options: .atomic)
        return StoredMealPhoto(path: url.path, wasNewlyCreated: wasNewlyCreated)
    }

    func deleteMealPhoto(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else { return }
        try fileManager.removeItem(atPath: path)
    }
}

@MainActor
struct SwiftDataMealLogRepository: MealLogRepository {
    let modelContext: ModelContext
    var photoStore: MealPhotoStoring = LocalMealPhotoStore()
    var featureFlags: MealScanFeatureFlags = .current
    var saveModelContext: (ModelContext) throws -> Void = { try $0.save() }

    func saveMealScan(_ confirmedMeal: ConfirmedMealScan) async throws {
        // Keep scanner writes isolated so their rollback cannot discard pending caller edits.
        let scannerContext = ModelContext(modelContext.container)
        scannerContext.autosaveEnabled = false

        let mealID = confirmedMeal.id
        var existingMealDescriptor = FetchDescriptor<MealEntry>(
            predicate: #Predicate { meal in
                meal.id == mealID
            }
        )
        existingMealDescriptor.fetchLimit = 1
        guard try modelContext.fetch(existingMealDescriptor).isEmpty,
              try scannerContext.fetch(existingMealDescriptor).isEmpty else {
            return
        }

        let result = confirmedMeal.scanResult
        let now = Date()
        let isRepeated = confirmedMeal.repeatSourceRecordID != nil
        let sourceName = isRepeated ? "Repeated reviewed meal" : "Photo meal estimate"
        let mealSource = isRepeated ? "reusedMeal" : NutritionImportSourceKind.aiMealScan.rawValue
        let storedPhoto: StoredMealPhoto?
        let photoPath: String?
        if featureFlags.enableMealPhotoRetention, let photoData = confirmedMeal.photoData {
            let photo = try photoStore.saveMealPhoto(photoData, mealID: mealID)
            storedPhoto = photo
            photoPath = photo.path
        } else {
            storedPhoto = nil
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
        scannerContext.insert(nutritionImport)

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
        scannerContext.insert(meal)

        for item in result.detectedItems {
            scannerContext.insert(
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
                    wasPortionAdjusted: item.wasPortionAdjusted,
                    warning: item.warning,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        scannerContext.insert(
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

        scannerContext.insert(
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

        do {
            try saveModelContext(scannerContext)
        } catch {
            let persistenceError = error
            scannerContext.rollback()
            if let storedPhoto, storedPhoto.wasNewlyCreated {
                do {
                    try photoStore.deleteMealPhoto(at: storedPhoto.path)
                } catch {
                    Logger.meals.error("Failed to remove a newly created meal photo after persistence failed.")
                }
            }
            throw persistenceError
        }

        InsightRefreshCoordinator.invalidate()
        Logger.meals.info("Saved reviewed AI meal estimate.")
    }
}
