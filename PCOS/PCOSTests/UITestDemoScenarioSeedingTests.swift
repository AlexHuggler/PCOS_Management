import Testing
import Foundation
import SwiftData
import UIKit
@testable import PCOS

@Suite("UI Test Demo Scenario Seeding", .serialized)
@MainActor
struct UITestDemoScenarioSeedingTests {
    @Test("All demo scenarios can seed engine-generated insights for UI coverage")
    func allDemoScenariosGeneratePersistedInsights() throws {
        for scenario in DemoDataScenario.allCases {
            let container = try TestHelpers.makeModelContainer()
            let context = container.mainContext

            try seedScenario(scenario, in: context)
            let generatedInsights = try InsightEngine(modelContext: context).generateInsights()
            #expect(!generatedInsights.isEmpty, "Expected \(scenario.rawValue) to generate at least one engine-backed insight.")

            for insight in generatedInsights {
                context.insert(insight)
            }
            try context.save()

            let persistedInsights = try context.fetch(
                FetchDescriptor<Insight>(
                    sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
                )
            )

            #expect(persistedInsights.count == generatedInsights.count)
            #expect(persistedInsights.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(persistedInsights.allSatisfy { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(persistedInsights.allSatisfy { $0.dataPointsUsed > 0 })
            #expect(persistedInsights.allSatisfy { $0.confidence >= 0.3 })
        }
    }

    @Test("Changing the app language regenerates persisted insights in the new locale")
    func changingAppLanguageRelocalizesPersistedInsights() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try seedScenario(.symptomManagement, in: context)

        AppLanguage.fr.persist(defaults: defaults)
        AppLanguage.fr.applyLaunchOverride(defaults: defaults)

        let initialInsights = try persistFreshInsights(
            in: context,
            appLanguage: .fr,
            preferredLanguages: ["fr_FR"]
        )
        InsightLocalizationRefreshService.markCurrentLanguage(
            defaults: defaults,
            appLanguage: .fr,
            preferredLanguages: ["fr_FR"]
        )

        let localizedRegenerator = InsightLocalizationRefreshService(
            modelContext: context,
            defaults: defaults
        )

        AppLanguage.en.persist(defaults: defaults)
        AppLanguage.en.applyLaunchOverride(defaults: defaults)

        let didRefresh = try localizedRegenerator.refreshIfNeeded(
            appLanguage: .en,
            preferredLanguages: ["en_US"]
        )
        #expect(didRefresh)

        let refreshedInsights = try fetchInsights(from: context)
        #expect(refreshedInsights.count == initialInsights.count)

        let initialSummaries = summarizeInsights(initialInsights)
        let refreshedSummaries = summarizeInsights(refreshedInsights)

        #expect(initialSummaries.map(\.signature) == refreshedSummaries.map(\.signature))
        #expect(initialSummaries.map(\.displayText) != refreshedSummaries.map(\.displayText))
        #expect(defaults.string(forKey: InsightLocalizationRefreshService.defaultsKey) == "en")
    }

    @Test("Repeat meal fixture requires UI test mode and matches the sample photo hash")
    func repeatMealFixtureIsUITestOnlyAndMatchesSamplePhoto() throws {
        let container = try TestHelpers.makeModelContainer()
        let context = container.mainContext

        try CycleBalanceApp.seedRepeatMealSuggestionIfNeeded(
            in: context,
            arguments: ["SeedRepeatMealSuggestion"]
        )
        #expect(try context.fetch(FetchDescriptor<MealScanRepeatCacheRecord>()).isEmpty)

        try CycleBalanceApp.seedRepeatMealSuggestionIfNeeded(
            in: context,
            arguments: ["UITestMode", "SeedRepeatMealSuggestion"]
        )

        let record = try #require(context.fetch(FetchDescriptor<MealScanRepeatCacheRecord>()).first)
        let sourceMeal = try #require(context.fetch(FetchDescriptor<MealEntry>()).first)
        let normalizedImage = try MealScanImageNormalizer().normalizeJPEGData(from: UIImage())
        #expect(record.sourceMealID == sourceMeal.id)
        #expect(record.sourceImageHash == normalizedImage.sourceImageHash)
        #expect(record.mealName == "Reviewed lentil bowl")
    }

    private func seedScenario(
        _ scenario: DemoDataScenario,
        in context: ModelContext
    ) throws {
        var backup = DemoDataBuilder(calendar: referenceCalendar).makeBackup(
            for: scenario,
            referenceDate: referenceDate
        )
        backup.records.insights = []

        let importService = SettingsDataImportService(modelContext: context)
        _ = try importService.replaceAll(with: backup)
    }

    private func persistFreshInsights(
        in context: ModelContext,
        appLanguage: AppLanguage? = nil,
        preferredLanguages: [String]? = nil
    ) throws -> [Insight] {
        let generatedInsights: [Insight]
        if let appLanguage {
            let resolvedPreferredLanguages = preferredLanguages ?? [appLanguage.localeIdentifier ?? "en_US"]
            generatedInsights = try L10n.withOverrides(
                appLanguage: appLanguage,
                preferredLanguages: resolvedPreferredLanguages
            ) {
                try InsightEngine(modelContext: context).generateInsights()
            }
        } else {
            generatedInsights = try InsightEngine(modelContext: context).generateInsights()
        }
        for insight in generatedInsights {
            context.insert(insight)
        }
        try context.save()
        return try fetchInsights(from: context)
    }

    private func fetchInsights(from context: ModelContext) throws -> [Insight] {
        try context.fetch(
            FetchDescriptor<Insight>(
                sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
            )
        )
    }

    private func summarizeInsights(_ insights: [Insight]) -> [(signature: String, displayText: String)] {
        insights
            .sorted {
                if $0.insightType.rawValue != $1.insightType.rawValue {
                    return $0.insightType.rawValue < $1.insightType.rawValue
                }
                if $0.dataPointsUsed != $1.dataPointsUsed {
                    return $0.dataPointsUsed < $1.dataPointsUsed
                }
                return $0.confidence < $1.confidence
            }
            .map { insight in
                let roundedConfidence = Int((insight.confidence * 1000).rounded())
                let signature = "\(insight.insightType.rawValue)|\(insight.dataPointsUsed)|\(roundedConfidence)"
                let displayText = "\(insight.title)|\(insight.content)"
                return (signature, displayText)
            }
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "UITestDemoScenarioSeedingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private var referenceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_773_878_400) // 2026-03-15 12:00:00 UTC
    }
}
