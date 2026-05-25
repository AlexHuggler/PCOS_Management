import SwiftUI
import SwiftData
import os

@Observable
@MainActor
final class InsightsViewModel {
    typealias InsightsGenerator = () throws -> [Insight]
    private static let firstVisitTipKey = "insights.firstVisitTipShown"

    private let modelContext: ModelContext
    private let generateInsights: InsightsGenerator
    private let planner = InsightPresentationPlanner()
    private let defaults: UserDefaults

    var insights: [Insight] = []
    var isGenerating = false
    var errorMessage: String?
    var readiness: InsightsDataReadiness = .empty

    init(
        modelContext: ModelContext,
        insightGenerator: InsightsGenerator? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        if let insightGenerator {
            self.generateInsights = insightGenerator
        } else {
            let engine = InsightEngine(modelContext: modelContext)
            self.generateInsights = { try engine.generateInsights() }
        }
    }

    /// Progress description shown during generation.
    var generationProgress: String?

    var shouldShowFirstVisitTip: Bool {
        !defaults.bool(forKey: Self.firstVisitTipKey)
    }

    var completedCycleCount: Int {
        readiness.completedCycles
    }

    /// Generate new insights via the engine, persist them, and refresh the local list.
    func refreshInsights() async {
        isGenerating = true
        generationProgress = L10n.string("Analyzing your data...", defaultValue: "Analyzing your data...")
        defer {
            isGenerating = false
            generationProgress = nil
        }
        errorMessage = nil

        do {
            // Yield to let the UI update before heavy computation
            await Task.yield()

            let newInsights = try generateInsights()

            generationProgress = L10n.string("Saving insights...", defaultValue: "Saving insights...")
            await Task.yield()

            for insight in newInsights {
                modelContext.insert(insight)
            }
            try modelContext.save()
            InsightLocalizationRefreshService.markCurrentLanguage()
            Logger.database.info("InsightsViewModel: Saved \(newInsights.count) new insights")
            fetchExistingInsights()
            InsightRefreshCoordinator.clear()
        } catch {
            modelContext.rollback()
            Logger.database.error("InsightsViewModel: Failed to refresh insights: \(error.localizedDescription)")
            errorMessage = Self.userFacingMessage(for: error)
            readiness = fetchDataReadiness()
        }
    }

    func loadInsights(forceRefresh: Bool = false) async {
        fetchExistingInsights()

        guard forceRefresh || insights.isEmpty || InsightRefreshCoordinator.needsRefresh() else {
            return
        }

        await refreshInsights()
    }

    /// Load all persisted insights, sorted by generatedDate descending.
    func fetchExistingInsights() {
        let descriptor = FetchDescriptor<Insight>(
            sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
        )
        do {
            insights = try modelContext.fetch(descriptor)
            errorMessage = nil
        } catch {
            Logger.database.error("InsightsViewModel: Failed to fetch insights: \(error.localizedDescription)")
            insights = []
            errorMessage = Self.userFacingMessage(for: error)
        }

        readiness = fetchDataReadiness()
    }

    func presentationPlan(
        preferences: InsightAudiencePreferences,
        isPremium: Bool
    ) -> InsightPresentationPlan {
        planner.makePlan(
            insights: insights,
            preferences: preferences,
            isPremium: isPremium
        )
    }

    func emptyStateContent(
        preferences: InsightAudiencePreferences
    ) -> InsightEmptyStateContent {
        planner.emptyStateContent(
            readiness: readiness,
            preferences: preferences
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return L10n.string(
            "Couldn't refresh insights right now. Please try again.",
            defaultValue: "Couldn't refresh insights right now. Please try again."
        )
    }

    private func fetchDataReadiness() -> InsightsDataReadiness {
        let cycles = (try? modelContext.fetch(FetchDescriptor<Cycle>())) ?? []
        let symptoms = (try? modelContext.fetch(FetchDescriptor<SymptomEntry>())) ?? []
        let meals = (try? modelContext.fetch(FetchDescriptor<MealEntry>())) ?? []
        let supplements = (try? modelContext.fetch(FetchDescriptor<SupplementLog>())) ?? []
        let dailyLogs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let bloodSugarReadings = (try? modelContext.fetch(FetchDescriptor<BloodSugarReading>())) ?? []

        return InsightsDataReadiness(
            completedCycles: cycles.filter { !$0.isPredicted && ($0.lengthDays != nil || $0.manualCycleLengthOverrideDays != nil) }.count,
            symptomDays: distinctDayCount(in: symptoms.map(\.date)),
            mealDays: distinctDayCount(in: meals.map(\.timestamp)),
            supplementDays: distinctDayCount(in: supplements.map(\.date)),
            dailyLogDays: distinctDayCount(in: dailyLogs.map(\.date)),
            bloodSugarDays: distinctDayCount(in: bloodSugarReadings.map(\.timestamp))
        )
    }

    private func distinctDayCount(in dates: [Date]) -> Int {
        let calendar = Calendar.current
        return Set(dates.map { calendar.startOfDay(for: $0) }).count
    }

    func markFirstVisitTipShown() {
        defaults.set(true, forKey: Self.firstVisitTipKey)
    }
}

@MainActor
struct InsightLocalizationRefreshService {
    static let defaultsKey = "insights.localizedLanguage"

