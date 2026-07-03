import Foundation
import Testing
@testable import PCOS

@Suite("Review Prompt Service", .serialized)
@MainActor
struct ReviewPromptServiceTests {
    @Test("Log saves do not prompt before a seven-day streak")
    func logSavesDoNotPromptBeforeSevenDayStreak() throws {
        let container = try TestHelpers.makeModelContainer()
        let defaults = makeDefaults()
        var promptCount = 0

        let didSchedule = ReviewPromptService.requestReviewIfEligible(
            modelContext: container.mainContext,
            moment: .logSaved,
            defaults: defaults,
            delay: 0
        ) {
            promptCount += 1
        }

        #expect(!didSchedule)
        #expect(promptCount == 0)
        #expect(!defaults.bool(forKey: ReviewPromptService.promptedDefaultsKey))
    }

    @Test("First insight prompt fires once and persists the prompt flag")
    func firstInsightPromptFiresOnce() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let defaults = makeDefaults()
        var promptCount = 0

        context.insert(Insight(
            insightType: .cyclePattern,
            title: "Pattern found",
            content: "Your recent logs are ready to review.",
            confidence: 0.82,
            dataPointsUsed: 7
        ))
        try context.save()

        let firstSchedule = ReviewPromptService.requestReviewIfEligible(
            modelContext: context,
            moment: .firstInsight,
            defaults: defaults,
            delay: 0
        ) {
            promptCount += 1
        }
        let secondSchedule = ReviewPromptService.requestReviewIfEligible(
            modelContext: context,
            moment: .firstInsight,
            defaults: defaults,
            delay: 0
        ) {
            promptCount += 1
        }

        #expect(firstSchedule)
        #expect(!secondSchedule)
        #expect(promptCount == 1)
        #expect(defaults.bool(forKey: ReviewPromptService.promptedDefaultsKey))
    }

    @Test("Seven-day logging streak is a high-value prompt moment")
    func sevenDayLoggingStreakPromptsOnce() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let defaults = makeDefaults()
        var promptCount = 0
        let calendar = Calendar.current

        for offset in 0..<7 {
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: Date()))
            context.insert(SymptomEntry(date: date, type: .fatigue, severity: 2))
        }
        try context.save()

        let didSchedule = ReviewPromptService.requestReviewIfEligible(
            modelContext: context,
            moment: .logSaved,
            defaults: defaults,
            delay: 0
        ) {
            promptCount += 1
        }

        #expect(didSchedule)
        #expect(promptCount == 1)
        #expect(defaults.bool(forKey: ReviewPromptService.promptedDefaultsKey))
    }

    @Test("Paywall success does not request an App Store review")
    func paywallSuccessDoesNotRequestReview() throws {
        let root = try TestHelpers.projectRoot(from: #filePath)
        let source = try String(contentsOf: root.appendingPathComponent("PCOS/PCOS/Core/StoreKit/PaywallView.swift"))

        #expect(!source.contains("ReviewPromptService.requestReviewIfEligible"))
    }

    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "PCOS.ReviewPromptServiceTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
