import Testing
import Foundation
import SwiftData
@testable import PCOS

@Suite("Daily Log Service", .serialized)
@MainActor
struct DailyLogServiceTests {
    @Test("Positive actions toggle into today's DailyLog without overwriting health context")
    func positiveActionsPreserveHealthContext() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        let today = Calendar.current.startOfDay(for: Date())
        let existing = DailyLog(
            date: today,
            weight: 140,
            sleepHours: 7.5,
            activeMinutes: 32,
            restingHeartRateBPM: 62,
            stressLevel: 3,
            energyLevel: 4,
            waterOz: 72
        )
        context.insert(existing)
        try context.save()

        let updated = try service.setPositiveAction(.walkMovement, isCompleted: true, date: today)
        _ = try service.setPositiveAction(.stressReduction, isCompleted: true, date: today)
        _ = try service.setPositiveAction(.walkMovement, isCompleted: false, date: today)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(updated.weight == 140)
        #expect(updated.sleepHours == 7.5)
        #expect(updated.activeMinutes == 32)
        #expect(updated.restingHeartRateBPM == 62)
        #expect(!logs[0].hasPositiveAction(.walkMovement))
        #expect(logs[0].hasPositiveAction(.stressReduction))
    }

    @Test("Daily check-in saves zero pain without overwriting existing daily context")
    func dailyCheckInPersistsZeroPain() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        let today = Calendar.current.startOfDay(for: Date())
        let existing = DailyLog(
            date: today,
            weight: 140,
            sleepHours: 7.5,
            activeMinutes: 32,
            restingHeartRateBPM: 62,
            stressLevel: 3,
            energyLevel: 4,
            waterOz: 72,
            positiveActionRawValues: PositiveActionType.walkMovement.rawValue
        )
        context.insert(existing)
        try context.save()

        let updated = try service.saveDailyCheckIn(
            date: today,
            painLevel0To10: 0,
            privateNote: "  No pain today.  "
        )

        #expect(updated.painLevel0To10 == 0)
        #expect(updated.privateNote == "No pain today.")
        #expect(updated.weight == 140)
        #expect(updated.sleepHours == 7.5)
        #expect(updated.activeMinutes == 32)
        #expect(updated.restingHeartRateBPM == 62)
        #expect(updated.stressLevel == 3)
        #expect(updated.energyLevel == 4)
        #expect(updated.waterOz == 72)
        #expect(updated.hasPositiveAction(.walkMovement))
    }

    @Test("Daily check-in rejects pain outside the zero to ten scale")
    func dailyCheckInRejectsPainOutsideScale() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        #expect(throws: DailyLogService.ValidationError.invalidPainLevel) {
            try service.saveDailyCheckIn(date: Date(), painLevel0To10: -1, privateNote: nil)
        }

        #expect(throws: DailyLogService.ValidationError.invalidPainLevel) {
            try service.saveDailyCheckIn(date: Date(), painLevel0To10: 11, privateNote: nil)
        }
    }

    @Test("Daily check-in persists stress and water when provided")
    func dailyCheckInPersistsStressAndWater() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        let today = Calendar.current.startOfDay(for: Date())
        let updated = try service.saveDailyCheckIn(
            date: today,
            painLevel0To10: 2,
            privateNote: nil,
            stressLevel: 4,
            waterOz: 64
        )

        #expect(updated.stressLevel == 4)
        #expect(updated.waterOz == 64)

        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        #expect(logs.count == 1)
        #expect(logs[0].stressLevel == 4)
        #expect(logs[0].waterOz == 64)
    }

    @Test("Daily check-in rejects stress and water outside their valid ranges")
    func dailyCheckInRejectsStressAndWaterOutsideRange() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        #expect(throws: DailyLogService.ValidationError.invalidStressLevel) {
            try service.saveDailyCheckIn(date: Date(), painLevel0To10: nil, privateNote: nil, stressLevel: 0)
        }

        #expect(throws: DailyLogService.ValidationError.invalidStressLevel) {
            try service.saveDailyCheckIn(date: Date(), painLevel0To10: nil, privateNote: nil, stressLevel: 6)
        }

        #expect(throws: DailyLogService.ValidationError.invalidWaterOz) {
            try service.saveDailyCheckIn(date: Date(), painLevel0To10: nil, privateNote: nil, waterOz: -1)
        }
    }

    @Test("Daily check-in with nil stress and water leaves stored values untouched")
    func dailyCheckInNilStressAndWaterLeaveStoredValuesUntouched() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let service = DailyLogService(modelContext: context)

        let today = Calendar.current.startOfDay(for: Date())
        let existing = DailyLog(
            date: today,
            stressLevel: 3,
            waterOz: 72
        )
        context.insert(existing)
        try context.save()

        let updated = try service.saveDailyCheckIn(
            date: today,
            painLevel0To10: 5,
            privateNote: nil
        )

        #expect(updated.painLevel0To10 == 5)
        #expect(updated.stressLevel == 3)
        #expect(updated.waterOz == 72)
    }

    @Test("Positive action catalog includes Janine v1 actions")
    func positiveActionCatalogIncludesJanineActions() {
        #expect(PositiveActionType.allCases == [
            .pcosFriendlyMeal,
            .highProteinMeal,
            .lowerCarbMeal,
            .walkMovement,
            .stressReduction,
            .goodSleep,
            .supplementsTaken,
            .cycleSupportiveSigns,
        ])
    }

    @Test("Positive action recommendations rank severe pain toward rest and stress support")
    func positiveActionRecommendationsRankPainSupport() {
        let symptoms = [
            SymptomEntry(date: Date(), type: .cramps, severity: 5),
            SymptomEntry(date: Date(), type: .fatigue, severity: 2),
        ]

        let recommendations = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 2,
            symptoms: symptoms,
            completedActions: []
        )

        #expect(recommendations.map(\.action).prefix(3).contains(.stressReduction))
        #expect(recommendations.map(\.action).prefix(3).contains(.goodSleep))
        #expect(recommendations.first?.reason.localizedCaseInsensitiveContains("cramps") == true)
    }

    @Test("Positive action recommendations rank luteal metabolic support before generic actions")
    func positiveActionRecommendationsRankLutealMetabolicSupport() {
        let symptoms = [
            SymptomEntry(date: Date(), type: .cravings, severity: 4),
            SymptomEntry(date: Date(), type: .energyCrash, severity: 4),
        ]

        let recommendations = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 22,
            symptoms: symptoms,
            completedActions: [.highProteinMeal]
        )

        #expect(recommendations.first?.action == .lowerCarbMeal)
        #expect(!recommendations.map(\.action).prefix(3).contains(.highProteinMeal))
        #expect(recommendations.first?.reason.localizedCaseInsensitiveContains("cravings") == true)
    }

    @Test("Positive action recommendations exclude completed actions and stay deterministic without context")
    func positiveActionRecommendationsExcludeCompletedAndRemainStable() {
        let completed = Set(PositiveActionType.allCases.dropLast())

        let recommendations = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: nil,
            symptoms: [],
            completedActions: completed
        )

        #expect(recommendations.map(\.action) == [.cycleSupportiveSigns])
        #expect(recommendations.first?.reason.localizedCaseInsensitiveContains("quick supportive action") == true)
    }

    @Test("Positive action recommendations respect cycle day phase boundaries")
    func positiveActionRecommendationsRespectCycleDayBoundaries() {
        let early = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 7,
            symptoms: [],
            completedActions: []
        )
        let follicular = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 8,
            symptoms: [],
            completedActions: []
        )
        let lateFollicular = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 15,
            symptoms: [],
            completedActions: []
        )
        let luteal = PositiveActionRecommendationEngine.rankedRecommendations(
            cycleDay: 16,
            symptoms: [],
            completedActions: []
        )

        #expect(early.first?.action == .stressReduction)
        #expect(follicular.first?.action == .walkMovement)
        #expect(lateFollicular.first?.action == .walkMovement)
        #expect(luteal.first?.action == .highProteinMeal)
    }
}
