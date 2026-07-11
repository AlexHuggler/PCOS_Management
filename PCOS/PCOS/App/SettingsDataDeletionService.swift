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
        try modelContext.delete(model: CycleEntry.self)
        try modelContext.delete(model: Cycle.self)
        try modelContext.delete(model: OvulationObservation.self)
        try modelContext.delete(model: SymptomEntry.self)
        try modelContext.delete(model: Insight.self)
        try modelContext.delete(model: BloodSugarReading.self)
        try modelContext.delete(model: SupplementLog.self)
        try modelContext.delete(model: MealEntry.self)
        try modelContext.delete(model: MealScanFoodItem.self)
        try modelContext.delete(model: MealScanNutritionSummary.self)
        try modelContext.delete(model: MealScanMetadata.self)
        try modelContext.delete(model: MealScanResultCacheRecord.self)
        try modelContext.delete(model: NutritionImportRecord.self)
        try modelContext.delete(model: HealthKitImportedSampleRecord.self)
        try modelContext.delete(model: HairPhotoEntry.self)
        try modelContext.delete(model: DailyLog.self)
        try modelContext.delete(model: PregnancyRecord.self)
        try modelContext.save()
        try deleteMealScanPhotosDirectory()
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
