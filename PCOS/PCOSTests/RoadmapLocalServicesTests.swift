import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import PCOS

@Suite("Roadmap Local Services", .serialized)
@MainActor
struct RoadmapLocalServicesTests {
    @Test("meal glucose service pairs meals, readings, feedback, reuse, and readiness")
    func mealGlucoseServicePairsContextAndReadiness() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let mealDate = Date(timeIntervalSince1970: 1_780_000_000)
        let meal = MealEntry(
            timestamp: mealDate,
            mealType: .lunch,
            mealDescription: "Quinoa chicken bowl",
            glycemicImpact: .low,
            carbsGrams: 32,
            proteinGrams: 28,
            fatGrams: 14,
            notes: "Balanced plate",
            postMealSymptomSeverity: 2,
            postMealSymptomNote: "Steady energy",
            postMealFeedbackTimestamp: mealDate.addingTimeInterval(7_200)
        )
        context.insert(meal)
        context.insert(
            BloodSugarReading(
                timestamp: mealDate.addingTimeInterval(-1_200),
                glucoseValue: 92,
                readingType: .beforeMeal,
                mealContext: "Before quinoa chicken bowl"
            )
        )
        context.insert(
            BloodSugarReading(
                timestamp: mealDate.addingTimeInterval(5_400),
                glucoseValue: 128,
                readingType: .afterMeal,
                mealContext: "After quinoa chicken bowl"
            )
        )
        try context.save()

        let service = MealGlucoseContextService(modelContext: context)
        let pairings = try service.mealGlucosePairings(days: 14, now: mealDate.addingTimeInterval(86_400))
        let pairing = try #require(pairings.first)
        let prefill = service.glucosePrefillContext(for: meal, readingType: .afterMeal, now: mealDate.addingTimeInterval(7_200))
        let reuse = try service.recentMealReuseSuggestions(limit: 3)
        let readiness = try service.readiness(days: 14, now: mealDate.addingTimeInterval(86_400))

        #expect(pairing.meal.id == meal.id)
        #expect(pairing.beforeMealReading?.glucoseValue == 92)
        #expect(pairing.afterMealReadings.map(\.glucoseValue) == [128])
        #expect(pairing.postMealFeedback?.severity == 2)
        #expect(pairing.postMealFeedback?.note == "Steady energy")
        #expect(prefill.mealContext == "After Quinoa chicken bowl")
        #expect(prefill.readingType == .afterMeal)
        #expect(reuse.first?.mealDescription == "Quinoa chicken bowl")
        #expect(reuse.first?.glycemicImpact == .low)
        #expect(readiness.state == .building)
        #expect(readiness.message.contains("meal and glucose"))
    }

    @Test("HealthKit contribution summaries count local Apple Health sources")
    func healthKitContributionSummariesCountSources() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        context.insert(
            DailyLog(
                date: now,
                weight: 72.5,
                sleepHours: 7.4,
                activeMinutes: 44,
                restingHeartRateBPM: 63
            )
        )
        context.insert(
            BloodSugarReading(
                timestamp: now.addingTimeInterval(-3_600),
                glucoseValue: 101,
                readingType: .random,
                fromHealthKit: true
            )
        )
        context.insert(
            BloodSugarReading(
                timestamp: now.addingTimeInterval(-1_800),
                glucoseValue: 119,
                readingType: .random,
                fromHealthKit: false
            )
        )
        try context.save()

        let summaries = try HealthKitContributionSummaryService(modelContext: context).summaries(days: 7, now: now)
        let counts = Dictionary(uniqueKeysWithValues: summaries.map { ($0.kind, $0.sampleCount) })

        #expect(counts[.bodyMass] == 1)
        #expect(counts[.sleepAnalysis] == 1)
        #expect(counts[.activeMinutes] == 1)
        #expect(counts[.restingHeartRate] == 1)
        #expect(counts[.bloodGlucose] == 1)
        #expect(summaries.first(where: { $0.kind == .bloodGlucose })?.sourceLabel == "Apple Health")
    }

    @Test("local profile photo store saves deletes and supports app-lock masking")
    func localProfilePhotoStoreSavesDeletesAndMasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProfilePhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = LocalProfilePhotoStore(baseDirectory: directory)
        let data = Data([0x01, 0x02, 0x03])
        let savedURL = try store.saveProfilePhoto(data)

        #expect(savedURL.lastPathComponent == "profile-photo.dat")
        #expect(try store.loadProfilePhoto() == data)
        #expect(store.shouldMaskProfilePhoto(isAppLockEnabled: true, isContentMasked: true))
        #expect(!store.shouldMaskProfilePhoto(isAppLockEnabled: true, isContentMasked: false))

        try store.deleteProfilePhoto()

        #expect(try store.loadProfilePhoto() == nil)
    }
}
