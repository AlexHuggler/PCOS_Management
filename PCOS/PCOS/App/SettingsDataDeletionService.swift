import Foundation
import SwiftData

@MainActor
struct SettingsDataDeletionService {
    private let modelContext: ModelContext
    private let fileManager: FileManager
    private let mealScanPhotosDirectory: URL

    init(
        modelContext: ModelContext,
        mealScanPhotosDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.fileManager = fileManager
        self.mealScanPhotosDirectory = mealScanPhotosDirectory
            ?? Self.defaultMealScanPhotosDirectory(fileManager: fileManager)
    }

    func deleteAllData() throws {
        try deleteAll(CycleEntry.self)
        try deleteAll(Cycle.self)
        try deleteAll(OvulationObservation.self)
        try deleteAll(SymptomEntry.self)
        try deleteAll(Insight.self)
        try deleteAll(BloodSugarReading.self)
        try deleteAll(SupplementLog.self)
        try deleteAll(MealScanRepeatCacheRecord.self)
        try deleteAll(MealEntry.self)
        try deleteAll(MealScanFoodItem.self)
        try deleteAll(MealScanNutritionSummary.self)
        try deleteAll(MealScanMetadata.self)
        try deleteAll(MealScanResultCacheRecord.self)
        try deleteAll(NutritionImportRecord.self)
        try deleteAll(HealthKitImportedSampleRecord.self)
        try deleteAll(HairPhotoEntry.self)
        try deleteAll(DailyLog.self)
        try deleteAll(PregnancyRecord.self)
        try modelContext.save()
        try deleteMealScanPhotosDirectory()
    }

    private func deleteAll<Model: PersistentModel>(_: Model.Type) throws {
        for model in try modelContext.fetch(FetchDescriptor<Model>()) {
            modelContext.delete(model)
        }
    }

    private func deleteMealScanPhotosDirectory() throws {
        guard fileManager.fileExists(atPath: mealScanPhotosDirectory.path) else { return }
        try fileManager.removeItem(at: mealScanPhotosDirectory)
    }

    private static func defaultMealScanPhotosDirectory(fileManager: FileManager) -> URL {
        let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupportDirectory.appendingPathComponent("MealScanPhotos", isDirectory: true)
    }
}
