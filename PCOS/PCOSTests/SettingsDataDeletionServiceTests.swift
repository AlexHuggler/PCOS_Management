import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Settings Data Deletion Service", .serialized)
@MainActor
struct SettingsDataDeletionServiceTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsDataDeletionServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("deleteAllData removes all tracked models")
    func deleteAllDataRemovesAllTrackedModels() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        let cycle = Cycle(startDate: Date())
        context.insert(cycle)

        let cycleEntry = CycleEntry(date: Date(), flowIntensity: .heavy, isPeriodDay: true)
        cycleEntry.cycle = cycle
        context.insert(cycleEntry)

        context.insert(SymptomEntry(date: Date(), type: .fatigue, severity: 4, notes: "note"))
        context.insert(Insight(insightType: .cyclePattern, title: "Title", content: "Body", confidence: 0.8, dataPointsUsed: 3))
        context.insert(BloodSugarReading(timestamp: Date(), glucoseValue: 101, readingType: .fasting, notes: "note"))
        context.insert(SupplementLog(date: Date(), supplementName: "Inositol", dosageMg: 2000, timeTaken: Date(), taken: true))
        context.insert(MealEntry(timestamp: Date(), mealType: .dinner, mealDescription: "Meal", glycemicImpact: .medium))
        context.insert(
            MealScanResultCacheRecord(
                cacheKey: "cache-key",
                modelID: "model-id",
                schemaVersion: "schema-v1",
                promptVersion: "prompt-v1",
                responseJSON: "{}",
                confidenceScore: 0.9,
                sourceImageHash: "image-hash"
            )
        )
        context.insert(HairPhotoEntry(date: Date(), photoType: .scalpPart, photoData: Data([0x00]), notes: "note"))
        context.insert(DailyLog(date: Date(), weight: 140, sleepHours: 7.5, activeMinutes: 30, stressLevel: 2, energyLevel: 4, waterOz: 64))

        try context.save()

        let service = SettingsDataDeletionService(modelContext: context)
        try service.deleteAllData()

        #expect(try context.fetch(FetchDescriptor<CycleEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cycle>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SymptomEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Insight>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<BloodSugarReading>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<SupplementLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MealScanResultCacheRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<HairPhotoEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }

    @Test("deleteAllData recursively removes the injected meal scan photos directory")
    func deleteAllDataRemovesMealScanPhotosRecursively() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let photosDirectory = rootDirectory.appendingPathComponent("MealScanPhotos", isDirectory: true)
        let nestedDirectory = photosDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data([0x01, 0x02]).write(to: nestedDirectory.appendingPathComponent("meal.jpg"))

        let container = try TestHelpers.makeModelContainer()
        let service = SettingsDataDeletionService(
            modelContext: container.mainContext,
            mealScanPhotosDirectory: photosDirectory
        )

        try service.deleteAllData()

        #expect(!FileManager.default.fileExists(atPath: photosDirectory.path))
    }

    @Test("deleteAllData treats a missing meal scan photos directory as a no-op")
    func deleteAllDataToleratesMissingMealScanPhotosDirectory() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let photosDirectory = rootDirectory.appendingPathComponent("MealScanPhotos", isDirectory: true)
        let container = try TestHelpers.makeModelContainer()
        let service = SettingsDataDeletionService(
            modelContext: container.mainContext,
            mealScanPhotosDirectory: photosDirectory
        )

        try service.deleteAllData()

        #expect(!FileManager.default.fileExists(atPath: photosDirectory.path))
    }

    @Test("deleteAllData propagates meal scan photos filesystem errors")
    func deleteAllDataPropagatesMealScanPhotosFilesystemErrors() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rootDirectory.path) }
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let photosDirectory = rootDirectory.appendingPathComponent("MealScanPhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: photosDirectory.appendingPathComponent("meal.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: photosDirectory.path)

        let container = try TestHelpers.makeModelContainer()
        let service = SettingsDataDeletionService(
            modelContext: container.mainContext,
            mealScanPhotosDirectory: photosDirectory
        )

        #expect(throws: Error.self) {
            try service.deleteAllData()
        }
    }
}