    private struct Snapshot {
        let id: UUID
        let generatedDate: Date
        let insightType: InsightType
        let title: String
        let content: String
        let scientificContent: String?
        let confidence: Double
        let dataPointsUsed: Int
        let actionable: Bool
        let relatedSymptoms: [String]
        let phaseContext: CyclePhase?
        let recommendedActions: [String]
        let learnMoreTopic: String?

        init(_ insight: Insight) {
            id = insight.id
            generatedDate = insight.generatedDate
            insightType = insight.insightType
            title = insight.title
            content = insight.content
            scientificContent = insight.scientificContent
            confidence = insight.confidence
            dataPointsUsed = insight.dataPointsUsed
            actionable = insight.actionable
            relatedSymptoms = insight.relatedSymptoms
            phaseContext = insight.phaseContext
            recommendedActions = insight.recommendedActions
            learnMoreTopic = insight.learnMoreTopic
        }

        func restore() -> Insight {
            Insight(
                id: id,
                generatedDate: generatedDate,
                insightType: insightType,
                title: title,
                content: content,
                scientificContent: scientificContent,
                confidence: confidence,
                dataPointsUsed: dataPointsUsed,
                actionable: actionable,
                relatedSymptoms: relatedSymptoms,
                phaseContext: phaseContext,
                recommendedActions: recommendedActions,
                learnMoreTopic: learnMoreTopic
            )
        }
    }

    private let modelContext: ModelContext
    private let defaults: UserDefaults

    init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
    }

    func refreshIfNeeded(
        appLanguage: AppLanguage? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) throws -> Bool {
        let resolvedAppLanguage = appLanguage ?? AppLanguage.stored(defaults: defaults)
        let targetLanguage = Self.languageIdentifier(
            appLanguage: resolvedAppLanguage,
            preferredLanguages: preferredLanguages
        )

        guard defaults.string(forKey: Self.defaultsKey) != targetLanguage else {
            return false
        }

        return try regenerateInsights(
            appLanguage: resolvedAppLanguage,
            preferredLanguages: preferredLanguages
        )
    }

    func regenerateInsights(
        appLanguage: AppLanguage? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) throws -> Bool {
        let resolvedAppLanguage = appLanguage ?? AppLanguage.stored(defaults: defaults)
        let targetLanguage = Self.languageIdentifier(
            appLanguage: resolvedAppLanguage,
            preferredLanguages: preferredLanguages
        )
        let previousLanguage = defaults.string(forKey: Self.defaultsKey)
        let existingInsights = try fetchExistingInsights()
        let snapshots = existingInsights.map(Snapshot.init)

        do {
            try deleteInsights(existingInsights)

            let regeneratedInsights = try L10n.withOverrides(
                appLanguage: resolvedAppLanguage,
                preferredLanguages: preferredLanguages
            ) {
                try InsightEngine(modelContext: modelContext).generateInsights()
            }
            for insight in regeneratedInsights {
                modelContext.insert(insight)
            }
            try modelContext.save()

            defaults.set(targetLanguage, forKey: Self.defaultsKey)
            Logger.database.info(
                "InsightLocalizationRefreshService: Regenerated \(regeneratedInsights.count) insights for language \(targetLanguage, privacy: .public)"
            )
            return !snapshots.isEmpty || !regeneratedInsights.isEmpty
        } catch {
            try restoreSnapshots(snapshots)
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            Logger.database.error(
                "InsightLocalizationRefreshService: Failed to regenerate localized insights: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    static func markCurrentLanguage(
        defaults: UserDefaults = .standard,
        appLanguage: AppLanguage? = nil,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        let resolvedAppLanguage = appLanguage ?? AppLanguage.stored(defaults: defaults)
        defaults.set(
            languageIdentifier(appLanguage: resolvedAppLanguage, preferredLanguages: preferredLanguages),
            forKey: defaultsKey
        )
    }

    private func fetchExistingInsights() throws -> [Insight] {
        try modelContext.fetch(
            FetchDescriptor<Insight>(
                sortBy: [SortDescriptor(\.generatedDate, order: .reverse)]
            )
        )
    }

    private func deleteInsights(_ insights: [Insight]) throws {
        for insight in insights {
            modelContext.delete(insight)
        }
        try modelContext.save()
    }

    private func restoreSnapshots(_ snapshots: [Snapshot]) throws {
        guard !snapshots.isEmpty else { return }

        modelContext.rollback()
        for snapshot in snapshots {
            modelContext.insert(snapshot.restore())
        }
        try modelContext.save()
    }

    private static func languageIdentifier(
        appLanguage: AppLanguage,
        preferredLanguages: [String]
    ) -> String {
        L10n.resolvedLanguageIdentifier(
            for: appLanguage,
            preferredLanguages: preferredLanguages
        )
    }
}
