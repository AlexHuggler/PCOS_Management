import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Settings Data Deletion Service", .serialized)
@MainActor
struct SettingsDataDeletionServiceTests {
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
        #expect(try context.fetch(FetchDescriptor<HairPhotoEntry>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<DailyLog>()).isEmpty)
    }
}
