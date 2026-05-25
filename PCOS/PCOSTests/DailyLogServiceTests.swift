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
}
